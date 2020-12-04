//
//  Compiler.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import Foundation
import NIO
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
        case initializing
        /// Child is running and accepting compilation jobs.
        case running(Exec.Child)
        /// Child is broken.  Fail new jobs with the error.
        case broken(Error)
    }

    /// Compiler process state.  Internal for test access.
    private(set) var state: State

    private var childRestart: (() -> EventLoopFuture<Void>)!

    // Configuration
    private let overallTimeout: Int
    private let globalImporters: [ImportResolver]
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
        childRestart = nil // self-ref kludge
        state = .initializing
        pendingCompilations = []
        activeCompilations = [:]

        // Pull out the child setup stuff so that it can be called again later.
        childRestart = { [unowned self] in
            var nextChild: Exec.Child!
            return initThread.runIfActive(eventLoop: eventLoop) { () -> Exec.Child in
                try Exec.spawn(embeddedCompilerURL, group: eventLoop)
            }.map { child in
                nextChild = child
            }.flatMap {
                ProtocolWriter.addHandler(to: nextChild.standardInput)
            }.flatMap {
                ProtocolReader.addHandler(to: nextChild.standardOutput)
            }.flatMap {
                nextChild.standardOutput.pipeline.addHandler(InboundMsgHandler(compiler: self))
            }.map {
                state = .running(nextChild)
                kickCompilations()
            }.flatMapErrorThrowing { error in
                state = .broken(error)
                kickCompilations()
                throw error
            }
        }
        try childRestart().wait()
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
        if case let .running(child) = state {
            child.process.terminate()
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
    /// Don't use this to unstick a stuck `compile(...)` call, that will terminate eventually.
//    public func reinit() throws {
//        precondition(state.isCompileRequestLegal)
//        child.process.terminate()
//        try restart()
//    }

    /// The process ID of the compiler process.
    ///
    /// Not normally needed; can be used to adjust resource usage or maybe send it a signal if stuck.
    /// The process ID is reported as `nil` if there currently is no running child process.
    public var compilerProcessIdentifier: EventLoopFuture<Int32?> {
        eventLoop.submit { [unowned self] in
            guard case let .running(child) = state else {
                return nil
            }
            return child.process.processIdentifier
        }
    }

    public var debugHandler: DebugHandler?

    private func debug(_ msg: @autoclosure () -> String) {
        debugHandler?(DebugMessage("[compid=\("???")] \(msg())"))
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
                functionsMap: mergedFnsNameMap)

            pendingCompilations.append(compilation)
            kickCompilations()
        }

        return promise.futureResult
    }

    /// Consider the pending work queue.  When we change `state` or add to `pendingCompilations`.`
    private func kickCompilations() {
        eventLoop.preconditionInEventLoop()

        switch state {
        case .broken(let error):
            // jobs submitted while restarting the compiler, restart failed: fail them.
            pendingCompilations.forEach {
                $0.promise.fail(ProtocolError("Sass compiler failed to restart after previous error: \(error)."))
            }
            pendingCompilations = []

        case .initializing:
            // jobs submitted while [re]starting the compiler: wait.
            break

        case .running(let child):
            pendingCompilations.forEach { job in
                activeCompilations[job.compilationID] = job
                job.notifyStart()
                job.promise.futureResult.whenComplete { _ in
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
        writePromise.futureResult.whenComplete { result in
            if case let .failure(error) = result {
                self.handle(error: ProtocolError("Write to Sass compiler failed: \(error)."))
            }
        }
    }

    /// Inbound message handler
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) {
        eventLoop.preconditionInEventLoop()
        debug("  rx \(message.logMessage)")

        guard case let .running(child) = state else {
            // TODO log
            return // don't care, got no jobs left
        }

        do {
            guard let compilationID = message.compilationID else {
                try receiveGlobal(message: message)
                return
            }

            guard let compilation = activeCompilations[compilationID] else {
                throw ProtocolError("Received message for unknown compilation ID \(compilationID): \(message)")
            }

            if let response = try compilation.receive(message: message) {
                send(message: response, to: child)
            }
        } catch {
            handle(error: error)
        }
    }

    /// Global message handler
    /// ie. messages not associated with a compilation ID.
    private func receiveGlobal(message: Sass_EmbeddedProtocol_OutboundMessage) throws {
        eventLoop.preconditionInEventLoop()

        switch message.message {
        case .error(let error):
            throw ProtocolError("Sass compiler signalled a protocol error, type=\(error.type), id=\(error.id): \(error.message)")
        default:
            throw ProtocolError("Sass compiler sent something uninterpretable: \(message).")
        }
    }

    /// Central transport/protocol error detection and 'recovery'.
    ///
    /// Errors come from:
    /// 1. Write transport errors, reported by a promise from `send(message:to:)`
    /// 2. Read transport errors, reported by the channel handler from `InboundMsgHandler.errorCaught(...)`
    /// 3. Protocol errors reported by the Sass compiler, from `receieveGlobal(message:)`
    /// 4. Protocol errors detected by us, from `receive(message)` and `Compilation.receive(message)`.
    ///
    /// In all cases we brutally restart the compiler and fail back all the jobs.  Need experience of how this
    /// actually fails before doing anything more.
    func handle(error: Error) {
        eventLoop.preconditionInEventLoop()
        preconditionFailure("Not implemented: \(error)")
    }

//        do {
//            state = .active
//            debug("start")
//            try child.send(message: message)
//            let results = try receiveMessages()
//            state = .idle
//            debug("end-success")
//            return results
//        }
//        catch let error as CompilerError {
//            state = .idle
//            debug("end-compiler-error")
//            throw error
//        }
//        catch {
//            // error with some layer of the protocol.
//            // the only erp we have to is to try and restart it into a known
//            // clean state.  seems ott to retry the command here, see how we go.
//            do {
//                debug("end-protocol-error - restarting compiler...")
//                child.process.terminate()
//                try restart()
//                debug("end-protocol-error - restart ok")
//            } catch {
//                // the system looks to be broken, sadface
//                state = .idle_broken
//                debug("end-protocol-error - restart failed: \(error)")
//            }
//            // Propagate original error
//            throw error
//        }


    /// Inbound message dispatch, top-level validation
//    private func receiveMessages() throws -> CompilerResults {
//        let timer = Timer()
//
//        while true {
//            let elapsedTime = timer.elapsed
//            let timeout = overallTimeout < 0 ? -1 : max(1, overallTimeout - elapsedTime)
//            let response = try child.receive(timeout: timeout)
//            debug("  rx \(response.logMessage)")
//            if let rspCompilationID = response.compilationID,
//               rspCompilationID != compilationID {
//                throw ProtocolError("Bad compilation ID, expected \(compilationID) got \(rspCompilationID)")
//            }
//
//            switch response.message {
//            case .compileResponse(let rsp):
//                return try receive(compileResponse: rsp)
//
//            case .error(let rsp):
//                try receive(error: rsp)
//
//            case .logEvent(let rsp):
//                try receive(log: rsp)
//
//            case .canonicalizeRequest(let req):
//                try receive(canonicalizeRequest: req)
//
//            case .importRequest(let req):
//                try receive(importRequest: req)
//
//            case .functionCallRequest(let req):
//                try receive(functionCallRequest: req)
//
//            default:
//                throw ProtocolError("Unexpected response: \(response)")
//            }
//        }
//    }

//    /// Inbound `CompileResponse` handler
//    private func receive(compileResponse: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse) throws -> CompilerResults {
//        switch compileResponse.result {
//        case .success(let s):
//            return .init(s, messages: messages)
//        case .failure(let f):
//            throw CompilerError(f, messages: messages)
//        case nil:
//            throw ProtocolError("Malformed CompileResponse, missing `result`: \(compileResponse)")
//        }
//    }
//
//    /// Inbound `LogEvent` handler
//    private func receive(log: Sass_EmbeddedProtocol_OutboundMessage.LogEvent) throws {
//        try messages.append(.init(log))
//    }
//
//    // MARK: Importers
//
//    static let baseImporterID = UInt32(4000)
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

struct Compilation {
    let promise: EventLoopPromise<CompilerResults>
    private let importers: [ImportResolver]
    private let functions: SassFunctionMap
    let compileReq: Sass_EmbeddedProtocol_InboundMessage.CompileRequest
    private var messages: [CompilerMessage]

    private static var _nextCompilationID = UInt32(4000)
    private static var nextCompilationID: UInt32 {
        defer { _nextCompilationID += 1 }
        return _nextCompilationID
    }

    var compilationID: UInt32 {
        compileReq.id
    }

    var eventLoop: EventLoop {
        promise.futureResult.eventLoop
    }

    /// Format and remember all the gorpy stuff we need to run a job.
    init(promise: EventLoopPromise<CompilerResults>,
         input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
         outputStyle: CssStyle,
         createSourceMap: Bool,
         importers: [ImportResolver],
         functionsMap: [SassFunctionSignature : (String, SassFunction)]) {
        self.promise = promise
        self.importers = importers
        self.functions = functionsMap.mapValues { $0.1 }
        self.compileReq = .with { msg in
            msg.id = Self.nextCompilationID
            msg.input = input
            msg.style = .init(outputStyle)
            msg.sourceMap = createSourceMap
            msg.importers = .init(importers, startingID: Self.baseImporterID)
            msg.globalFunctions = functionsMap.values.map { $0.0 }
        }
        self.messages = []
    }

    static let baseImporterID = UInt32(4000)

    func notifyStart() {
        // timer
        // log
    }

    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) throws -> Sass_EmbeddedProtocol_InboundMessage? {
        switch message.message {
        case .compileResponse(let rsp):
            try receive(compileResponse: rsp)

//        case .logEvent(let rsp):
//            try receive(log: rsp)
//
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
        return nil
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
