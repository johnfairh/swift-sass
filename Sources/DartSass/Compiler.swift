//
//  Compiler.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import struct Foundation.URL
import class Foundation.FileManager // cwd
@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NIOPosix // NIOThreadPool, NIOPipeBootstrap
import Logging
@_exported import Sass

// Compiler -- interface, control state machine
// CompilerChild -- Child process, NIO reads and writes
// CompilerRequest -- job state, many, managed by CompilerWork

/// A Sass compiler that uses Dart Sass as an embedded child process.
///
/// The Dart Sass compiler is bundled with this package for macOS and Ubuntu 64-bit Linux.
/// For other platforms you need to supply this separately, see
/// [the readme](https://github.com/johnfairh/swift-sass/blob/main/README.md).
///
/// Some debug logging is available via `Compiler.logger`.
///
/// You must shut down the compiler using `shutdownGracefully(...)` before the last reference
/// to the object is released otherwise the program will exit.
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
    let eventLoop: EventLoop // XXX move to run() unless tests do need somehow

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
    private var stateWaitingQueue: ContinuationQueue

    /// Change the compiler state and resume anyone waiting.
    private func setState(_ state: State, fn: String = #function) {
//        debug("\(fn): \(self.state) -> \(state)")
        self.state = state
        Task.detached { await self.stateWaitingQueue.kick() }
    }

    /// Suspend the current task until the compiler state changes
    private func waitForStateChange() async {
        await stateWaitingQueue.wait()
    }

    private var runTask: Task<Void, Never>?

    /// Number of times we've tried to start the embedded Sass compiler.
    private(set) var startCount: Int

    /// The path of the compiler program
    private let embeddedCompilerFileURL: URL
    /// Its arguments
    private let embeddedCompilerFileArgs: [String]

    /// Fixed settings for the compiler
    let settings: Settings

    /// Most recently received version of compiler
    private var versions: Versions?

    /// Active compilation work indexed by RequestID
    var activeRequests: [UInt32 : any CompilerRequest]

    /// Task waiting for quiesce
    var quiesceContinuation: CheckedContinuation<Void, Never>?

    /// Use the bundled Dart Sass compiler as the Sass compiler.
    ///
    /// The bundled Dart Sass compiler is built on macOS (11.6) or Ubuntu (20.04) Intel 64-bit.
    /// If you are running on another operating system then use `init(eventLoopGroupProvider:embeddedCompilerFileURL:embeddedCompilerFileArguments:timeout:messageStyle:verboseDeprecations:suppressDependencyWarnings:importers:functions:)`
    /// supplying the path of the correct Dart Sass compiler.
    ///
    /// Initialization continues asynchronously after the initializer completes; failures are reported
    /// when the compiler is next used.
    ///
    /// You must shut down the compiler with `shutdownGracefully()` before letting it
    /// go out of scope.
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
                functions: SassFunctionMap = [:]) throws {
        let (url, args) = try DartSassEmbedded.getURLAndArgs()
        self.init(eventLoopGroupProvider: eventLoopGroupProvider,
                  embeddedCompilerFileURL: url,
                  embeddedCompilerFileArguments: args,
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
    /// You must shut down the compiler with `shutdownGracefully()` before letting it
    /// go out of scope.
    ///
    /// - parameter eventLoopGroupProvider: NIO `EventLoopGroup` to use: either `.shared` to use
    ///   an existing group or `.createNew` to create and manage a new event loop.  Default is `.createNew`.
    /// - parameter embeddedCompilerFileURL: Path of the `sass` program
    ///   or something else that speaks the Sass embedded protocol.  Check [the readme](https://github.com/johnfairh/swift-sass/blob/main/README.md)
    ///   for the supported protocol versions.
    /// - parameter embeddedCompilerFileArguments: Any arguments to be passed to the
    ///   `embeddedCompilerFileURL` program.  Default none.
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
                embeddedCompilerFileArguments: [String] = [],
                timeout: Int = 60,
                messageStyle: CompilerMessageStyle = .plain,
                verboseDeprecations: Bool = false,
                suppressDependencyWarnings: Bool = false,
                importers: [ImportResolver] = [],
                functions: SassFunctionMap = [:]) {
        precondition(embeddedCompilerFileURL.isFileURL, "Not a file URL: \(embeddedCompilerFileURL)")
        eventLoopGroup = ProvidedEventLoopGroup(eventLoopGroupProvider)
        eventLoop = self.eventLoopGroup.any()
        self.embeddedCompilerFileURL = embeddedCompilerFileURL
        self.embeddedCompilerFileArgs = embeddedCompilerFileArguments
        state = .initializing
        startCount = 0
        settings = Settings(timeout: timeout,
                            globalImporters: importers,
                            globalFunctions: functions,
                            messageStyle: messageStyle,
                            verboseDeprecations: verboseDeprecations,
                            suppressDependencyWarnings: suppressDependencyWarnings)
        stateWaitingQueue = ContinuationQueue()
        activeRequests = [:]
        quiesceContinuation = nil
        runTask = nil
        Task { // what the fuck is up with this...
            await self.initThunk()
        }
    }

    private func initThunk() async {
        await TestSuspend?.suspend(for: .initThunk)
        runTask = Task { await run() }
    }

    deinit {
        precondition(activeRequests.isEmpty)// !hasActiveRequests) WTF Swift async-await in deinit is weird
        precondition(state.isShutdown, "Compiler not shutdown: \(state)")
    }

    /// Run and maintain the Sass compiler.
    ///
    /// Cancelling this ``Task`` initiates a graceful exit of the compiler.
    private func run() async {
        precondition(state.isInitializing, "Unexpected state at run(): \(state)")

        let initThread = NIOThreadPool(numberOfThreads: 1)
        initThread.start()

        while !Task.isCancelled {
            do {
                setState(.initializing)

                precondition(!hasActiveRequests)
                startCount += 1

                // Get onto the thread to start the child process
                let child = try await initThread.runIfActive(eventLoop: eventLoop) {
                    try CompilerChild(fileURL: self.embeddedCompilerFileURL,
                                      arguments: self.embeddedCompilerFileArgs,
                                      workHandler: { [unowned self] in try await receive(message: $0, reply: $1) },
                                      errorHandler: { [unowned self] in await handleError($0) })
                }.get()

                try await child.setUpChannel(group: eventLoop)
                await TestSuspend?.suspend(for: .endOfInitializing)

                debug("Compiler is started, starting healthcheck")
                setState(.checking(child))

                // Kick off the child task to deal with compiler responses
                async let messageLoopTask: Void = runMessageLoop()

                let versions = try await sendVersionRequest(to: child)
                try versions.check()
                self.versions = versions

                // Might already be quiescing here, race with msgloop task
                if state.isChecking {
                    setState(.running(child))
                    await waitForStateChange()
                }

                await messageLoopTask
                precondition(state.isQuiescing, "Expected quiescing, is \(state)")

                debug("Quiescing work for \(Task.isCancelled ? "shutdown" : "restart")")
                await quiesce()
                debug("Quiesce complete, no outstanding compilations")
            } catch is CancellationError {
                // means we got cancelled waiting for the version query - go straight to shutdown.
            } catch {
                setState(.broken(error))
                debug("Can't start the compiler at all: \(error)")
                await stopAndCancelWork(with: error)
                while state.isBroken {
                    await waitForStateChange()
                }
            }
        }

        // Clean up 1-time resources
        try? await initThread.shutdownGracefully()
        try? await eventLoopGroup.shutdownGracefully()

        setState(.shutdown)
        debug("Compiler is shutdown")
    }

    /// Deal with inbound messages.
    ///
    /// This runs as a structured child task of `runTask` with cancellation propagation.
    private func runMessageLoop() async {
        let child = state.child!
        await child.processMessages()
        debug("Compiler message-loop ended, cancelled = \(Task.isCancelled)")
        setState(.quiescing(child))
        if Task.isCancelled {
            await stopAndCancelWork(with: CancellationError())
        }
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
    ///
    /// Throws an error if the compiler cannot be restarted due to error or because `shutdownGracefully()`
    /// has already been called.
    public func reinit() async throws {
        // Figure out if we need to prompt a reset
        if state.isRunning || state.isBroken {
            await handleError(LifecycleError("User requested Sass compiler be reinitialized"))
            while !state.isInitializing {
                await waitForStateChange()
            }
        }

        // Now wait for the reset to finish
        while true {
            switch state {
            case .initializing, .checking, .quiescing:
                await waitForStateChange()
            case .running:
                // reset complete
                return
            case .broken(let error):
                debug("Restart failed: \(error)")
                throw error
            case .shutdown:
                throw LifecycleError("Attempt to reinit() compiler that is already shut down")
            }
        }
    }

    /// Shut down the compiler.
    ///
    /// You must call this before the last reference to the `Compiler` is released.
    ///
    /// Cancels any outstanding work and shuts down internal threads. There’s no way back
    /// from this state: to do more compilation you will need a new instance.
    public func shutdownGracefully() async {
        while runTask == nil { // dumb window during init thunk
            await waitForStateChange()
        }
        debug("Shutdown request from \(state), active count=\(activeRequests.count)")
        runTask?.cancel()

        while !state.isShutdown {
            if state.isBroken {
                setState(.initializing)
            } else {
                await waitForStateChange()
            }
        }
    }

    /// Test hook
    func waitForRunning() async { await waitFor(\.isRunning) }
    func waitForBroken() async { await waitFor(\.isBroken) }
    func waitForQuiescing() async { await waitFor(\.isQuiescing) }

    func waitFor(_ statekp: KeyPath<State, Bool>) async {
        while !state[keyPath: statekp] {
            await waitForStateChange()
        }
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

    func debug(_ msg: @autoclosure () -> String) {
        Compiler.logger.debug(.init(stringLiteral: msg()))
    }

    // MARK: Compilation entrypoints

    typealias Continuation<T> = CheckedContinuation<T, any Error>

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
                        functions: SassFunctionMap = [:]) async throws -> CompilerResults {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let child = try await waitUntilReadyToCompile(continuation: continuation)
                let msg = startCompilation(input: .path(fileURL.path),
                                           outputStyle: outputStyle,
                                           sourceMapStyle: sourceMapStyle,
                                           includeCharset: includeCharset,
                                           importers: .init(importers),
                                           functions: functions,
                                           continuation: continuation)
                await child.send(message: msg)
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
                        functions: SassFunctionMap = [:]) async throws -> CompilerResults {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let child = try await waitUntilReadyToCompile(continuation: continuation)
                let msg = startCompilation(
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
                await child.send(message: msg)
            }
        }
    }

    private func waitUntilReadyToCompile(continuation: Continuation<CompilerResults>) async throws -> CompilerChild {
        while true {
            let err: (any Error)?
            switch state {
            case .broken(let error):
                // submitted while restarting the compiler; restart failed: fail
                err = LifecycleError("Sass compiler failed to start after unrecoverable error: \(error)")

            case .shutdown:
                // submitted after/during shutdown: fail
                err = LifecycleError("Sass compiler has been shut down, not accepting work")

            case .initializing, .quiescing, .checking:
                // submitted while [re]starting the compiler: wait
                err = nil
                await waitForStateChange()

            case .running(let child):
                // ready to go
                return child
            }
            if let err {
                continuation.resume(throwing: err)
                throw err
            }
        }
    }

    // MARK: Version query

    // Unit-test hook to inject/drop version request
    private var versionsResponder: VersionsResponder? = nil
    func setVersionsResponder(_ responder: VersionsResponder?) {
        self.versionsResponder = responder
    }

    private func sendVersionRequest(to child: CompilerChild) async throws -> Versions {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                await TestSuspend?.suspend(for: .sendVersionRequest)
                guard state.isChecking else {
                    debug("Cancelling versions query, state moved on to \(state)")
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let msg = startVersionRequest(continuation: continuation)
                if let versionsResponder {
                    if let rsp = await versionsResponder.provideVersions(msg: msg) {
                        await child.receive(message: rsp)
                    }
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
    /// In the async world this is collapsing into "SACW" which is good...
    func handleError(_ error: any Error) async {
        switch state {
        case .initializing:
            // Nothing to do, if something fails we'll notice
            break

        case .checking:
            // Timeout or something while checking the version, kick the process
            // and let the init process handle the error.
            debug("Error while checking compiler, stopping it")
            await stopAndCancelWork(with: error)

        case .running(let child):
            debug("Restarting compiler from running")
            setState(.quiescing(child))
            await stopAndCancelWork(with: error)

        case .broken:
            // Reinit attempt
            debug("Error (\(error)) while broken, reinit compiler")
            setState(.initializing)

        case .quiescing:
            // Corner/race stay in this state but try to hurry things along.
            debug("Error while quiescing, stopping compiler")
            await stopAndCancelWork(with: error)

        case .shutdown:
            // Nothing to do
            debug("Error (\(error)) while shutdown - doing nothing")
        }
    }

    private func stopAndCancelWork(with error: any Error) async {
        await state.child?.stop()
        cancelAllActive(with: error)
    }
}

/// NIO layer
///
/// Looks after the actual child process.
/// Knows how to set up the channel pipeline.
/// Routes inbound messages to CompilerWork.
actor CompilerChild: ChannelInboundHandler {
    typealias InboundIn = InboundMessage

    /// The child process
    private let child: Exec.Child
    /// Message handling (ex. the work manager)
    typealias WorkHandler = (InboundMessage, @escaping ReplyFn) async throws -> Void
    private let workHandler: WorkHandler
    /// Error handling
    typealias ErrorHandler = (any Error) async -> Void
    private let errorHandler: ErrorHandler
    /// Cancellation protocol
    private var stopping: Bool

    /// API
    nonisolated let processIdentifier: Int32

    /// Internal for test
    var channel: Channel {
        asyncChannel!.channel
    }

    private(set) var asyncChannel: NIOAsyncChannel<InboundMessage, OutboundMessage>!

    /// Create a new Sass compiler process.
    ///
    /// Must not be called in an event loop!  But I don't know how to check that.
    init(fileURL: URL, arguments: [String], workHandler: @escaping WorkHandler, errorHandler: @escaping ErrorHandler) throws {
        self.child = try Exec.spawn(fileURL, arguments)
        self.processIdentifier = child.process.processIdentifier
        self.workHandler = workHandler
        self.errorHandler = errorHandler
        self.stopping = false

        // The termination handler is always called when the process ends.
        // Only cascade this up into a compiler restart when we're not already
        // stopping, ie. we didn't just ask the process to end.
        self.child.process.terminationHandler = { _ in
            Task { await self.childTerminationHandler() }
        }
    }

    private func childTerminationHandler() async {
        await TestSuspend?.suspend(for: .childTermination)
        if !stopping {
            // unfortunate race condition here while this & Compile are on separate actors - new work received
            // before the compiler actually does this call will get smashed and failed rather than queued.
            await errorHandler(ProtocolError("Compiler process exitted unexpectedly"))
        }
    }

    /// Shutdown point - stop the child process to clean up the channel.
    /// Rely on `Compiler.stopAndCancelWork()` sequencing with the active work queue.
    func stop() {
        if !stopping {
            stopping = true
            child.process.terminationHandler = nil
            child.terminate()
            // Linux weirdness - `terminate` doesn't cause the AsyncChannel to finish even though
            // it definitely stops the process - so we have to poke it:
            //
            // 1) asyncChannel?.outboundWriter.finish() --- worked once then never again, maybe I imagined it
            // 2) kill(processIdentifier, -9) --- no effect
            // 3) horrendous multi-layered Task version of msgLoopTask enabling Swift concurrency
            //    cancel -- which NIO is far more interested in than the pipe going broken -- seems
            //    to work.  Fuck me.
            msgLoopTask?.cancel()
        }
    }

    /// Connect the unix child process to NIO
    func setUpChannel(group: EventLoopGroup) async throws {
        asyncChannel = try await NIOPipeBootstrap(group: group)
            .takingOwnershipOfDescriptors(input: child.stdoutFD, output: child.stdinFD) { ch in
                ProtocolWriter.addHandler(to: ch)
                    .flatMap {
                        ProtocolReader.addHandler(to: ch)
                    }
                    .flatMapThrowing {
                        try NIOAsyncChannel(synchronouslyWrapping: ch)
                    }
            }
    }

    /// Send a message to the Sass compiler with error detection.
    func send(message: OutboundMessage) async {
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
            // sigchld handler to clean up.  The test suite forces us down here by calling the
            // mysterious 'finish' method on the async writer.
            await errorHandler(ProtocolError("Write to Sass compiler failed: \(error)"))
        }
    }

    private var msgLoopTask: Task<Void, Never>?

    /// Process messages from the child until it dies or the task is cancelled
    ///
    /// See `stop()` for why this nonsense is so nonsensical.
    func processMessages() async {
        await withTaskCancellationHandler {
            msgLoopTask = Task {
                await processMessages2()
            }
            await msgLoopTask?.value
        } onCancel: {
            Task { await msgLoopTask?.cancel() }
        }
    }

    private func processMessages2() async {
        precondition(asyncChannel != nil)
        do {
            for try await message in asyncChannel.inboundStream {
                // only 'async' because of hop to Compiler actor - is non-blocking synchronous on client side
                await receive(message: message)
            }
        } catch is CancellationError {
        } catch {
            // Called from NIO up the stack if our binary protocol reader has a problem
            await errorHandler(ProtocolError("Read from Sass compiler failed: \(error)"))
        }
    }

    /// Split out for test access
    func receive(message: InboundMessage) async {
        guard !stopping else {
            // I don't really understand how this happens but have test proof on Linux
            // on Github Actions env, seems to be an inbound buffer where something can
            // get caught and appear even after the child process is terminated.
            Compiler.logger.debug("Rx: \(message.logMessage) while stopping, discarding")
            return
        }
        Compiler.logger.debug("Rx: \(message.logMessage)")

        do {
            try await workHandler(message) {
                await self.send(message: $0)
            }
        } catch {
            await errorHandler(error)
        }
    }
}

/// Version response injection for testing
protocol VersionsResponder {
    func provideVersions(msg: OutboundMessage) async -> InboundMessage?
}

/// Dumb enum helpers
extension Compiler.State {
    var isBroken: Bool {
        if case .broken = self {
            return true
        }
        return false
    }

    var isChecking: Bool {
        if case .checking = self {
            return true
        }
        return false
    }

    var isInitializing: Bool {
        if case .initializing = self {
            return true
        }
        return false
    }

    var isQuiescing: Bool {
        if case .quiescing = self {
            return true
        }
        return false
    }

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    var isShutdown: Bool {
        if case .shutdown = self {
            return true
        }
        return false
    }
}
