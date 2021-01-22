//
//  CompilerRequests.swift
//  SassEmbedded
//
//  Copyright 2020-2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIO
import NIOConcurrencyHelpers
import Foundation

// Protocols and classes modelling compiler communication sequences
// Debug logging, multi-message exchanges, client activity
// Cancelling, timeout.
//
// CompilerRequest/TypedCompilerRequest --- interface protocol to CompilerWork.
//     Split in two because of Swift associated-type limitations
// ManagedCompilerRequest -- protocol to share timeout/cancelling behaviour
// CompilationRequest -- class modelling a compilation request
// VersionRequest -- class modelling a version request

// MARK: CompilerRequest

protocol CompilerRequest: class {
    /// Notify that the initial request has been sent.  Return any timeout handler.
    func start(timeout: Int) -> EventLoopFuture<Void>?
    /// Handle a compiler response for `requestID`
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?>
    /// Abandon the request
    func cancel(with error: Error)

    var requestID: UInt32 { get }
    var debugPrefix: String { get }
    var requestName: String { get }
}

extension CompilerRequest {
    /// Log helper
    func debug(_ message: String) {
        Compiler.logger.debug("\(debugPrefix): \(message)")
    }
}

protocol TypedCompilerRequest: CompilerRequest {
    associatedtype ResultType
    var promise: EventLoopPromise<ResultType> { get }
}

extension TypedCompilerRequest {
    var futureResult: EventLoopFuture<ResultType> {
        promise.futureResult
    }

    var eventLoop: EventLoop {
        futureResult.eventLoop
    }
}

// MARK: ManagedCompilerRequest

private enum CompilerRequestState {
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

private protocol ManagedCompilerRequest: TypedCompilerRequest {
    var timer: Scheduled<Void>? { get set }
    var state: CompilerRequestState { get set }
}

extension ManagedCompilerRequest {
    /// Initialization - adopters must call during init
    func initCompilerRequest() {
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
            debug("send \(requestName), starting \(timeout)s timer")
            timer = eventLoop.scheduleTask(in: .seconds(Int64(timeout))) { }
            return timer?.futureResult
        }
        debug("send \(requestName), no timeout")
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
    func clientStarting() {
        precondition(!state.isInClient)
        state = .client
    }

    /// Deferred cancellation at the end of client activity
    func clientStopped() {
        let oldState = state
        state = .normal

        precondition(oldState.isInClient)
        if case let .client_error(error) = oldState {
            debug("hostfn/importer done, cancelling")
            promise.fail(error)
        }
    }
}

// MARK: CompilationRequest

final class CompilationRequest: ManagedCompilerRequest {
    // Protocol reqs
    private(set) var promise: EventLoopPromise<CompilerResults>
    fileprivate var timer: Scheduled<Void>?
    fileprivate var state: CompilerRequestState

    // Debug
    var debugPrefix: String { "CompID=\(requestID)" }
    var requestName: String { "Compile-Req" }

    // Compilation-specific
    let compileReq: Sass_EmbeddedProtocol_InboundMessage.CompileRequest
    private let importers: [AsyncImportResolver]
    private let functions: SassAsyncFunctionMap
    private var messages: [CompilerMessage]

    // Compilation ID management
    private static var _nextCompilationID = NIOAtomic<UInt32>.makeAtomic(value: 4000)
    private static var nextCompilationID: UInt32 {
        _nextCompilationID.add(1)
    }
    static var peekNextCompilationID: UInt32 {
        _nextCompilationID.load()
    }

    var requestID: UInt32 {
        compileReq.id
    }

    /// Format and remember all the gorpy stuff we need to run a job.
    init(promise: EventLoopPromise<CompilerResults>,
         input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
         outputStyle: CssStyle,
         createSourceMap: Bool,
         importers: [AsyncImportResolver],
         stringImporter: AsyncImportResolver?,
         functionsMap: [SassFunctionSignature : (String, SassAsyncFunction)]) {
        var firstFreeImporterID = CompilationRequest.baseImporterID
        if let stringImporter = stringImporter {
            self.importers = [stringImporter] + importers
            firstFreeImporterID += 1
        } else {
            self.importers = importers
        }
        self.functions = functionsMap.mapValues { $0.1 }
        self.compileReq = .with { msg in
            msg.id = Self.nextCompilationID
            msg.input = input
            msg.style = .init(outputStyle)
            msg.sourceMap = createSourceMap
            msg.importers = .init(importers, startingID: firstFreeImporterID)
            msg.globalFunctions = functionsMap.values.map { $0.0 }
        }
        self.messages = []
        self.promise = promise
        self.state = .normal
        self.timer = nil
        initCompilerRequest()
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

            case nil, .error, .versionResponse:
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
        let minImporterID = CompilationRequest.baseImporterID
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

private extension AsyncImportResolver {
    var importer: AsyncImporter? {
        switch self {
        case .loadPath(_): return nil
        case .importer(let i): return i
        }
    }
}

// MARK: VersionRequest

final class VersionRequest: ManagedCompilerRequest {
    // Protocol reqs
    private(set) var promise: EventLoopPromise<Versions>
    fileprivate var timer: Scheduled<Void>?
    fileprivate var state: CompilerRequestState

    // Debug
    var debugPrefix: String { "Version-Req" }
    var requestName: String { "Version-Req" }

    var versionReq: Sass_EmbeddedProtocol_InboundMessage.VersionRequest {
        .init()
    }

    static let requestID = UInt32(0xfffffffe)

    var requestID: UInt32 {
        VersionRequest.requestID
    }

    init(promise: EventLoopPromise<Versions>) {
        self.promise = promise
        self.state = .normal
        self.timer = nil
        initCompilerRequest()
    }

    /// Inbound messages.
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        guard case .versionResponse(let vers) = message.message else {
            return eventLoop.makeProtocolError("Unexpected response to Version-Req: \(message)")
        }
        promise.succeed(.init(vers))
        return eventLoop.makeSucceededFuture(nil)
    }
}
