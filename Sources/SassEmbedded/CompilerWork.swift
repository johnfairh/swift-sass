//
//  CompilerWork.swift
//  SassEmbedded
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIO
import NIOConcurrencyHelpers
import Sass
import Foundation

/// The part of the compiler that deals with actual Sass things rather than process management.
/// It understands the contents of the Sass protocol messages.
///
/// Looks after global Sass state, a queue of pending work and a set of active work.
/// It can quiesce active work.  It manages compilation timeouts.
/// It has an API back to CompilerControl to call for a reset if things get too much.
final class CompilerWork {
    /// Event loop we're all running on
    private let eventLoop: EventLoop
    /// Async callback to request the system be reset
    private let resetRequest: (Error) -> Void
    /// Configured max timeout, seconds
    private let timeout: Int
    /// Configured global importer rules, for all compilations
    private let globalImporters: [AsyncImportResolver]
    /// Configured functions, for all compilations
    private let globalFunctions: SassAsyncFunctionMap

    /// Unstarted compilation work
    private var pendingCompilations: [Compilation]
    /// Active compilation work indexed by CompilationID
    private var activeCompilations: [UInt32 : Compilation]
    /// Promise tracking active work quiesce
    private var quiescePromise: EventLoopPromise<Void>?

    init(eventLoop: EventLoop,
         resetRequest: @escaping (Error) -> Void,
         timeout: Int,
         importers: [AsyncImportResolver],
         functions: SassAsyncFunctionMap) {
        self.eventLoop = eventLoop
        self.resetRequest = resetRequest
        self.timeout = timeout
        globalImporters = importers
        globalFunctions = functions
        pendingCompilations = []
        activeCompilations = [:]
        quiescePromise = nil
    }

    deinit {
        precondition(pendingCompilations.isEmpty)
        precondition(!hasActiveCompilations)
    }

    var hasActiveCompilations: Bool {
        !activeCompilations.isEmpty
    }

    /// Add a new compilation request to the pending queue.
    /// Return the future for the job.
    func addPendingCompilation(input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
                               outputStyle: CssStyle,
                               createSourceMap: Bool,
                               importers: [AsyncImportResolver],
                               functions: SassAsyncFunctionMap) -> EventLoopFuture<CompilerResults> {
        eventLoop.preconditionInEventLoop()

        // Figure out functions - semantic name does not include params so merge global
        // and per-job based on name alone, then pass the whole lot to the job.
        let localFnsNameMap = functions._asSassFunctionNameElementMap
        let globalFnsNameMap = globalFunctions._asSassFunctionNameElementMap
        let mergedFnsNameMap = globalFnsNameMap.merging(localFnsNameMap) { g, l in l }

        let promise = eventLoop.makePromise(of: CompilerResults.self)

        let compilation = Compilation(
                promise: promise,
                input: input,
                outputStyle: outputStyle,
                createSourceMap: createSourceMap,
                importers: globalImporters + importers,
                functionsMap: mergedFnsNameMap)

        pendingCompilations.append(compilation)

        return promise.futureResult
    }

    /// Cancel any pending (unstarted) jobs.
    func cancelAllPending(with error: Error) {
        let copy = pendingCompilations
        pendingCompilations = []
        copy.forEach {
            $0.cancel(with: error)
        }
    }

    /// Start all pending (unstarted) jobs.
    /// Actually just return the messages to send, we don't do the actual I/O here.
    /// But do tasks assuming they've been sent.
    func startAllPending() -> [Sass_EmbeddedProtocol_InboundMessage] {
        pendingCompilations.forEach { job in
            activeCompilations[job.compilationID] = job
            job.start(timeout: timeout)?.whenSuccess { [self] in
                resetRequest(
                    ProtocolError("Timeout: CompID=\(job.compilationID) timed out after \(timeout)s"))
            }
            job.futureResult.whenComplete { result in
                self.activeCompilations[job.compilationID] = nil
                self.kickQuiesce()
            }
        }
        defer { pendingCompilations = [] }
        return pendingCompilations.map { job in .with { $0.compileRequest = job.compileReq } }
    }

    /// Try to cancel any active jobs.  This means stop waiting for the Sass compiler to respond,
    /// it has been taken care of elsewhere, but don't preempty any client completions.
    /// ie: after this routine, there may still be active jobs: see `quiesce()`.
    func cancelAllActive(with error: Error) {
        activeCompilations.values.forEach {
            $0.cancel(with: error)
        }
    }

    /// Start a process that notifies when all active jobs are complete.
    func quiesce() -> EventLoopFuture<Void> {
        precondition(quiescePromise == nil, "Overlapping quiesce requests")
        let promise = eventLoop.makePromise(of: Void.self)
        quiescePromise = promise
        kickQuiesce()
        return promise.futureResult
    }

    /// Nudge the quiesce process.
    private func kickQuiesce() {
        if let quiescePromise = quiescePromise {
            if activeCompilations.isEmpty {
                self.quiescePromise = nil
                quiescePromise.succeed(())
            } else {
                Compiler.logger.debug("Waiting for outstanding compilations: \(activeCompilations.count)")
            }
        }
    }

    /// Handle an inbound message from the Sass compiler.
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        if let compilationID = message.compilationID {
            guard let compilation = activeCompilations[compilationID] else {
                return eventLoop.makeProtocolError("Received message for unknown CompID=\(compilationID): \(message)")
            }
            return compilation.receive(message: message)
        }

        return receiveGlobal(message: message)
    }

    /// Global message handler
    /// ie. messages not associated with a compilation ID.
    private func receiveGlobal(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        eventLoop.preconditionInEventLoop()

        switch message.message {
        case .error(let error):
            return eventLoop.makeProtocolError("Sass compiler signalled a protocol error, type=\(error.type), ID=\(error.id): \(error.message)")
        default:
            return eventLoop.makeProtocolError("Sass compiler sent something uninterpretable: \(message)")
        }
    }
}

private extension AsyncImportResolver {
    var importer: AsyncImporter? {
        switch self {
        case .loadPath(_): return nil
        case .importer(let i): return i
        }
    }
}

/// A compilation request tracker, owned by `CompilerWork`.
///
final class Compilation {
    let compileReq: Sass_EmbeddedProtocol_InboundMessage.CompileRequest
    private let promise: EventLoopPromise<CompilerResults>
    private let importers: [AsyncImportResolver]
    private let functions: SassAsyncFunctionMap
    private var messages: [CompilerMessage]
    private var timer: Scheduled<Void>?

    enum State {
        // waiting on computation or the compiler
        case normal
        // waiting on a future from a custom importer/hostfn
        case client
        // waiting on custom, error pending
        case client_error(Error)

        var isInClient: Bool {
            switch self {
            case .normal: return false
            case .client, .client_error: return true
            }
        }
    }

    private var state: State

    private static var _nextCompilationID = NIOAtomic<UInt32>.makeAtomic(value: 4000)
    private static var nextCompilationID: UInt32 {
        _nextCompilationID.add(1)
    }
    static var peekNextCompilationID: UInt32 {
        _nextCompilationID.load()
    }

    var compilationID: UInt32 {
        compileReq.id
    }

    var futureResult: EventLoopFuture<CompilerResults> {
        promise.futureResult
    }

    private var eventLoop: EventLoop {
        futureResult.eventLoop
    }

    private func debug(_ message: String) {
        Compiler.logger.debug("CompID=\(compilationID): \(message)")
    }

    /// Format and remember all the gorpy stuff we need to run a job.
    init(promise: EventLoopPromise<CompilerResults>,
         input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
         outputStyle: CssStyle,
         createSourceMap: Bool,
         importers: [AsyncImportResolver],
         functionsMap: [SassFunctionSignature : (String, SassAsyncFunction)]) {
        self.promise = promise
        self.importers = importers
        self.functions = functionsMap.mapValues { $0.1 }
        self.timer = nil
        self.compileReq = .with { msg in
            msg.id = Self.nextCompilationID
            msg.input = input
            msg.style = .init(outputStyle)
            msg.sourceMap = createSourceMap
            msg.importers = .init(importers, startingID: Compilation.baseImporterID)
            msg.globalFunctions = functionsMap.values.map { $0.0 }
        }
        self.messages = []
        self.state = .normal

        futureResult.whenComplete { [self] in
            precondition(!state.isInClient)
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

    /// Notify that the initial compile-req has been sent.  Return any timeout handler.
    func start(timeout: Int) -> EventLoopFuture<Void>? {
        if timeout >= 0 {
            debug("send Compile-Req, starting \(timeout)s timer")
            timer = eventLoop.scheduleTask(in: .seconds(Int64(timeout))) { }
            return timer?.futureResult
        }
        debug("send Compile-Req, no timeout")
        return nil
    }

    /// Abandon the job with a given error - because it never gets a chance to start or as a result
    /// of a timeout -> reset, or because of a protocol error on another job.
    func cancel(with error: Error) {
        timer?.cancel()
        if !state.isInClient {
            promise.fail(error)
        } else {
            debug("waiting to cancel while hostfn/importer runs")
            state = .client_error(error)
        }
    }

    /// Wrapper to match the 'stopped' version
    private func clientStarting() {
        precondition(!state.isInClient)
        state = .client
    }

    /// Deferred cancellation at the end of client activity
    private func clientStopped() {
        let oldState = state
        state = .normal

        precondition(oldState.isInClient)
        if case let .client_error(error) = oldState {
            debug("hostfn/importer done, cancelling")
            promise.fail(error)
        }
    }

    // Receive empire.
    // This is structurally very gorpy: everything can report errors indicating
    // some nonsense in the message, and some messages go async to generate a
    // reply.
    //
    // Do some renaming to increase readability.
    private typealias OBM = Sass_EmbeddedProtocol_OutboundMessage
    private typealias IBM = Sass_EmbeddedProtocol_InboundMessage

    /// Inbound messages.
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        do {
            switch message.message {
            case .compileResponse(let rsp):
                return try receive(compileResponse: rsp)

            case .logEvent(let rsp):
                return try receive(log: rsp)

            case .canonicalizeRequest(let req):
                return try receive(canonicalizeRequest: req)

            case .importRequest(let req):
                return try receive(importRequest: req)

            case .functionCallRequest(let req):
                return try receive(functionCallRequest: req)

            case .fileImportRequest(let req):
                return eventLoop.makeProtocolError("Unexpected FileImport-Req: \(req)")

            case nil, .error:
                preconditionFailure("Unreachable: message type not associated with CompID: \(message)")
            }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }

    /// Inbound `CompileResponse` handler
    private func receive(compileResponse: OBM.CompileResponse) throws -> EventLoopFuture<IBM?> {
        switch compileResponse.result {
        case .success(let s):
            promise.succeed(.init(s, messages: messages))
        case .failure(let f):
            promise.fail(CompilerError(f, messages: messages))
        case nil:
            throw ProtocolError("Malformed Compile-Rsp, missing `result`: \(compileResponse)")
        }
        return eventLoop.makeSucceededFuture(nil)
    }

    /// Inbound `LogEvent` handler
    private func receive(log: OBM.LogEvent) throws -> EventLoopFuture<IBM?> {
        try messages.append(.init(log))
        return eventLoop.makeSucceededFuture(nil)
    }

    // MARK: Importers

    static let baseImporterID = UInt32(4000)

    /// Helper
    private func getImporter(importerID: UInt32) throws -> AsyncImporter {
        let minImporterID = Compilation.baseImporterID
        let maxImporterID = minImporterID + UInt32(importers.count) - 1
        guard importerID >= minImporterID, importerID <= maxImporterID else {
            throw ProtocolError("Bad importer ID \(importerID), out of range (\(minImporterID)-\(maxImporterID))")
        }
        guard let importer = importers[Int(importerID - minImporterID)].importer else {
            throw ProtocolError("Bad importer ID \(importerID), not an importer")
        }
        return importer
    }

    /// Inbound `CanonicalizeRequest` handler
    private func receive(canonicalizeRequest req: OBM.CanonicalizeRequest) throws -> EventLoopFuture<IBM?> {
        let importer = try getImporter(importerID: req.importerID)
        var rsp = IBM.CanonicalizeResponse.with { $0.id = req.id }

        clientStarting()

        return importer.canonicalize(eventLoop: eventLoop, importURL: req.url)
            .map { canonURL -> IBM.CanonicalizeResponse in
                if let canonURL = canonURL {
                    rsp.url = canonURL.absoluteString
                    self.debug("Tx Canon-Rsp-Success ReqID=\(req.id)")
                } else {
                    // leave result nil -> can't deal with this request
                    self.debug("Tx Canon-Rsp-Nil ReqID=\(req.id)")
                }
                return rsp
            }.recover { error in
                rsp.error = String(describing: error)
                self.debug("Tx Canon-Rsp-Error ReqID=\(req.id)")
                return rsp
            }.map { rsp in
                self.clientStopped()
                return .with { $0.message = .canonicalizeResponse(rsp) }
            }
    }

    /// Inbound `ImportRequest` handler
    private func receive(importRequest req: OBM.ImportRequest) throws -> EventLoopFuture<IBM?> {
        let importer = try getImporter(importerID: req.importerID)
        guard let url = URL(string: req.url) else {
            throw ProtocolError("Malformed import URL: \(req.url)")
        }
        var rsp = IBM.ImportResponse.with { $0.id = req.id }

        clientStarting()

        return importer.load(eventLoop: eventLoop, canonicalURL: url)
            .map { results -> IBM.ImportResponse in
                rsp.success = .with { msg in
                    msg.contents = results.contents
                    msg.syntax = .init(results.syntax)
                    results.sourceMapURL.flatMap { msg.sourceMapURL = $0.absoluteString }
                }
                self.debug("Tx Import-Rsp-Success ReqID=\(req.id)")
                return rsp
            }.recover { error in
                rsp.error = String(describing: error)
                self.debug("Tx Import-Rsp-Error ReqID=\(req.id)")
                return rsp
            }.map { rsp in
                self.clientStopped()
                return .with { $0.message = .importResponse(rsp) }
            }
    }

    // MARK: Functions

    /// Inbound 'FunctionCallRequest' handler
    private func receive(functionCallRequest req: OBM.FunctionCallRequest) throws -> EventLoopFuture<IBM?> {
        /// Helper to run the callback after we locate it
        func doSassFunction(_ fn: @escaping SassAsyncFunction) throws -> EventLoopFuture<IBM?> {
            var rsp = IBM.FunctionCallResponse.with { $0.id = req.id }

            let args = try req.arguments.map { try $0.asSassValue() }

            clientStarting()

            return fn(self.eventLoop, args).map { resultValue -> IBM.FunctionCallResponse in
                rsp.success = .init(resultValue)
                self.debug("Tx FnCall-Rsp-Success ReqID=\(req.id)")
                return rsp
            }.recover { error in
                rsp.error = String(describing: error)
                self.debug("Tx FnCall-Rsp-Error ReqID=\(req.id)")
                return rsp
            }.map { rsp in
                self.clientStopped()
                return .with { $0.message = .functionCallResponse(rsp) }
            }
        }

        switch req.identifier {
        case .functionID(let id):
            guard let sassDynamicFunc = Sass._lookUpDynamicFunction(id: id) else {
                throw ProtocolError("Host function ID=\(id) not registered.")
            }
            if let asyncDynamicFunc = sassDynamicFunc as? SassAsyncDynamicFunction {
                return try doSassFunction(asyncDynamicFunc.asyncFunction)
            }
            return try doSassFunction(SyncFunctionAdapter(sassDynamicFunc.function))

        case .name(let name):
            guard let sassFunc = functions[name] else {
                throw ProtocolError("Host function name '\(name)' not registered.")
            }
            return try doSassFunction(sassFunc)

        case nil:
            throw ProtocolError("Missing 'identifier' field in FunctionCallRequest")
        }
    }
}
