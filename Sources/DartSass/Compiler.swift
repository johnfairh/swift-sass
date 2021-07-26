//
//  Compiler.swift
//  DartSass
//
//  Copyright 2020-2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import struct Foundation.URL
import class Foundation.FileManager // cwd
import Dispatch
import NIO
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
public final class Compiler {
    private let eventLoopGroup: ProvidedEventLoopGroup

    /// NIO event loop we're bound to.  Internal for test.
    let eventLoop: EventLoop

    /// Child process initialization involves blocking steps and happens outside of NIO.
    private let initThread: NIOThreadPool

    enum State {
        /// No child, new jobs wait on promise with new state.
        case initializing(EventLoopFuture<Void>)
        /// Child up, checking it's working before accepting compilations.
        case checking(CompilerChild, EventLoopFuture<Void>)
        /// Child is running and accepting compilation jobs.
        case running(CompilerChild)
        /// Child is broken.  Fail new jobs with the error.  Reinit permitted.
        case broken(Error)
        /// System is shutting down, ongoing jobs will complete but no new.
        /// Shutdown will be done when promise completes.
        case quiescing(CompilerChild, EventLoopFuture<Void>)
        /// Compiler is shut down.  Fail new jobs.
        case shutdown

        var child: CompilerChild? {
            switch self {
            case .checking(let c, _), .running(let c), .quiescing(let c, _): return c
            case .initializing(_), .broken(_), .shutdown: return nil
            }
        }

        var future: EventLoopFuture<Void>? {
            switch self {
            case .initializing(let f), .checking(_, let f), .quiescing(_, let f): return f
            case .running, .broken, .shutdown: return nil
            }
        }

        @discardableResult
        mutating func toInitializing(_ future: EventLoopFuture<Void>) -> EventLoopFuture<Void> {
            self = .initializing(future)
            return future
        }

        mutating func inittingToChecking(_ child: CompilerChild) {
            self = .checking(child, future!)
        }

        mutating func checkingToRunning() {
            self = .running(child!)
        }

        mutating func toQuiescing(_ future: EventLoopFuture<Void>) -> EventLoopFuture<Void> {
            self = .quiescing(child!, future)
            return future
        }
    }

    /// Compiler process state.  Internal for test access.
    private(set) var state: State

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
    /// The bundled Dart Sass compiler is built for macOS (Intel) or Ubuntu Xenial (16.04) 64-bit.
    /// If you are running on another operating system then use `init(eventLoopGroupProvider:embeddedCompilerFileURL:timeout:messageStyle:verboseDeprecations:suppressDependencyWarnings:importers:functions:)`
    /// supplying the path of the correct Dart Sass compiler.
    ///
    /// Initialization continues asynchronously after the initializer completes; failures are reported
    /// when the compiler is next used.
    ///
    /// You must shut down the compiler with `shutdownGracefully(queue:_:)` or
    /// `syncShutdownGracefully()` before letting it go out of scope.
    ///
    /// - parameter eventLoopGroup: NIO `EventLoopGroup` to use: either `.shared` to use
    ///   an existing group or `.createNew` to create and manage a new event loop.
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
    public convenience init(eventLoopGroupProvider: NIOEventLoopGroupProvider,
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
    /// You must shut down the compiler with `shutdownGracefully(queue:_:)` or
    /// `syncShutdownGracefully()` before letting it go out of scope.
    ///
    /// - parameter eventLoopGroup: NIO `EventLoopGroup` to use: either `.shared` to use
    ///   an existing group or `.createNew` to create and manage a new event loop.
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
    public init(eventLoopGroupProvider: NIOEventLoopGroupProvider,
                embeddedCompilerFileURL: URL,
                timeout: Int = 60,
                messageStyle: CompilerMessageStyle = .plain,
                verboseDeprecations: Bool = false,
                suppressDependencyWarnings: Bool = false,
                importers: [ImportResolver] = [],
                functions: SassAsyncFunctionMap = [:]) {
        precondition(embeddedCompilerFileURL.isFileURL, "Not a file URL: \(embeddedCompilerFileURL)")
        self.eventLoopGroup = ProvidedEventLoopGroup(eventLoopGroupProvider)
        eventLoop = self.eventLoopGroup.next()
        initThread = NIOThreadPool(numberOfThreads: 1)
        initThread.start()
        work = nil
        self.embeddedCompilerFileURL = embeddedCompilerFileURL
        state = .shutdown
        startCount = 0
        // self init done
        work = CompilerWork(eventLoop: eventLoop,
                            resetRequest: { [unowned self] in handle(error: $0) },
                            timeout: timeout,
                            settings: .init(messageStyle: messageStyle,
                                            verboseDeprecations: verboseDeprecations,
                                            suppressDependencyWarnings: suppressDependencyWarnings),
                            importers: importers,
                            functions: functions)
        state.toInitializing(startCompiler())
    }

    deinit {
        guard case .shutdown = state else {
            preconditionFailure("Compiler not shutdown: \(state)")
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
    public func reinit() -> EventLoopFuture<Void> {
        eventLoop.flatSubmit {
            self.handle(error: LifecycleError("User requested Sass compiler be reinitialized"))
        }
    }

    /// Shut down the compiler asynchronously.
    ///
    /// You must call this (or `syncShutdownGracefully()` before the last reference to the
    /// `Compiler` is released.
    ///
    /// Waits for work to wind down naturally and shuts down internal threads.  There's no way back
    /// from this state: to do more compilation you will need a new object.
    ///
    /// This resolves on a dispatch queue because of internal event queue shutdown; make sure the
    /// queue is being run.
    public func shutdownGracefully(queue: DispatchQueue = .global(), _ callback: @escaping (Error?) -> Void) {
        eventLoop.flatSubmit {
            self.shutdown()
        }.whenCompleteBlocking(onto: queue) { result in
            self.eventLoopGroup.shutdownGracefully(queue: queue) { elgError in
                callback(result.error ?? elgError)
            }
        }
    }

    /// Shut down the compiler synchronously.
    ///
    /// See `shutdownGracefully(queue:_:)`.
    ///
    /// Do not call this from an event loop thread.
    public func syncShutdownGracefully() throws {
        try eventLoop.flatSubmit {
            self.shutdown()
        }.wait()

        try eventLoopGroup.syncShutdownGracefully()
    }

    /// The process ID of the embedded Sass compiler.
    ///
    /// Not normally needed; could be used to adjust resource usage or maybe send it a signal if stuck.
    /// The process ID is reported after waiting for any [re]initialization to complete; a value of `nil`
    /// means that the compiler is broken or shutdown.
    public var compilerProcessIdentifier: EventLoopFuture<Int32?> {
        eventLoop.flatSubmit { [self] in
            switch state {
            case .broken, .shutdown:
                return eventLoop.makeSucceededFuture(nil)
            case .checking(let child, _), .running(let child), .quiescing(let child, _):
                return eventLoop.makeSucceededFuture(child.processIdentifier)
            case .initializing(let future):
                return future.flatMap {
                    self.compilerProcessIdentifier
                }
            }
        }
    }

    /// The name of the underlying Sass implementation.  `nil` if unknown.
    public var compilerName: EventLoopFuture<String?> {
        versionsFuture.map { $0?.compilerName }
    }

    /// The version of the underlying Sass implementation.  For Dart Sass and LibSass this is in
    /// [semver](https://semver.org/spec/v2.0.0.html) format. `nil` if unknown (never got a version).
    public var compilerVersion: EventLoopFuture<String?> {
        versionsFuture.map { $0?.compilerVersionString }
    }

    /// The version of the package implementing the compiler side of the embedded Sass protocol.
    /// Probably in [semver](https://semver.org/spec/v2.0.0.html) format.
    /// `nil` if unknown (never got a version).
    public var compilerPackageVersion: EventLoopFuture<String?> {
        versionsFuture.map { $0?.packageVersionString }
    }

    private var versionsFuture: EventLoopFuture<Versions?> {
        eventLoop.flatSubmit { [self] in
            switch state {
            case .broken, .shutdown, .running, .quiescing:
                return eventLoop.makeSucceededFuture(versions)
            case .checking(_, let future), .initializing(let future):
                let promise = eventLoop.makePromise(of: Optional<Versions>.self)
                future.whenComplete { _ in
                    promise.succeed(self.versions)
                }
                return promise.futureResult
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

    /// Asynchronous version of `compile(fileURL:outputStyle:sourceMapStyle:importers:functions:)`.
    public func compileAsync(fileURL: URL,
                             outputStyle: CssStyle = .expanded,
                             sourceMapStyle: SourceMapStyle = .separateSources,
                             importers: [ImportResolver] = [],
                             functions: SassAsyncFunctionMap = [:]) -> EventLoopFuture<CompilerResults> {
        eventLoop.flatSubmit { [self] in
            defer { kickPendingCompilations() }
            return work.addPendingCompilation(
                input: .path(fileURL.path),
                outputStyle: outputStyle,
                sourceMapStyle: sourceMapStyle,
                importers: .init(importers),
                functions: functions)
        }
    }

    /// Compile to CSS from a stylesheet file.
    ///
    /// - parameters:
    ///   - fileURL: The URL of the file to compile.  The file extension determines the
    ///     expected syntax of the contents, so it must be css/scss/sass.
    ///   - outputStyle: How to format the produced CSS.  Default `.expanded`.
    ///   - sourceMapStyle: Kind of source map to create for the CSS.  Default `.separateSources`.
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
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        try compileAsync(fileURL: fileURL,
                         outputStyle: outputStyle,
                         sourceMapStyle: sourceMapStyle,
                         importers: importers,
                         functions: .init(functions)).wait()
    }

    /// Asynchronous version of `compile(string:syntax:url:importer:outputStyle:sourceMapStyle:importers:functions:)`.
    public func compileAsync(string: String,
                             syntax: Syntax = .scss,
                             url: URL? = nil,
                             importer: ImportResolver? = nil,
                             outputStyle: CssStyle = .expanded,
                             sourceMapStyle: SourceMapStyle = .separateSources,
                             importers: [ImportResolver] = [],
                             functions: SassAsyncFunctionMap = [:]) -> EventLoopFuture<CompilerResults> {
        eventLoop.flatSubmit { [self] in
            defer { kickPendingCompilations() }
            return work.addPendingCompilation(
                input: .string(.with { m in
                    m.source = string
                    m.syntax = .init(syntax)
                    url.flatMap { m.url = $0.absoluteString }
                    m.importer = .init(findImplicitImporter(importer: importer),
                                       id: CompilationRequest.baseImporterID)
                }),
                outputStyle: outputStyle,
                sourceMapStyle: sourceMapStyle,
                importers: importers,
                stringImporter: importer,
                functions: functions)
        }
    }

    // Compile from string, no importer given, supposed to try the current directory.
    // but the child process's CWD could be different to ours - so we can't let it resolve.
    private func findImplicitImporter(importer: ImportResolver?) -> ImportResolver {
        importer ?? .loadPath(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    /// Compile to CSS from an inline stylesheet.
    ///
    /// - parameters:
    ///   - string: The stylesheet text to compile.
    ///   - syntax: The syntax of `string`, default `.scss`.
    ///   - url: The absolute URL to associate with `string`, from where it was loaded.
    ///     Default `nil` meaning unknown.
    ///   - importer: Rule to resolve `@import` etc. from `string` relative to `url`.  Default `nil`
    ///     meaning the current filesystem directory is used.
    ///   - outputStyle: How to format the produced CSS.  Default `.expanded`.
    ///   - sourceMapStyle: Kind of source map to create for the CSS.  Default `.separateSources`.
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
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        try compileAsync(string: string,
                         syntax: syntax,
                         url: url,
                         importer: importer,
                         outputStyle: outputStyle,
                         sourceMapStyle: sourceMapStyle,
                         importers: importers,
                         functions: .init(functions)).wait()
    }

    /// Consider the pending work queue.  When we change `state` or add to `pendingCompilations`.`
    private func kickPendingCompilations() {
        eventLoop.preconditionInEventLoop()

        switch state {
        case .broken(let error):
            // jobs submitted while restarting the compiler; restart failed: fail them.
            work.cancelAllPending(with: LifecycleError("Sass compiler failed to restart after previous error: \(error)"))

        case .shutdown, .quiescing:
            // jobs submitted after/during shutdown: fail them.
            work.cancelAllPending(with: LifecycleError("Compiler has been shutdown, not accepting further work"))

        case .initializing, .checking:
            // jobs submitted while [re]starting the compiler: wait.
            break

        case .running(let child):
            // goodpath
            child.send(messages: work.startAllPending())
        }
    }

    /// Startup ceremony
    ///
    /// Get onto the thread to start the child and bootstrap the NIO connections.
    /// Then back to the event loop to add handlers and kick the state machine.
    ///
    /// When this future completes the system is either in running or broken.
    private func startCompiler() -> EventLoopFuture<Void> {
        precondition(!work.hasActiveRequests)
        startCount += 1
        return initThread.runIfActive(eventLoop: eventLoop) { [self] in
            try CompilerChild(eventLoop: eventLoop,
                              fileURL: embeddedCompilerFileURL,
                              work: work,
                              errorHandler: { [unowned self] in self.handle(error: $0) })
        }.flatMap { child in
            child.addChannelHandlers()
        }.flatMap { child -> EventLoopFuture<Versions> in
            self.debug("Compiler is started, starting healthcheck")
            self.state.inittingToChecking(child)
            return self.sendVersionRequest(to: child)
        }.flatMapThrowing { versions in
            try versions.check()
            self.versions = versions
            self.state.checkingToRunning()
            self.kickPendingCompilations()
        }.flatMapErrorThrowing { error in
            self.debug("Can't start the compiler at all: \(error)")
            self.state.child?.stopAndCancelWork(with: error)
            self.state = .broken(error)
            self.kickPendingCompilations()
            throw error
        }
    }

    // Unit-test hook to inject/drop version request
    var versionsResponder: VersionsResponder? = nil

    private func sendVersionRequest(to child: CompilerChild) -> EventLoopFuture<Versions> {
        let (future, reqMsg) = work.startVersionRequest()

        if let responder = versionsResponder {
            responder.provideVersions(eventLoop: eventLoop, msg: reqMsg) {
                child.receive(message: $0)
            }
        } else {
            child.send(message: reqMsg)
        }
        return future
    }

    /// Central transport/protocol error detection and 'recovery'.
    ///
    /// Errors come from:
    /// 1. Write transport errors, reported by a promise from `CompilerChild.send(message:to:)`
    /// 2. Read transport errors, reported by the channel handler from `CompilerChild.errorCaught(...)`
    /// 3. Protocol errors reported by the Sass compiler, from `CompilerWork.receieveGlobal(message:)`
    /// 4. Protocol errors detected by us, from `CompilationRequest.receive(message)`.
    /// 5. User-injected restarts, from `reinit()`.
    /// 6. Timeouts, from `CompilerWork`'s reset API.
    ///
    /// In all cases we brutally restart the compiler and fail back all the jobs.  Need experience of how this
    /// actually fails before doing anything more.
    @discardableResult
    func handle(error: Error) -> EventLoopFuture<Void> {
        eventLoop.preconditionInEventLoop()

        switch state {
        case .initializing(let future):
            return future

        case .checking(let child, let future):
            // Timeout or something while checking the version, kick the process
            // and let the init process handle the error.
            debug("Error while checking compiler, stopping it")
            child.stopAndCancelWork(with: error)
            return future

        case .running(let child):
            debug("Restarting compiler from running")
            child.stopAndCancelWork(with: error)
            return state.toInitializing(
                work.quiesce().flatMap {
                    self.debug("No outstanding compilations, restarting compiler")
                    return self.startCompiler()
                })

        case .broken:
            debug("Restarting compiler from broken")
            return state.toInitializing(startCompiler())

        case .quiescing(let child, let future):
            // Nasty corner - stay in this state but try to
            // hurry things along.
            debug("Error while quiescing, stopping compiler")
            child.stopAndCancelWork(with: error)
            return future

        case .shutdown:
            return eventLoop.makeLifecycleError("Compiler has been shutdown, ignoring: \(error)")
        }
    }

    /// Graceful shutdown.
    ///
    /// Let all work finish normally, then kill the child process and go to the terminal state.
    private func shutdown() -> EventLoopFuture<Void> {
        eventLoop.preconditionInEventLoop()

        switch state {
        case .initializing(let initFuture), .checking(_, let initFuture):
            debug("Shutdown during startup, deferring")
            // Nasty corner - wait for the init to resolve and then
            // try again!
            return initFuture.flatMap { _ in
                self.debug("Reissuing deferred shutdown")
                return self.shutdown()
            }

        case .running(let child):
            debug("Shutdown from running")
            return state.toQuiescing(
                work.quiesce().flatMap { () -> EventLoopFuture<Void> in
                    self.debug("No outstanding compilations, shutting down compiler")
                    child.stopAndCancelWork()
                    return self.initThread.shutdownGracefully(eventLoop: self.eventLoop)
                }.map {
                    self.debug("Compiler is shutdown")
                    self.state = .shutdown
                })

        case .broken, .shutdown:
            state = .shutdown
            return eventLoop.makeSucceededFuture(())

        case .quiescing(_, let future):
            return future
        }
    }
}

/// NIO layer
///
/// Looks after the actual child process.
/// Knows how to set up the channel pipeline.
/// Routes inbound messages to CompilerWork.
final class CompilerChild: ChannelInboundHandler {
    typealias InboundIn = Sass_EmbeddedProtocol_OutboundMessage

    /// Our event loop
    private let eventLoop: EventLoop
    /// The child process
    private let child: Exec.Child
    /// The work manager
    private let work: CompilerWork
    /// Error handling
    private let errorHandler: (Error) -> Void
    /// Cancellation protocol
    private var stopping: Bool

    /// API
    var processIdentifier: Int32 {
        child.process.processIdentifier
    }

    /// Test
    var channel: Channel {
        child.channel
    }

    /// Create a new Sass compiler process.
    ///
    /// Must not be called in an event loop!  But I don't know how to check that.
    init(eventLoop: EventLoop, fileURL: URL, work: CompilerWork, errorHandler: @escaping (Error) -> Void) throws {
        self.child = try Exec.spawn(fileURL, group: eventLoop)
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
            eventLoop.execute {
                if !self.stopping {
                    errorHandler(ProtocolError("Compiler process exitted unexpectedly"))
                }
            }
        }
    }

    /// Connect Sass protocol handlers.
    func addChannelHandlers() -> EventLoopFuture<CompilerChild> {
        ProtocolWriter.addHandler(to: child.channel)
            .flatMap {
                ProtocolReader.addHandler(to: self.child.channel)
            }.flatMap {
                self.child.channel.pipeline.addHandler(self)
            }.map {
                self
            }
    }

    /// Send a message to the Sass compiler with error detection.
    @discardableResult
    func send(message: Sass_EmbeddedProtocol_InboundMessage) -> EventLoopFuture<Void> {
        eventLoop.preconditionInEventLoop()
        guard !stopping else {
            // Race condition of compiler reset vs. async host function
            return eventLoop.makeSucceededFuture(())
        }

        return child.channel.writeAndFlush(message).flatMapError { error in
            // tough to reliably hit this error.  if we kill the process while trying to write to
            // it we get this on Darwin maybe 20% of the time vs. the write working, leaving the
            // sigchld handler to clean up.
            self.errorHandler(ProtocolError("Write to Sass compiler failed: \(error)"))
            return self.eventLoop.makeFailedFuture(error)
        }
    }

    func send(messages: [Sass_EmbeddedProtocol_InboundMessage]) {
        messages.forEach { send(message: $0) }
    }

    /// Called from the pipeline handler with a new message
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        eventLoop.preconditionInEventLoop()
        receive(message: unwrapInboundIn(data))
    }

    /// Split out for test access
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) {
        Compiler.logger.debug("Rx: \(message.logMessage)")

        work.receive(message: message).map {
            if let response = $0 {
                self.send(message: response)
            }
        }.whenFailure {
            self.errorHandler($0)
        }
    }

    /// Called from NIO up the stack if something goes wrong with the inbound connection
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        errorHandler(ProtocolError("Read from Sass compiler failed: \(error)"))
    }

    /// Shutdown point - stop the child process to clean up the channel.
    /// Cascade to `CompilerWork` so it stops waiting for responses -- this is a little bit spaghetti but it's helpful
    /// to keep them tightly bound.
    func stopAndCancelWork(with error: Error? = nil) {
        stopping = true
        child.process.terminationHandler = nil
        child.terminate()
        if let error = error {
            work.cancelAllActive(with: error)
        }
    }
}

/// Version response injection for testing
protocol VersionsResponder {
    func provideVersions(eventLoop: EventLoop,
                         msg: Sass_EmbeddedProtocol_InboundMessage,
                         callback: @escaping (Sass_EmbeddedProtocol_OutboundMessage) -> Void)
}
