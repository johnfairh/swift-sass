//
//  Compiler.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import Foundation
import NIO
import Logging
@_exported import Sass

/// An instance of the embedded Sass compiler hosted in Swift.
///
/// It runs the compiler as a child process and lets you provide stylesheet importers and Sass functions
/// that are part of your Swift code.
///
/// Most simple usage looks like:
/// ```swift
/// do {
///    let compiler = try Compiler()
///    let results = try compiler.compile(sourceFileURL: sassFileURL)
///    print(results.css)
/// } catch {
/// }
/// ```
///
/// Separately to this package you need to supply the `dart-sass-embedded` program or some
/// other thing supporting the Embedded Sass protocol that this class runs under the hood.
///
/// Use `Compiler.warningHandler` to get sight of warnings from the compiler.
///
/// To debug problems, start with the output from `Compiler.debugHandler`, all the source files
/// being given to the compiler, and the description of any errors thrown.
public final class Compiler: CompilerProtocol {
    /// NIO event loop we're bound to.
    private let eventLoop: EventLoop

    /// Child process initialization involves blocking steps and happens outside of NIO.
    private let initThread: NIOThreadPool

    enum State {
        /// No child, new jobs wait.
        case initializing(EventLoopFuture<Void>)
        /// Child is running and accepting compilation jobs.
        case running(Exec.Child)
        /// Child is broken.  Fail new jobs with the error.
        case broken(Error)
        /// System is shutting down.
        case quiescing(Exec.Child, EventLoopFuture<Void>)
        /// Compiler is shut down.  Fail new jobs.
        case shutdown
    }

    /// Compiler process state.  Internal for test access.
    private(set) var state: State

    /// The URL of the compiler program
    private let embeddedCompilerURL: URL

    /// Configured max timeout
    private let overallTimeout: Int
    /// Configured global importer rules, for all compilations
    private let globalImporters: [ImportResolver]
    /// Configured functions, for all compilations
    private let globalFunctions: SassFunctionMap

    /// Unstarted compilation work
    private var pendingCompilations: [Compilation]
    /// Active compilation work
    private var activeCompilations: [UInt32: Compilation]

    /// Initialize using the given program as the embedded Sass compiler.
    ///
    /// - parameter eventLoopGroup: The NIO `EventLoopGroup` to use.
    /// - parameter embeddedCompilerURL: The file URL to `dart-sass-embedded`
    ///   or something else that speaks the embedded Sass protocol.
    /// - parameter overallTimeoutSeconds: The maximum time allowed  for the embedded
    ///   compiler to compile a stylesheet.  Detects hung compilers.  Default is a minute; set
    ///   -1 to disable timeouts.
    /// - parameter importers: Rules for resolving `@import` that cannot be satisfied relative to
    ///   the source file's URL, used for all compile requests made of this instance.
    /// - parameter functions: Sass functions available to all compile requests made of this instance.
    ///
    /// - throws: Something from Foundation if the program does not start.
    public init(eventLoopGroup: EventLoopGroup,
                embeddedCompilerURL: URL,
                overallTimeoutSeconds: Int = 60,
                importers: [ImportResolver] = [],
                functions: SassFunctionMap = [:]) throws {
        precondition(embeddedCompilerURL.isFileURL, "Not a file: \(embeddedCompilerURL)")
        eventLoop = eventLoopGroup.next()
        initThread = NIOThreadPool(numberOfThreads: 1)
        initThread.start()
        overallTimeout = overallTimeoutSeconds
        globalImporters = importers
        globalFunctions = functions
        self.embeddedCompilerURL = embeddedCompilerURL
        pendingCompilations = []
        activeCompilations = [:]
        state = .shutdown
        let initFuture = startCompiler()
        state = .initializing(initFuture)

        try initFuture.wait()
    }

    /// Initialize using a program found on `PATH` as the embedded Sass compiler.
    ///
    /// - parameter eventLoopGroup: The NIO `EventLoopGroup` to use.
    /// - parameter embeddedCompilerName: Name of the program, default `dart-sass-embedded`.
    /// - parameter timeoutSeconds: The maximum time allowed  for the embedded
    ///   compiler to compile a stylesheet.  Detects hung compilers.  Default is a minute; set
    ///   -1 to disable timeouts.
    /// - parameter importers: Rules for resolving `@import` that cannot be satisfied relative to
    ///   the source file's URL, used for all compile requests to this instance.
    /// - parameter functions: Sass functions available to all compile requests made of this instance.    ///
    /// - throws: `ProtocolError()` if the program can't be found.
    ///           Everything from `init(embeddedCompilerURL:)`
    public convenience init(eventLoopGroup: EventLoopGroup,
                            embeddedCompilerName: String = "dart-sass-embedded",
                            overallTimeoutSeconds: Int = 60,
                            importers: [ImportResolver] = [],
                            functions: SassFunctionMap = [:]) throws {
        let results = Exec.run("/usr/bin/env", "which", embeddedCompilerName, stderr: .discard)
        guard let path = results.successString else {
            throw ProtocolError("Can't find `\(embeddedCompilerName)` on PATH.\n\(results.failureReport)")
        }
        try self.init(eventLoopGroup: eventLoopGroup,
                      embeddedCompilerURL: URL(fileURLWithPath: path),
                      overallTimeoutSeconds: overallTimeoutSeconds,
                      importers: importers,
                      functions: functions)
    }

    deinit {
        try? initThread.syncShutdownGracefully()
        precondition(activeCompilations.isEmpty)
        precondition(pendingCompilations.isEmpty) // TODO should be able to hit this
        if case let .running(child) = state {
            child.terminate()
        }
    }

    /// Startup ceremony
    ///
    /// Get onto the thread to start the child and bootstrap the NIO connections.
    /// Then back to the event loop to add handlers and kick the state machine.
    ///
    /// When this future completes the system is either in running or broken.
    private func startCompiler() -> EventLoopFuture<Void> {
        precondition(activeCompilations.isEmpty)
        var nextChild: Exec.Child!
        return initThread.runIfActive(eventLoop: eventLoop) {
            nextChild = try Exec.spawn(self.embeddedCompilerURL, group: self.eventLoop)
        }.flatMap {
            ProtocolWriter.addHandler(to: nextChild.standardInput)
        }.flatMap {
            ProtocolReader.addHandler(to: nextChild.standardOutput)
        }.flatMap {
            nextChild.standardOutput.pipeline.addHandler(InboundMsgHandler(compiler: self))
        }.map {
            self.debug("Compiler is started")
            self.state = .running(nextChild)
            self.kickCompilations()
        }.flatMapErrorThrowing { error in
            self.debug("Can't start the compiler at all: \(error)")
            self.state = .broken(error)
            self.kickCompilations()
            throw error
        }
    }

    /// Restart the Sass compiler process.
    ///
    /// Normally a single instance of the compiler process persists across all invocations to
    /// `compile(...)` on this `Compiler` instance.   This method stops the current
    /// compiler process and starts a new one: the intended use is for compilers whose
    /// resource usage escalates over time and need calming down.  You probably don't need to
    /// call it.
    ///
    /// Any outstanding compile jobs are failed.
    public func reinit() -> EventLoopFuture<Void> {
        eventLoop.flatSubmit {
            self.handle(error: ProtocolError("User requested Compiler reinit."))
        }
    }

    /// Shut down the system.
    ///
    /// Wait for work to wind down and shuts down internal threads.  There's no way back from this
    /// state, to do more compilation you need a new object.
    ///
    /// If you don't call this and wait for the result before shutting down the event loop then
    /// there is a chance NIO will crash.
    public func shutdownGracefully() -> EventLoopFuture<Void> {
        eventLoop.flatSubmit {
            self.shutdown()
        }
    }

    /// The process ID of the compiler process.
    ///
    /// Not normally needed; can be used to adjust resource usage or maybe send it a signal if stuck.
    /// The process ID is reported as `nil` if there currently is no running child process.
    public var compilerProcessIdentifier: EventLoopFuture<Int32?> {
        eventLoop.submit {
            guard case let .running(child) = self.state else {
                return nil
            }
            return child.process.processIdentifier
        }
    }

    /// Logger for the module.
    ///
    /// Produces goodpath protocol tracing at `.debug` log level, approx 500 bytes per compile request.
    ///
    /// Produces protocol error tracing at `.error` log level.  This is the same as the `description` of
    /// thrown `ProtocolError`s.
    public static var logger = Logger(label: "swift-sass")

    private func debug(_ msg: @autoclosure () -> String) {
        Compiler.logger.debug(.init(stringLiteral: msg()))
    }

    /// Asynchronous version of `compile(fileURL:outputStyle:createSourceMap:importers:functions:)`.
    public func compileAsync(fileURL: URL,
                             outputStyle: CssStyle = .expanded,
                             createSourceMap: Bool = false,
                             importers: [ImportResolver] = [],
                             functions: SassFunctionMap = [:]) -> EventLoopFuture<CompilerResults> {
        compile(input: .path(fileURL.path),
                outputStyle: outputStyle,
                createSourceMap: createSourceMap,
                importers: importers,
                functions: functions)
    }

    public func compile(fileURL: URL,
                        outputStyle: CssStyle = .expanded,
                        createSourceMap: Bool = false,
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        try compileAsync(fileURL: fileURL,
                         outputStyle: outputStyle,
                         createSourceMap: createSourceMap,
                         importers: importers,
                         functions: functions).wait()
    }

    /// Asynchronous version of `compile(text:syntax:url:outputStyle:createSourceMap:importers:functions:)`.
    public func compileAsync(text: String,
                             syntax: Syntax = .scss,
                             url: URL? = nil,
                             outputStyle: CssStyle = .expanded,
                             createSourceMap: Bool = false,
                             importers: [ImportResolver] = [],
                             functions: SassFunctionMap = [:]) -> EventLoopFuture<CompilerResults> {
        compile(input: .string(.with { m in
                   m.source = text
                   m.syntax = .init(syntax)
                   url.flatMap { m.url = $0.absoluteString }
                }),
                outputStyle: outputStyle,
                createSourceMap: createSourceMap,
                importers: importers,
                functions: functions)
    }

    public func compile(text: String,
                        syntax: Syntax = .scss,
                        url: URL? = nil,
                        outputStyle: CssStyle = .expanded,
                        createSourceMap: Bool = false,
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        try compileAsync(text: text,
                         syntax: syntax,
                         url: url,
                         outputStyle: outputStyle,
                         createSourceMap: createSourceMap,
                         importers: importers,
                         functions: functions).wait()
    }

    /// Helper to generate the compile request message
    private func compile(input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
                         outputStyle: CssStyle,
                         createSourceMap: Bool,
                         importers: [ImportResolver],
                         functions: SassFunctionMap) -> EventLoopFuture<CompilerResults> {
        // Figure out functions - semantic name does not include params so merge global
        // and per-job based on name alone, then pass the whole lot to the job.
        let localFnsNameMap = functions._asSassFunctionNameElementMap
        let globalFnsNameMap = globalFunctions._asSassFunctionNameElementMap
        let mergedFnsNameMap = globalFnsNameMap.merging(localFnsNameMap) { g, l in l }

        let promise = eventLoop.makePromise(of: CompilerResults.self)

        eventLoop.execute { [self] in
            let compilation = Compilation(
                promise: promise,
                input: input,
                outputStyle: outputStyle,
                createSourceMap: createSourceMap,
                importers: globalImporters + importers,
                functionsMap: mergedFnsNameMap,
                timeoutSeconds: overallTimeout,
                resetRequest: { handle(error: $0) })

            pendingCompilations.append(compilation)
            kickCompilations()
        }

        return promise.futureResult
    }

    /// Consider the pending work queue.  When we change `state` or add to `pendingCompilations`.`
    private func kickCompilations() {
        eventLoop.preconditionInEventLoop()

        func cancelAllPending(with error: Error) {
            pendingCompilations.forEach {
                $0.cancel(with: error)
            }
            pendingCompilations = []
        }

        switch state {
        case .broken(let error):
            // jobs submitted while restarting the compiler, restart failed: fail them.
            cancelAllPending(with: ProtocolError("Sass compiler failed to restart after previous error: \(error)."))

        case .shutdown, .quiescing(_, _):
            cancelAllPending(with: ProtocolError("Compiler instance has been shutdown, not accepting further jobs."))

        case .initializing:
            // jobs submitted while [re]starting the compiler: wait.
            break

        case .running(let child):
            pendingCompilations.forEach { job in
                activeCompilations[job.compilationID] = job
                job.notifyStart()
                job.futureResult.whenComplete { result in
                    self.activeCompilations[job.compilationID] = nil
                }
                send(message: .with { $0.compileRequest = job.compileReq }, to: child)
            }
            pendingCompilations = []
        }
    }

    /// Central message-sending and write-error detection.
    private func send(message: Sass_EmbeddedProtocol_InboundMessage, to child: Exec.Child) {
        eventLoop.preconditionInEventLoop()

        let writePromise = eventLoop.makePromise(of: Void.self)
        child.standardInput.writeAndFlush(message, promise: writePromise)
        writePromise.futureResult.whenFailure { error in
            self.handle(error: ProtocolError("Write to Sass compiler failed: \(error)."))
        }
    }

    /// Inbound message handler
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) {
        eventLoop.preconditionInEventLoop()
        debug("Rx: \(message.logMessage)")

        guard case let .running(child) = state else {
            debug("    discarding, compiler is resetting.")
            return // don't care, got no jobs left
        }

        let replyFuture: EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?>

        if let compilationID = message.compilationID {
            guard let compilation = activeCompilations[compilationID] else {
                handle(error: ProtocolError("Received message for unknown compilation ID \(compilationID): \(message)"))
                return
            }
            replyFuture = compilation.receive(message: message)
        } else {
            replyFuture = receiveGlobal(message: message)
        }

        replyFuture.whenSuccess {
            if let response = $0 {
                self.send(message: response, to: child)
            }
        }
        replyFuture.whenFailure {
            self.handle(error: $0)
        }
    }

    /// Global message handler
    /// ie. messages not associated with a compilation ID.
    private func receiveGlobal(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        eventLoop.preconditionInEventLoop()

        switch message.message {
        case .error(let error):
            return eventLoop.makeFailedFuture(ProtocolError("Sass compiler signalled a protocol error, type=\(error.type), id=\(error.id): \(error.message)"))
        default:
            return eventLoop.makeFailedFuture(ProtocolError("Sass compiler sent something uninterpretable: \(message)."))
        }
    }

    /// Central transport/protocol error detection and 'recovery'.
    ///
    /// Errors come from:
    /// 1. Write transport errors, reported by a promise from `send(message:to:)`
    /// 2. Read transport errors, reported by the channel handler from `InboundMsgHandler.errorCaught(...)`
    /// 3. Protocol errors reported by the Sass compiler, from `receieveGlobal(message:)`
    /// 4. Protocol errors detected by us, from `receive(message)` and `Compilation.receive(message)`.
    /// 5. User-injected restarts, from `reinit()`.
    ///
    /// In all cases we brutally restart the compiler and fail back all the jobs.  Need experience of how this
    /// actually fails before doing anything more.
    @discardableResult
    func handle(error: Error) -> EventLoopFuture<Void> {
        eventLoop.preconditionInEventLoop()

        switch state {
        case .initializing(let future):
            // already initializing
            return future

        case .running(let child):
            let initPromise = eventLoop.makePromise(of: Void.self)
            state = .initializing(initPromise.futureResult)
            activeCompilations.values.forEach {
                $0.cancel(with: error)
            }
            // TODO: need to quiesce jobs active in client
            precondition(activeCompilations.isEmpty, "Uncancelled compilations")

            debug("Restarting compiler from running")
            child.terminate()
            child.close()
                .flatMap {
                    self.startCompiler()
                }.cascade(to: initPromise)
            return initPromise.futureResult

        case .broken(_):
            debug("Restarting compiler from broken")
            let future = startCompiler()
            state = .initializing(future)
            return future

        case .quiescing(_, _):
            preconditionFailure("TODO - error vs. quiesce")

        case .shutdown:
            return eventLoop.makeFailedFuture(ProtocolError("Instance is shutdown, ignoring: \(error)"))
        }
    }

    private func shutdown() -> EventLoopFuture<Void> {
        eventLoop.preconditionInEventLoop()

        switch state {
        case .initializing(let initFuture):
            let shutdownPromise = eventLoop.makePromise(of: Void.self)
            initFuture.whenComplete { _ in
                self.shutdown().cascade(to: shutdownPromise)
            }
            return shutdownPromise.futureResult

        case .running(let child):
            let shutdownPromise = eventLoop.makePromise(of: Void.self)
            state = .shutdown

            activeCompilations.values.forEach {
                $0.cancel(with: ProtocolError("TODO: Shutdown vs. job-submission"))
            }
            // TODO: need to quiesce jobs
            precondition(activeCompilations.isEmpty, "Uncancelled compilations")

            child.terminate()
            child.close().whenComplete { _ in
                self.initThread.shutdownGracefully { _ in
                    shutdownPromise.succeed(())
                }
            }
            return shutdownPromise.futureResult

        case .broken(_), .shutdown:
            state = .shutdown
            return eventLoop.makeSucceededFuture(())

        case .quiescing(_, let future):
            return future
        }
    }

    /// Inbound message dispatch, top-level validation
//    private func receiveMessages() throws -> CompilerResults {
//        let timer = Timer()
//
//            let elapsedTime = timer.elapsed
//            let timeout = overallTimeout < 0 ? -1 : max(1, overallTimeout - elapsedTime)
//    }

//
//    // MARK: Importers
//
//    /// Helper
//    private func getImporter(importerID: UInt32) throws -> Importer {
//        let minImporterID = Compiler.baseImporterID
//        let maxImporterID = minImporterID + UInt32(currentImporters.count) - 1
//        guard importerID >= minImporterID, importerID <= maxImporterID else {
//            throw ProtocolError("Bad importer ID \(importerID), out of range (\(minImporterID)-\(maxImporterID))")
//        }
//        guard let importer = currentImporters[Int(importerID - minImporterID)].importer else {
//            throw ProtocolError("Bad importer ID \(importerID), not an importer")
//        }
//        return importer
//    }
//
//    /// Inbound `CanonicalizeRequest` handler
//    private func receive(canonicalizeRequest req: Sass_EmbeddedProtocol_OutboundMessage.CanonicalizeRequest) throws {
//        let importer = try getImporter(importerID: req.importerID)
//        var rsp = Sass_EmbeddedProtocol_InboundMessage.CanonicalizeResponse()
//        rsp.id = req.id
//        do {
//            if let canonicalURL = try importer.canonicalize(importURL: req.url) {
//                rsp.url = canonicalURL.absoluteString
//                debug("  tx canon-rsp-success reqid=\(req.id)")
//            } else {
//                // leave result nil -> can't deal with this request
//                debug("  tx canon-rsp-nil reqid=\(req.id)")
//            }
//        } catch {
//            rsp.error = String(describing: error)
//            debug("  tx canon-rsp-error reqid=\(req.id)")
//        }
////        try child.send(message: .with { $0.message = .canonicalizeResponse(rsp) })
//    }
//
//    /// Inbound `ImportRequest` handler
//    private func receive(importRequest req: Sass_EmbeddedProtocol_OutboundMessage.ImportRequest) throws {
//        let importer = try getImporter(importerID: req.importerID)
//        guard let url = URL(string: req.url) else {
//            throw ProtocolError("Malformed import URL \(req.url)")
//        }
//        var rsp = Sass_EmbeddedProtocol_InboundMessage.ImportResponse()
//        rsp.id = req.id
//        do {
//            let results = try importer.load(canonicalURL: url)
//            rsp.success = .with { msg in
//                msg.contents = results.contents
//                msg.syntax = .init(results.syntax)
//                results.sourceMapURL.flatMap { msg.sourceMapURL = $0.absoluteString }
//            }
//            debug("  tx import-rsp-success reqid=\(req.id)")
//        } catch {
//            rsp.error = String(describing: error)
//            debug("  tx import-rsp-error reqid=\(req.id)")
//        }
////        try child.send(message: .with { $0.message = .importResponse(rsp) })
//    }
//
//    // MARK: Functions
//
//    /// Inbound 'FunctionCallRequest' handler
//    private func receive(functionCallRequest req: Sass_EmbeddedProtocol_OutboundMessage.FunctionCallRequest) throws {
//        /// Helper to run the callback after we locate it
//        func doSassFunction(_ fn: SassFunction) throws {
//            var rsp = Sass_EmbeddedProtocol_InboundMessage.FunctionCallResponse()
//            rsp.id = req.id
//            do {
//                let resultValue = try fn(req.arguments.map { try $0.asSassValue() })
//                rsp.success = .init(resultValue)
//                debug("  tx fncall-rsp-success reqid=\(req.id)")
//            } catch {
//                rsp.error = String(describing: error)
//                debug("  tx fncall-rsp-error reqid=\(req.id)")
//            }
////            try child.send(message: .with { $0.message = .functionCallResponse(rsp) })
//        }
//
//        switch req.identifier {
//        case .functionID(let id):
//            guard let sassDynamicFunc = Sass._lookUpDynamicFunction(id: id) else {
//                throw ProtocolError("Host function id \(id) not registered.")
//            }
//            try doSassFunction(sassDynamicFunc.function)
//
//        case .name(let name):
//            guard let sassFunc = currentFunctions[name] else {
//                throw ProtocolError("Host function \(name) not registered.")
//            }
//            try doSassFunction(sassFunc)
//
//        case nil:
//            throw ProtocolError("Missing 'identifier' field in FunctionCallRequest")
//        }
//    }
}

private extension ImportResolver {
    var importer: Importer? {
        switch self {
        case .loadPath(_): return nil
        case .importer(let i): return i
        }
    }
}

final class Compilation {
    let compileReq: Sass_EmbeddedProtocol_InboundMessage.CompileRequest
    private let promise: EventLoopPromise<CompilerResults>
    private let importers: [ImportResolver]
    private let functions: SassFunctionMap
    private var messages: [CompilerMessage]
    private let timeoutSeconds: Int
    private var timer: Scheduled<Void>?
    private let resetRequest: (Error) -> Void

    private static var _nextCompilationID = UInt32(4000)
    private static var nextCompilationID: UInt32 {
        defer { _nextCompilationID += 1 }
        return _nextCompilationID
    }

    var compilationID: UInt32 {
        compileReq.id
    }

    var futureResult: EventLoopFuture<CompilerResults> {
        promise.futureResult
    }

    private var eventLoop: EventLoop {
        promise.futureResult.eventLoop
    }

    private func debug(_ message: String) {
        Compiler.logger.debug("CompID \(compilationID): \(message)")
    }

    /// Format and remember all the gorpy stuff we need to run a job.
    init(promise: EventLoopPromise<CompilerResults>,
         input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
         outputStyle: CssStyle,
         createSourceMap: Bool,
         importers: [ImportResolver],
         functionsMap: [SassFunctionSignature : (String, SassFunction)],
         timeoutSeconds: Int,
         resetRequest: @escaping (Error) -> Void) {
        self.promise = promise
        self.importers = importers
        self.functions = functionsMap.mapValues { $0.1 }
        self.timeoutSeconds = timeoutSeconds
        self.timer = nil
        self.resetRequest = resetRequest
        self.compileReq = .with { msg in
            msg.id = Self.nextCompilationID
            msg.input = input
            msg.style = .init(outputStyle)
            msg.sourceMap = createSourceMap
            msg.importers = .init(importers, startingID: Self.baseImporterID)
            msg.globalFunctions = functionsMap.values.map { $0.0 }
        }
        self.messages = []

        futureResult.whenComplete { [self] in
            timer?.cancel()
            switch $0 {
            case .success(_):
                debug("complete: success")
            case .failure(let error):
                if error is CompilerError {
                    debug("complete: compiler error")
                } else {
                    debug("complete: protocol error")
                }
            }
        }
    }

    /// Notify that the initial compile-req has been sent.
    func notifyStart() {
        debug("send Compile-Req, starting \(timeoutSeconds)s timer")
        timer = eventLoop.scheduleTask(in: .seconds(Int64(timeoutSeconds))) { [self] in
            resetRequest(ProtocolError("Timeout: job \(compilationID) timed out after \(timeoutSeconds)"))
        }
    }

    /// Abandon the job with a given error - because it never gets a chance to start or as a result
    /// of a timeout -> reset.
    func cancel(with error: Error) {
        timer?.cancel()
        promise.fail(error)
    }

    static let baseImporterID = UInt32(4000)

    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        do {
            switch message.message {
            case .compileResponse(let rsp):
                try receive(compileResponse: rsp)

            case .logEvent(let rsp):
                try receive(log: rsp)

            //        case .canonicalizeRequest(let req):
            //            try receive(canonicalizeRequest: req)
            //
            //        case .importRequest(let req):
            //            try receive(importRequest: req)
            //
            //        case .functionCallRequest(let req):
            //            try receive(functionCallRequest: req)

            default:
                throw ProtocolError("Unexpected message for compilationID \(compilationID): \(message)")
            }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
        return eventLoop.makeSucceededFuture(nil)
    }

    /// Inbound `CompileResponse` handler
    private func receive(compileResponse: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse) throws {
        switch compileResponse.result {
        case .success(let s):
            promise.succeed(.init(s, messages: messages))
        case .failure(let f):
            promise.fail(CompilerError(f, messages: messages))
        case nil:
            throw ProtocolError("Malformed CompileResponse, missing `result`: \(compileResponse)")
        }
    }

    /// Inbound `LogEvent` handler
    private func receive(log: Sass_EmbeddedProtocol_OutboundMessage.LogEvent) throws {
        try messages.append(.init(log))
    }
}

/// Shim final read channel handler, pass on to Compiler
private final class InboundMsgHandler: ChannelInboundHandler {
    typealias InboundIn = Sass_EmbeddedProtocol_OutboundMessage

    private weak var compiler: Compiler?

    init(compiler: Compiler) {
        self.compiler = compiler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        compiler?.receive(message: unwrapInboundIn(data))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        compiler?.handle(error: ProtocolError("Read from Sass compiler failed: \(error)"))
    }
}
