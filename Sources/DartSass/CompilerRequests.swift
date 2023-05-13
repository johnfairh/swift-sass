//
//  CompilerRequests.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIOCore
import struct Foundation.URL
import class Dispatch.DispatchSemaphore
import Atomics
@_spi(SassCompilerProvider) import Sass

// Protocols and classes modelling compiler communication sequences
// Debug logging, multi-message exchanges, client activity
// Cancelling, timeout.
//
// CompilerRequest --- interface protocol to CompilerWork.
// ManagedCompilerRequest -- protocol to share timeout/cancelling behaviour
// CompilationRequest -- class modelling a compilation request
// VersionRequest -- class modelling a version request

// MARK: Request ID allocation

enum RequestID {
    private static var _next = ManagedAtomic<UInt32>(4000)
    fileprivate static var next: UInt32 {
        _next.loadThenWrappingIncrement(ordering: .relaxed)
    }
    // For tests
    static var peekNext: UInt32 {
        _next.load(ordering: .relaxed)
    }
}

// MARK: CompilerRequest

protocol CompilerRequest: AnyObject {
    /// Notify that the initial request has been sent.  Return any timeout handler.
    func start(timeoutSeconds: Int, onTimeout: @escaping () async -> Void)
    /// Handle a compiler response for `requestID`
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) async throws -> Sass_EmbeddedProtocol_InboundMessage?
    /// Abandon the request
    func cancel(with error: any Error)

    var requestID: UInt32 { get }
    var debugPrefix: String { get }
    var requestName: String { get }

    associatedtype ResultType
    var clientDone: (Self, Result<ResultType, any Error>) -> Void { get }
}

extension CompilerRequest {
    /// Log helper
    func debug(_ message: String) {
        Compiler.logger.debug("\(debugPrefix): \(message)")
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

struct Lock {
    private let dsem: DispatchSemaphore

    init() {
        dsem = DispatchSemaphore(value: 1)
    }

    func locked<T>(_ call: () throws -> T) rethrows -> T {
        dsem.wait()
        defer { dsem.signal() }
        return try call()
    }
}

private protocol ManagedCompilerRequest: CompilerRequest {
    var timer: Task<Void, Never>? { get set }
    var state: CompilerRequestState { get set }
    var stateLock: Lock { get }
}

extension ManagedCompilerRequest {
    func sendDone(_ result: Result<ResultType, any Error>) {
        precondition(!state.isInClient)
        timer?.cancel()
        switch result {
        case .success(_):
            debug("complete: success")
        case .failure(let error):
            if error is CompilerError {
                debug("complete: compiler error")
            } else if error is CancellationError {
                debug("complete: cancellation error")
            } else {
                debug("complete: protocol error")
            }
        }
        clientDone(self, result)
    }

    /// Notify that the initial compile-req has been sent.  Return any timeout handler.
    func start(timeoutSeconds: Int, onTimeout: @escaping () async -> Void ) {
        guard timeoutSeconds >= 0 else {
            debug("send \(requestName), no timeout")
            return
        }

        debug("send \(requestName), starting \(timeoutSeconds)s timer")
        timer = Task {
            do {
                if #available(macOS 13.0, *) {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                } else {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1000 * 1000 * 1000))
                }
                await onTimeout()
            } catch {
            }
        }
    }

    /// Abandon the job with a given error - because it never gets a chance to start or as a result
    /// of a timeout -> reset, or because of a protocol error on another job.
    func cancel(with error: any Error) {
        timer?.cancel()
        stateLock.locked {
            if !state.isInClient {
                sendDone(.failure(error))
            } else {
                debug("waiting to cancel while hostfn/importer runs")
                state = .client_error(error)
            }
        }
    }

    /// Wrapper to match the 'stopped' version
    func clientStarting() {
        stateLock.locked {
            precondition(!state.isInClient)
            state = .client
        }
    }

    /// Deferred cancellation at the end of client activity
    func clientStopped() {
        stateLock.locked {
            let oldState = state
            state = .normal

            precondition(oldState.isInClient)
            if case let .client_error(error) = oldState {
                debug("hostfn/importer done, cancelling")
                sendDone(.failure(error))
            }
        }
    }
}

// MARK: CompilationRequest

final class CompilationRequest: ManagedCompilerRequest {
    // Protocol reqs
    fileprivate var timer: Task<Void, Never>?
    fileprivate var state: CompilerRequestState
    fileprivate let stateLock: Lock
    let clientDone: (CompilationRequest, Result<CompilerResults, any Error>) -> Void

    // Debug
    var debugPrefix: String { "CompID=\(requestID)" }
    var requestName: String { "Compile-Req" }

    // Compilation-specific
    let compileReq: Sass_EmbeddedProtocol_InboundMessage.CompileRequest
    private let importers: [ImportResolver]
    private let functions: SassAsyncFunctionMap
    private var messages: [CompilerMessage]

    var requestID: UInt32 {
        compileReq.id
    }

    /// Format and remember all the gorpy stuff we need to run a job.
    init(input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
         outputStyle: CssStyle,
         sourceMapStyle: SourceMapStyle,
         includeCharset: Bool,
         settings: Compiler.Settings,
         importers: [ImportResolver],
         stringImporter: ImportResolver?,
         functionsMap: [SassFunctionSignature : (String, SassAsyncFunction)],
         done: @escaping (CompilationRequest, Result<CompilerResults, any Error>) -> Void) {
        var firstFreeImporterID = CompilationRequest.baseImporterID
        if let stringImporter = stringImporter {
            self.importers = [stringImporter] + importers
            firstFreeImporterID += 1
        } else {
            self.importers = importers
        }
        self.functions = functionsMap.mapValues { $0.1 }
        self.compileReq = .with { msg in
            msg.id = RequestID.next
            msg.input = input
            msg.style = .init(outputStyle)
            msg.sourceMap = sourceMapStyle.createSourceMap
            msg.importers = .init(importers, startingID: firstFreeImporterID)
            msg.globalFunctions = functionsMap.values.map { $0.0 }
            msg.alertAscii = false
            msg.alertColor = settings.messageStyle.isColored
            msg.verbose = settings.verboseDeprecations
            msg.quietDeps = settings.suppressDependencyWarnings
            msg.sourceMapIncludeSources = sourceMapStyle.embedSourceMap
            msg.charset = includeCharset
        }
        self.messages = []
        self.state = .normal
        self.timer = nil
        self.stateLock = Lock()
        self.clientDone = done
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
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) async throws -> Sass_EmbeddedProtocol_InboundMessage? {
        switch message.message {
        case .compileResponse(let rsp):
            return try receive(compileResponse: rsp)

        case .canonicalizeRequest(let req):
            return try await receive(canonicalizeRequest: req)

        case .importRequest(let req):
            return try await receive(importRequest: req)

        case .functionCallRequest(let req):
            return try await receive(functionCallRequest: req)

        case .fileImportRequest(let req):
            return try await receive(fileImportRequest: req)

        case .logEvent(let rsp):
            return try receive(log: rsp)

        case nil, .error, .versionResponse:
            preconditionFailure("Unreachable: message type not associated with CompID: \(message)")
        }
    }

    /// Inbound `CompileResponse` handler
    private func receive(compileResponse: OBM.CompileResponse) throws -> IBM? {
        switch compileResponse.result {
        case .success(let s):
            sendDone(.success(CompilerResults(s, messages: messages)))
        case .failure(let f):
            sendDone(.failure(CompilerError(f, messages: messages)))
        case nil:
            throw ProtocolError("Malformed Compile-Rsp, missing `result`: \(compileResponse)")
        }
        return nil
    }

    /// Inbound `LogEvent` handler
    private func receive(log: OBM.LogEvent) throws -> IBM? {
        try messages.append(.init(log))
        return nil
    }

    // MARK: Importers

    static let baseImporterID = UInt32(4000)

    /// Helper
    private func getImporter<T>(importerID: UInt32, keyPath: KeyPath<ImportResolver, T?>) throws -> T {
        let minImporterID = CompilationRequest.baseImporterID
        let maxImporterID = minImporterID + UInt32(importers.count) - 1
        guard importerID >= minImporterID, importerID <= maxImporterID else {
            throw ProtocolError("Bad importer ID \(importerID), out of range (\(minImporterID)-\(maxImporterID))")
        }
        guard let importer = importers[Int(importerID - minImporterID)][keyPath: keyPath] else {
            throw ProtocolError("Bad importer ID \(importerID), not an importer")
        }
        return importer
    }

    /// Inbound `CanonicalizeRequest` handler
    private func receive(canonicalizeRequest req: OBM.CanonicalizeRequest) async throws -> IBM? {
        let importer = try getImporter(importerID: req.importerID, keyPath: \.importer)
        var rsp = IBM.CanonicalizeResponse.with { $0.id = req.id }

        clientStarting()

        do {
            let canonURL = try await importer.canonicalize(ruleURL: req.url,
                                                           fromImport: req.fromImport)
            if let canonURL = canonURL {
                rsp.url = canonURL.absoluteString
                self.debug("Tx Canon-Rsp-Success ReqID=\(req.id)")
            } else {
                // leave result nil -> can't deal with this request
                self.debug("Tx Canon-Rsp-Nil ReqID=\(req.id)")
            }
        } catch {
            rsp.error = String(describing: error)
            self.debug("Tx Canon-Rsp-Error ReqID=\(req.id)")
        }

        self.clientStopped()
        return .with { $0.message = .canonicalizeResponse(rsp) }
    }

    /// Inbound `ImportRequest` handler
    private func receive(importRequest req: OBM.ImportRequest) async throws -> IBM? {
        let importer = try getImporter(importerID: req.importerID, keyPath: \.importer)
        guard let url = URL(string: req.url) else {
            throw ProtocolError("Malformed import URL: \(req.url)")
        }
        var rsp = IBM.ImportResponse.with { $0.id = req.id }

        clientStarting()

        do {
            if let results = try await importer.load(canonicalURL: url) {
                rsp.success = .with { msg in
                    msg.contents = results.contents
                    msg.syntax = .init(results.syntax)
                    results.sourceMapURL.flatMap { msg.sourceMapURL = $0.absoluteString }
                }
                self.debug("Tx Import-Rsp-Success ReqID=\(req.id)")
            } else {
                rsp.result = nil
                self.debug("Tx Import-Rsp-Null ReqID=\(req.id)")
            }
        } catch {
            rsp.error = String(describing: error)
            self.debug("Tx Import-Rsp-Error ReqID=\(req.id)")
        }

        self.clientStopped()
        return .with { $0.message = .importResponse(rsp) }
    }

    /// Inbound `FileImportRequest` handler
    private func receive(fileImportRequest req: OBM.FileImportRequest) async throws -> IBM? {
        let importer = try getImporter(importerID: req.importerID, keyPath: \.filesystemImporter)
        var rsp = IBM.FileImportResponse.with { $0.id = req.id }

        clientStarting()

        do {
            if let urlPath = try await importer.resolve(ruleURL: req.url, fromImport: req.fromImport) {
                rsp.fileURL = urlPath.absoluteString
                self.debug("Tx FileImport-Rsp-Success ReqID=\(req.id)")
            } else {
                // leave fileURL as nil
                self.debug("Tx FileImport-Rsp-Nil ReqID=\(req.id)")
            }
        } catch {
            rsp.error = String(describing: error)
            self.debug("Tx FileImport-Rsp-Error ReqID=\(req.id)")
        }

        self.clientStopped()
        return .with { $0.message = .fileImportResponse(rsp) }
    }

    // MARK: Functions

    /// Inbound 'FunctionCallRequest' handler
    private func receive(functionCallRequest req: OBM.FunctionCallRequest) async throws -> IBM? {
        /// Helper to run the callback after we locate it
        func doSassFunction(_ fn: @escaping SassAsyncFunction) async throws -> IBM? {
            var rsp = IBM.FunctionCallResponse.with { $0.id = req.id }

            // Set up to monitor accesses to any `SassArgumentList`s
            var accessedArgLists = Set<UInt32>()
            func accessArgList(id: UInt32) {
                guard id != 0 else { return }
                accessedArgLists.insert(id)
            }

            let args = try SassValueMonitor.with(accessArgList) {
                try req.arguments.map { try $0.asSassValue() }
            }

            clientStarting()

            do {
                let resultValue = try await fn(args)
                rsp.success = .init(resultValue)
                self.debug("Tx FnCall-Rsp-Success ReqID=\(req.id)")
            } catch {
                rsp.error = String(describing: error)
                self.debug("Tx FnCall-Rsp-Success ReqID=\(req.id)")
            }

            rsp.accessedArgumentLists = Array(accessedArgLists)
            self.clientStopped()
            return .with { $0.message = .functionCallResponse(rsp) }
        }

        switch req.identifier {
        case .functionID(let id):
            guard let sassDynamicFunc = SassDynamicFunction.lookUp(id: id) else {
                throw ProtocolError("Host function ID=\(id) not registered.")
            }
            if let asyncFunc = sassDynamicFunc as? SassAsyncDynamicFunction {
                return try await doSassFunction(asyncFunc.asyncFunction)
            }
            return try await doSassFunction(SyncFunctionAdapter(sassDynamicFunc.function))

        case .name(let name):
            guard let sassFunc = functions[name] else {
                throw ProtocolError("Host function name '\(name)' not registered.")
            }
            return try await doSassFunction(sassFunc)

        case nil:
            throw ProtocolError("Missing 'identifier' field in FunctionCallRequest")
        }
    }
}

private extension ImportResolver {
    var importer: Importer? {
        switch self {
        case .loadPath, .filesystemImporter: return nil
        case .importer(let i): return i
        }
    }

    var filesystemImporter: FilesystemImporter? {
        switch self {
        case .loadPath, .importer: return nil
        case .filesystemImporter(let f): return f
        }
    }
}

// MARK: VersionRequest

final class VersionRequest: ManagedCompilerRequest {
    // Protocol reqs
    fileprivate var timer: Task<Void, Never>?
    fileprivate var state: CompilerRequestState
    fileprivate var stateLock: Lock
    let clientDone: (VersionRequest, Result<Versions, any Error>) -> Void

    // Version-specific
    let versionReq: Sass_EmbeddedProtocol_InboundMessage.VersionRequest

    // Debug
    var debugPrefix: String { "VerID=\(requestID)" }
    var requestName: String { "Version-Req" }

    var requestID: UInt32 {
        versionReq.id
    }

    init(done: @escaping (VersionRequest, Result<Versions, any Error>) -> Void) {
        self.state = .normal
        self.timer = nil
        self.stateLock = Lock()
        self.versionReq = .with { $0.id = RequestID.next }
        self.clientDone = done
    }

    /// Inbound messages.
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) async throws -> Sass_EmbeddedProtocol_InboundMessage? {
        guard case .versionResponse(let vers) = message.message else {
            throw ProtocolError("Unexpected response to Version-Req: \(message)")
        }
        sendDone(.success(Versions(vers)))
        return nil
    }
}
