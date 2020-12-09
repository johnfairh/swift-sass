//
//  CompilerWork.swift
//  EmbeddedSass
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
    private let globalFunctions: SassFunctionMap

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
         functions: SassFunctionMap) {
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
                               functions: SassFunctionMap) -> EventLoopFuture<CompilerResults> {
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
                    ProtocolError("Timeout: job \(job.compilationID) timed out after \(timeout)s"))
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
                return eventLoop.makeFailedFuture(ProtocolError("Received message for unknown compilation ID \(compilationID): \(message)"))
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
            return eventLoop.makeFailedFuture(ProtocolError("Sass compiler signalled a protocol error, type=\(error.type), id=\(error.id): \(error.message)"))
        default:
            return eventLoop.makeFailedFuture(ProtocolError("Sass compiler sent something uninterpretable: \(message)"))
        }
    }
}

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
    private let functions: SassFunctionMap
    private var messages: [CompilerMessage]
    private var timer: Scheduled<Void>?

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
        promise.futureResult.eventLoop
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
         functionsMap: [SassFunctionSignature : (String, SassFunction)]) {
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

    /// Notify that the initial compile-req has been sent.  Return any timeout handler.
    func start(timeout: Int) -> EventLoopFuture<Void>? {
        if timeout >= 0 {
            debug("send Compile-Req, starting \(timeout)s timer")
            timer = eventLoop.scheduleTask(in: .seconds(Int64(timeout))) { }
            return timer?.futureResult
        } else {
            debug("send Compile-Req, no timeout")
            return nil
        }
    }

    /// Abandon the job with a given error - because it never gets a chance to start or as a result
    /// of a timeout -> reset, or because of a protocol error on another job.
    func cancel(with error: Error) {
        timer?.cancel()
        promise.fail(error)
    }

    /// Inbound messages.  Rework all this error handling stuff when complete.
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        do {
            switch message.message {
            case .compileResponse(let rsp):
                try receive(compileResponse: rsp)

            case .logEvent(let rsp):
                try receive(log: rsp)

            case .canonicalizeRequest(let req):
                return try receive(canonicalizeRequest: req)

            case .importRequest(let req):
                return try receive(importRequest: req)
            //
            //        case .functionCallRequest(let req):
            //            try receive(functionCallRequest: req)

            case .functionCallRequest(_):
                throw ProtocolError("Unimplemented message for CompID=\(compilationID): \(message)")

            case nil, .error(_), .fileImportRequest(_):
                preconditionFailure("Unreachable: message type not associated with CompID: \(message)")
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
    private func receive(canonicalizeRequest req: Sass_EmbeddedProtocol_OutboundMessage.CanonicalizeRequest) throws -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        let importer = try getImporter(importerID: req.importerID)
        var rsp = Sass_EmbeddedProtocol_InboundMessage.CanonicalizeResponse()
        rsp.id = req.id

        return importer.canonicalize(eventLoop: eventLoop, importURL: req.url)
            .map { canonURL in
                if let canonURL = canonURL {
                    rsp.url = canonURL.absoluteString
                    self.debug("  tx canon-rsp-success reqid=\(req.id)")
                } else {
                    // leave result nil -> can't deal with this request
                    self.debug("  tx canon-rsp-nil reqid=\(req.id)")
                }
                return rsp
            }.recover { error in
                rsp.error = String(describing: error)
                self.debug("  tx canon-rsp-error reqid=\(req.id)")
                return rsp
            }.map { rsp in
                .with { $0.message = .canonicalizeResponse(rsp) }
            }
    }

    /// Inbound `ImportRequest` handler
    private func receive(importRequest req: Sass_EmbeddedProtocol_OutboundMessage.ImportRequest) throws -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        let importer = try getImporter(importerID: req.importerID)
        guard let url = URL(string: req.url) else {
            throw ProtocolError("Malformed import URL \(req.url)")
        }
        var rsp = Sass_EmbeddedProtocol_InboundMessage.ImportResponse()
        rsp.id = req.id

        return importer.load(eventLoop: eventLoop, canonicalURL: url)
            .map { results in
                rsp.success = .with { msg in
                    msg.contents = results.contents
                    msg.syntax = .init(results.syntax)
                    results.sourceMapURL.flatMap { msg.sourceMapURL = $0.absoluteString }
                }
                self.debug("  tx import-rsp-success reqid=\(req.id)")
                return rsp
            }.recover { error in
                rsp.error = String(describing: error)
                self.debug("  tx import-rsp-error reqid=\(req.id)")
                return rsp
            }.map { rsp in
                .with { $0.message = .importResponse(rsp) }
            }
    }
}
