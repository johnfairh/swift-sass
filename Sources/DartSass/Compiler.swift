//
//  Compiler.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import struct Foundation.URL
import class Foundation.FileManager // cwd
import Dispatch
@_spi(AsyncChannel) import NIOCore
import NIOPosix
import Logging
@_exported import Sass

// Compiler -- interface, control state machine
// CompilerChild -- Child process, NIO reads and writes
// CompilerWork -- Sass stuff, protocol, job management
// CompilerRequest -- job state, many, managed by CompilerWork

/// A Sass compiler that uses Dart Sass as an embedded child process.
///
/// The Dart Sass compiler is bundled with this package for macOS and Ubuntu 64-bit Linux.
/// For other platforms you need to supply this separately, see
/// [the readme](https://github.com/johnfairh/swift-sass/blob/main/README.md).
///
/// Some debug logging is available via `Compiler.logger`.
///
/// You must shut down the compiler using `shutdownGracefully(...)`
/// or `syncShutdownGracefully()` otherwise the program will exit.
///
/// ## Custom importer resolution
///
/// Dart Sass uses a different algorithm to LibSass for processing imports. Each stylesheet is associated
/// with the importer that loaded it -- this may be an internal or hidden filesystem importer.  Import resolution
/// then goes:
/// * Consult the stylesheet's associated importer.
/// * Consult every `DartSass.ImportResolver` given to the compiler, first the global list then the
///   per-compilation list, in order within each list.
public actor Compiler {
    private let eventLoopGroup: ProvidedEventLoopGroup

    /// NIO event loop we're bound to.  Internal for test.
    let eventLoop: EventLoop // XXX

    enum State {
        /// No child, new jobs wait for state change.
        case initializing
        /// Child up, checking it's working before accepting compilations.
        case checking(CompilerChild)
        /// Child is running and accepting compilation jobs.
        case running(CompilerChild)
        /// Child is broken.  Fail new jobs with the error.  Reinit permitted.
        case broken(any Error)
        /// System is shutting down, ongoing jobs will complete but no new. XXX can be ->init too
        /// Shutdown will be done when state changes.
        case quiescing(CompilerChild)
        /// Compiler is shut down.  Fail new jobs.
        case shutdown

        var child: CompilerChild? {
            switch self {
            case .checking(let c), .running(let c), .quiescing(let c): return c
            case .initializing, .broken, .shutdown: return nil
            }
        }
    }

    /// Compiler process state.  Internal for test access.
    private(set) var state: State

    /// Jobs waiting on compiler state change.
    private var stateWaitingQueue: ContinuationQueue2

    /// Change the compiler state and resume anyone waiting.
    func setState(_ state: State) {
        self.state = state
        Task { await stateWaitingQueue.kick() } // XXX is this OK?, better make thing async?
    }

    /// Suspend the current task until the compiler state changes
    func waitForStateChange() async {
        await stateWaitingQueue.wait()
    }

    /// Number of times we've tried to start the embedded Sass compiler.
    private(set) var startCount: Int

    /// The path of the compiler program
    private let embeddedCompilerFileURL: URL

    /// The actual compilation work
    private var work: CompilerWork!

    /// Most recently received version of compiler
    private var versions: Versions?

    /// Use the bundled Dart Sass compiler as the Sass compiler.
    ///
    /// The bundled Dart Sass compiler is built on macOS (11.6) or Ubuntu (20.04) Intel 64-bit.
    /// If you are running on another operating system then use `init(eventLoopGroupProvider:embeddedCompilerFileURL:timeout:messageStyle:verboseDeprecations:suppressDependencyWarnings:importers:functions:)`
    /// supplying the path of the correct Dart Sass compiler.
    ///
    /// Initialization continues asynchronously after the initializer completes; failures are reported
    /// when the compiler is next used.
    ///
    /// You must shut down the compiler with `shutdownGracefully()` or
    /// `syncShutdownGracefully()` before letting it go out of scope.
    ///
    /// - parameter eventLoopGroupProvider: NIO `EventLoopGroup` to use: either `.shared` to use
    ///   an existing group or `.createNew` to create and manage a new event loop.  Default is `.createNew`.
    /// - parameter timeout: Maximum time in seconds allowed for the embedded
    ///   compiler to compile a stylesheet.  Detects hung compilers.  Default is a minute; set
    ///   -1 to disable timeouts.
    /// - parameter messageStyle: Style for diagnostic message descriptions.  Default is `.plain`.
    /// - parameter verboseDeprecations: Control for deprecation warning messages.
    ///   If `false` then the compiler will send only a few deprecation warnings of the same type.
    ///   Default is `false` meaning repeated deprecation warnings _are_ suppressed.
    /// - parameter suppressDependencyWarnings: Control for warning messages from Sass files
    ///   loaded by importers other than the importer used to load the main Sass file.
    ///   Default is `false` meaning such warnings _are not_ suppressed.
    /// - parameter importers: Rules for resolving `@import` that cannot be satisfied relative to
    ///   the source file's URL, used for all this compiler's compilations.
    /// - parameter functions: Sass functions available to all this compiler's compilations.
    /// - throws: `LifecycleError` if the program can't be found.
    public init(eventLoopGroupProvider: NIOEventLoopGroupProvider = .createNew,
                timeout: Int = 60,
                messageStyle: CompilerMessageStyle = .plain,
                verboseDeprecations: Bool = false,
                suppressDependencyWarnings: Bool = false,
                importers: [ImportResolver] = [],
                functions: SassAsyncFunctionMap = [:]) throws {
        let url = try DartSassEmbedded.getURL()
        self.init(eventLoopGroupProvider: eventLoopGroupProvider,
                  embeddedCompilerFileURL: url,
                  timeout: timeout,
                  messageStyle: messageStyle,
                  verboseDeprecations: verboseDeprecations,
                  suppressDependencyWarnings: suppressDependencyWarnings,
                  importers: importers,
                  functions: functions)
    }

    /// Use a program as the Sass embedded compiler.
    ///
    /// Initialization continues asynchronously after the initializer returns; failures are reported
    /// when the compiler is next used.
    ///
    /// You must shut down the compiler with `shutdownGracefully()` or
    /// `syncShutdownGracefully()` before letting it go out of scope.
    ///
    /// - parameter eventLoopGroupProvider: NIO `EventLoopGroup` to use: either `.shared` to use
    ///   an existing group or `.createNew` to create and manage a new event loop.  Default is `.createNew`.
    /// - parameter embeddedCompilerFileURL: Path of `dart-sass-embedded`
    ///   or something else that speaks the Sass embedded protocol.  Check [the readme](https://github.com/johnfairh/swift-sass/blob/main/README.md)
    ///   for the supported protocol versions.
    /// - parameter timeout: Maximum time in seconds allowed for the embedded
    ///   compiler to compile a stylesheet.  Detects hung compilers.  Default is a minute; set
    ///   -1 to disable timeouts.
    /// - parameter messageStyle: Style for diagnostic message descriptions.  Default is `.plain`.
    /// - parameter verboseDeprecations: Control for deprecation warning messages.
    ///   If `false` then the compiler will send only a few deprecation warnings of the same type.
    ///   Default is `false` meaning repeated deprecation warnings _are_ suppressed.
    /// - parameter suppressDependencyWarnings: Control for warning messages from Sass files
    ///   loaded by importers other than the importer used to load the main Sass file.
    ///   Default is `false` meaning such warnings _are not_ suppressed.
    /// - parameter importers: Rules for resolving `@import` that cannot be satisfied relative to
    ///   the source file's URL, used for all this compiler's compilations.
    /// - parameter functions: Sass functions available to all this compiler's compilations.
    public init(eventLoopGroupProvider: NIOEventLoopGroupProvider = .createNew,
                embeddedCompilerFileURL: URL,
                timeout: Int = 60,
                messageStyle: CompilerMessageStyle = .plain,
                verboseDeprecations: Bool = false,
                suppressDependencyWarnings: Bool = false,
                importers: [ImportResolver] = [],
                functions: SassAsyncFunctionMap = [:]) {
        precondition(embeddedCompilerFileURL.isFileURL, "Not a file URL: \(embeddedCompilerFileURL)")
        self.eventLoopGroup = ProvidedEventLoopGroup(eventLoopGroupProvider) // XXX need to shut this MF down
        eventLoop = self.eventLoopGroup.any()
        work = nil
        self.embeddedCompilerFileURL = embeddedCompilerFileURL
        state = .shutdown
        startCount = 0
        // self init done
        work = CompilerWork(eventLoop: eventLoop,
                            resetRequest: { [unowned self] in handleError($0) },
                            timeout: timeout,
                            settings: .init(messageStyle: messageStyle,
                                            verboseDeprecations: verboseDeprecations,
                                            suppressDependencyWarnings: suppressDependencyWarnings),
                            importers: importers,
                            functions: functions)
    }

    deinit {
        guard case .shutdown = state else {
            preconditionFailure("Compiler not shutdown: \(state)")
        }
    }

    /// Run and maintain the Sass compiler.
    ///
    /// Cancelling this ``Task`` initiates a graceful exit of the compiler and causes the
    /// routine to return normally.
    ///
    /// The routine returns abnormally by throwing an error if there is something seriously
    /// wrong, for example the embedded compiler cannot start or the version is wrong.
    /// It's unlikely there's anything a software client can do to fix this kind of problem, but you
    /// are welcome to call `run()` again to have another go.
    ///
    /// Minor errors such as compiler process crashes or timeouts do not cause the routine
    /// to return, these are handled internally.
    func run() async throws {
        guard case .shutdown = state else { // XXX or broken
            preconditionFailure("Bad state to run Sass compiler: \(state)")
        }

        let initThread = NIOThreadPool(numberOfThreads: 1)
        initThread.start()

        // XXX might need cancellation check to catch Task cancellation during init
        //        debug("Shutdown during startup, deferring") not exactly that
        do {
            while !Task.isCancelled {
                setState(.initializing)

                precondition(!work.hasActiveRequests)
                startCount += 1

                // Get onto the thread to start the child and bootstrap the NIO connections.
                let child = try await initThread.runIfActive(eventLoop: eventLoop) { [self] in
                    try CompilerChild(eventLoop: eventLoop,
                                      fileURL: embeddedCompilerFileURL,
                                      work: work,
                                      errorHandler: { [unowned self] in await self.handleError($0) })
                }.get()

                try await child.addChannelHandlers()

                debug("Compiler is started, starting healthcheck")
                setState(.checking(child))

                // Kick off the child task to deal with compiler responses
                async let messageLoopTask: Void = runMessageLoop()

                let versions = try await sendVersionRequest(to: child)
                try versions.check()
                self.versions = versions

                // Might already be quiescing here, race with msgloop task
                if case .checking = state {
                    setState(.running(child))
                    await waitForStateChange()
                }
                await messageLoopTask

                guard case .quiescing = state else {
                    preconditionFailure("Expected quiescing, is \(state)")
                }
                let reason = Task.isCancelled ? "shutdown" : "restart"
                debug("Quiescing work for \(reason)")
                await work.quiesce()
                debug("No outstanding compilations, shutting down compiler")
                // XXX child.stopAndCancelWork ?? tbd

                // go round again, back to initting
            }
        } catch {
            debug("Can't start the compiler at all: \(error)")
            await state.child?.stopAndCancelWork(with: error)
            setState(.broken(error))
        }

        // Clean up and propagate errors
        // Should be `defer` but Swift cba to do async there...
        try? await initThread.shutdownGracefully()

        if case let .broken(error) = state {
            throw error
        } else {
            setState(.shutdown)
        }
    }

    /// Deal with inbound messages.
    ///
    /// This is supposed to run as a structured child task of the `run()` task with cancellation propagation.
    private func runMessageLoop() async {
        let child = state.child!
        debug("MessageQueueTask in") // XXX bringup tracing
        await child.processMessages()
        debug("MessageQueueTask message-loop returned, cancelled = \(Task.isCancelled)")
        setState(.quiescing(child))
        debug("MessageQueueTask set quiescing")
    }

    /// Restart the embedded Sass compiler.
    ///
    /// Normally a single instance of the compiler's process persists across all invocations to
    /// `compile(...)` on this `Compiler` instance.   This method stops the current
    /// compiler process and starts a new one: the intended use is for compilers whose
    /// resource usage escalates over time and need calming down.  You probably don't need to
    /// call it.
    ///
    /// Any outstanding compilations are failed.
    public func reinit() async {
        await handleError(LifecycleError("User requested Sass compiler be reinitialized"))
    }

    /// The process ID of the embedded Sass compiler.
    ///
    /// Not normally needed; could be used to adjust resource usage or maybe send it a signal if stuck.
    /// The process ID is reported after waiting for any [re]initialization to complete; a value of `nil`
    /// means that the compiler is broken or shutdown.
    public var compilerProcessIdentifier: Int32? {
        get async {
            while true {
                switch state {
                case .broken, .shutdown:
                    return nil
                case .checking(let child), .running(let child), .quiescing(let child):
                    return child.processIdentifier
                case .initializing:
                    await waitForStateChange()
                }
            }
        }
    }

    /// The name of the underlying Sass implementation.  `nil` if unknown.
    public var compilerName: String? {
        get async {
            await stableVersions?.compilerName
        }
    }

    /// The version of the underlying Sass implementation.  For Dart Sass and LibSass this is in
    /// [semver](https://semver.org/spec/v2.0.0.html) format. `nil` if unknown (never got a version).
    public var compilerVersion: String? {
        get async {
            await stableVersions?.compilerVersionString
        }
    }

    /// The version of the package implementing the compiler side of the embedded Sass protocol.
    /// Probably in [semver](https://semver.org/spec/v2.0.0.html) format.
    /// `nil` if unknown (never got a version).
    public var compilerPackageVersion: String? {
        get async {
            await stableVersions?.packageVersionString
        }
    }

    private var stableVersions: Versions? {
        get async {
            while true {
                switch state {
                case .broken, .shutdown, .running, .quiescing:
                    return versions
                case .checking, .initializing:
                    await waitForStateChange()
                }
            }
        }
    }

    /// Logger for the module.
    ///
    /// A [swift-log](https://github.com/apple/swift-log) `Logger`.
    ///
    /// Produces goodpath protocol and compiler lifecycle tracing at `Logger.Level.debug` log level,
    /// approx 300 bytes per compile request.
    ///
    /// Produces protocol and lifecycle error reporting at `Logger.Level.debug` log level for conditions
    /// that are also reported through errors thrown from some API.
    public static var logger = Logger(label: "dart-sass")

    private func debug(_ msg: @autoclosure () -> String) {
        Compiler.logger.debug(.init(stringLiteral: msg()))
    }

    // MARK: Compilation entrypoints

    /// Compile to CSS from a stylesheet file.
    ///
    /// - parameters:
    ///   - fileURL: The URL of the file to compile.  The file extension determines the
    ///     expected syntax of the contents, so it must be css/scss/sass.
    ///   - outputStyle: How to format the produced CSS.  Default `.expanded`.
    ///   - sourceMapStyle: Kind of source map to create for the CSS.  Default `.separateSources`.
    ///   - includeCharset: If the output is non-ASCII, whether to include `@charset`.
    ///   - importers: Rules for resolving `@import` etc. for this compilation, used in order after
    ///     `fileURL`'s directory and any set globally..  Default none.
    ///   - functions: Functions for this compilation, overriding any with the same name previously
    ///     set globally. Default none.
    /// - throws: `CompilerError` if there is a critical error with the input, for example a syntax error.
    ///           Some other kind of error if something goes wrong  with the compiler infrastructure itself.
    /// - returns: `CompilerResults` with CSS and optional source map.
    public func compile(fileURL: URL,
                        outputStyle: CssStyle = .expanded,
                        sourceMapStyle: SourceMapStyle = .separateSources,
                        includeCharset: Bool = false,
                        importers: [ImportResolver] = [],
                        functions: SassAsyncFunctionMap = [:]) async throws -> CompilerResults {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                try await waitUntilReadyToCompile()
                let msg = work.startCompilation(input: .path(fileURL.path),
                                                outputStyle: outputStyle,
                                                sourceMapStyle: sourceMapStyle,
                                                includeCharset: includeCharset,
                                                importers: .init(importers),
                                                functions: functions,
                                                continuation: continuation)
                // if we move the WorkActive queue into this actor then 'state'
                // gets synchronized with it.  We still have the next line, that
                // shoots off to the child's executor, meaning that a statechange
                // to quiescing with or without a 'handleError'->'stopAndCancelWork'
                // can occur.  If SACW happens then we're good: the 'send' is ignored
                // because 'child.stopped' and the req is cleaned up by SACW.
                // If we just have the 'run' task cancelled then we get 'quiescing',
                // work.quiesce will know to wait for 1 and we'll actually be good too,
                // because SACW won't happen so the child will be happy.
                //
                // huh - the key gain is to synchronize the work queue with state, not
                // doing that means we can add things to the queue AFTER SACW which will
                // be stuck forever
                //
                // The dual behaviour, task.cancel vs. error, is in fact exactly what the
                // old 'dignified shutdown' did, allowing existing work to run.  So fine,
                // we should lean in to that.
                //
                // XXX big tbd here is what the NIO stream does with cancellation, it may just
                // XXX abort meaning there is no gracefulness to be had and we have to throw
                // XXX in the SACW in all cases.
                await state.child!.send(message: msg)
            }
        }
    }

    /// Compile to CSS from an inline stylesheet.
    ///
    /// - parameters:
    ///   - string: The stylesheet text to compile.
    ///   - syntax: The syntax of `string`, default `.scss`.
    ///   - url: The absolute URL to associate with `string`, from where it was loaded.
    ///     Default `nil` meaning unknown.
    ///   - importer: Rule to resolve `@import` etc. from `string` relative to `url`.  Default `nil`
    ///     meaning no filesystem importer is configured.  Unlike some Sass implementations this means that
    ///     imports of files from the current directory don't work automatically: add a loadpath to `importers`.
    ///   - outputStyle: How to format the produced CSS.  Default `.expanded`.
    ///   - sourceMapStyle: Kind of source map to create for the CSS.  Default `.separateSources`.
    ///   - includeCharset: If the output is non-ASCII, whether to include `@charset`.
    ///   - importers: Rules for resolving `@import` etc. for this compilation, used in order after
    ///     any set globally.  Default none.
    ///   - functions: Functions for this compilation, overriding any with the same name previously
    ///     set globally.  Default none.
    /// - throws: `CompilerError` if there is a critical error with the input, for example a syntax error.
    ///           Some other kind of error if something goes wrong  with the compiler infrastructure itself.
    /// - returns: `CompilerResults` with CSS and optional source map.
    public func compile(string: String,
                        syntax: Syntax = .scss,
                        url: URL? = nil,
                        importer: ImportResolver? = nil,
                        outputStyle: CssStyle = .expanded,
                        sourceMapStyle: SourceMapStyle = .separateSources,
                        includeCharset: Bool = false,
                        importers: [ImportResolver] = [],
                        functions: SassAsyncFunctionMap = [:]) async throws -> CompilerResults {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                try await waitUntilReadyToCompile()
                let msg = work.startCompilation(
                    input: .string(.with { m in
                        m.source = string
                        m.syntax = .init(syntax)
                        url.map {
                            m.url = $0.absoluteString
                        }
                        importer.map {
                            m.importer = .init($0, id: CompilationRequest.baseImporterID)
                        }
                    }),
                    outputStyle: outputStyle,
                    sourceMapStyle: sourceMapStyle,
                    includeCharset: includeCharset,
                    importers: importers,
                    stringImporter: importer,
                    functions: functions,
                    continuation: continuation)
                await state.child!.send(message: msg)
            }
        }
    }

    private func waitUntilReadyToCompile() async throws {
        while true {
            switch state {
            case .broken(let error):
                // submitted while restarting the compiler; restart failed: fail
                throw LifecycleError("Sass compiler failed to start after unrecoverable rror: \(error)")

            case .shutdown:
                // submitted after/during shutdown: fail
                throw LifecycleError("Sass compiler is not started, not accepting work")

            case .initializing, .quiescing, .checking:
                // submitted while [re]starting the compiler: wait
                await waitForStateChange()

            case .running:
                // ready to go
                break
            }
        }
    }

    // MARK: Version query

    // Unit-test hook to inject/drop version request
    var versionsResponder: VersionsResponder? = nil

    private func sendVersionRequest(to child: CompilerChild) async throws -> Versions {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                guard case .checking(let child) = state else {
                    debug("Cancelling versions query")
                    throw CancellationError()
                }
                let msg = work.startVersionRequest(continuation: continuation)
                if let versionsResponder {
                    let rsp = await versionsResponder.provideVersions(msg: msg)
                    await child.receive(message: rsp)
                } else {
                    await child.send(message: msg)
                }
            }
        }
    }

    /// Central transport/protocol error detection and 'recovery'.
    ///
    /// Errors come from:
    /// 1. Write transport errors, reported by `CompilerChild.send(...)`
    /// 2. Read transport errors, reported by the `CompilerChild.processMessages(...)`
    /// 3. Protocol errors reported by the Sass compiler, from `CompilerWork.receieveGlobal(message:)`
    /// 4. Protocol errors detected by us, from `CompilationRequest.receive(message)`.
    /// 5. User-injected restarts, from `reinit()`.
    /// 6. Timeouts, from `CompilerWork`'s reset API.
    ///
    /// In all cases we brutally restart the compiler and fail back all the jobs.
    /// In the async world this is collapsing into "child?.SACW" which is good...
    func handleError(_ error: any Error) async {
        switch state {
        case .initializing:
            // Nothing to do, if something fails we'll notice
            break

        case .checking(let child):
            // Timeout or something while checking the version, kick the process
            // and let the init process handle the error.
            debug("Error while checking compiler, stopping it")
            await child.stopAndCancelWork(with: error)

        case .running(let child):
            debug("Restarting compiler from running")
            await child.stopAndCancelWork(with: error)
            // XXX hopefully that's it - channel will die and cause quiesce

        case .broken:
            // Not sure how this happens (reinit?)
            debug("Error (\(error)) while broken - doing nothing")

        case .quiescing(let child):
            // Corner/race stay in this state but try to hurry things along.
            debug("Error while quiescing, stopping compiler")
            await child.stopAndCancelWork(with: error)

        case .shutdown:
            // Nothing to do
            debug("Error (\(error)) while shutdown - doing nothing")
        }
    }

    // XXX then - compilerwork merge - closure for done to include book-keeping and continuation resumption
}

/// NIO layer
///
/// Looks after the actual child process.
/// Knows how to set up the channel pipeline.
/// Routes inbound messages to CompilerWork.
actor CompilerChild: ChannelInboundHandler {
    typealias InboundIn = Sass_EmbeddedProtocol_OutboundMessage

    /// Our event loop
    private let eventLoop: EventLoop
    /// The child process
    private let child: Exec.Child
    /// The work manager
    private let work: CompilerWork
    /// Error handling
    private let errorHandler: (Error) async -> Void
    /// Cancellation protocol
    private var stopping: Bool

    /// API
    nonisolated let processIdentifier: Int32

    /// Internal for test
    var channel: Channel {
        child.channel
    }

    /// The compiler's "Inbound" messages are our "Outbound" and vice-versa.
    private(set) var asyncChannel: NIOAsyncChannel<Sass_EmbeddedProtocol_OutboundMessage, Sass_EmbeddedProtocol_InboundMessage>!

    /// Create a new Sass compiler process.
    ///
    /// Must not be called in an event loop!  But I don't know how to check that.
    init(eventLoop: EventLoop, fileURL: URL, work: CompilerWork, errorHandler: @escaping (Error) async -> Void) throws {
        self.child = try Exec.spawn(fileURL, group: eventLoop)
        self.processIdentifier = child.process.processIdentifier
        self.eventLoop = eventLoop
        self.work = work
        self.errorHandler = errorHandler
        self.stopping = false

        // The termination handler is always called when the process ends.
        // Only cascade this up into a compiler restart when we're not already
        // stopping, ie. we didn't just ask the process to end.

        // This vs. `stopAndCancelWork()` vs. the eventLoop becoming invalid is still
        // racy because we don't flush out any pending call here before stopping the event loop.
        // Don't want to interlock it because (a) more quiesce phases and (b) don't trust
        // the library to guarantee a timely call.
        self.child.process.terminationHandler = { _ in
            Task { await self.childTerminationHandler() }
        }
    }

    private func childTerminationHandler() async {
        if !stopping {
            await errorHandler(ProtocolError("Compiler process exitted unexpectedly"))
        }
    }

    /// Connect Sass protocol handlers.
    func addChannelHandlers() async throws  { // XXX move EVentLoop to param here?
        try await ProtocolWriter.addHandler(to: channel).get()
        try await ProtocolReader.addHandler(to: channel).get()
        asyncChannel = try await eventLoop.submit { [channel] in
            try NIOAsyncChannel(synchronouslyWrapping: channel)
        }.get()
    }

    /// Send a message to the Sass compiler with error detection.
    func send(message: Sass_EmbeddedProtocol_InboundMessage) async {
        precondition(asyncChannel != nil)
        guard !stopping else {
            // Race condition of compiler reset vs. async host function
            return
        }

        do {
            try await asyncChannel.outboundWriter.write(message) // == writeAndFlush
        } catch {
            // tough to reliably hit this error.  if we kill the process while trying to write to
            // it we get this on Darwin maybe 20% of the time vs. the write working, leaving the
            // sigchld handler to clean up.
            await errorHandler(ProtocolError("Write to Sass compiler failed: \(error)"))
        }
    }

//    /// Send a bunch of messages in order. XXX what is this for??
//    func send(messages: [Sass_EmbeddedProtocol_InboundMessage]) async {
//        for m in messages {
//            await send(message: m)
//        }
//    }

    /// Process messages from the child until it dies or the task is cancelled
    func processMessages() async {
        precondition(asyncChannel != nil)
        do {
            for try await message in asyncChannel.inboundStream {
                await receive(message: message)
            }
        } catch {
            /// Called from NIO up the stack if something goes wrong with the inbound connection.... maybe ... XXX
            await errorHandler(ProtocolError("Read from Sass compiler failed: \(error)"))
        }
    }

    /// Split out for test access
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) async {
        guard !stopping else {
            // I don't really understand how this happens but have test proof on Linux
            // on Github Actions env, seems to be an inbound buffer where something can
            // get caught and appear even after the child process is terminated.
            Compiler.logger.debug("Rx: \(message.logMessage) while stopping, discarding")
            return
        }
        Compiler.logger.debug("Rx: \(message.logMessage)")

        do {
            if let response = try await work.receive(message: message) {
                await send(message: response)
            }
        } catch {
            await errorHandler(error)
        }
    }

    /// Shutdown point - stop the child process to clean up the channel.
    /// Cascade to `CompilerWork` so it stops waiting for responses -- this is a little bit spaghetti but it's helpful
    /// to keep them tightly bound.
    func stopAndCancelWork(with error: Error? = nil) {
        stopping = true
        child.process.terminationHandler = nil
        child.terminate()
        // asyncChannel = nil ?? XXX
        if let error {
            work.cancelAllActive(with: error)
        }
    }
}

/// Version response injection for testing
protocol VersionsResponder {
    func provideVersions(msg: Sass_EmbeddedProtocol_InboundMessage) async -> Sass_EmbeddedProtocol_OutboundMessage
}
