//
//  CompilerRequests.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIOCore
import NIOConcurrencyHelpers
import struct Foundation.URL
import Dispatch
@_spi(SassCompilerProvider) import Sass

// Protocols and classes modelling compiler communication sequences
// Debug logging, multi-message exchanges, client activity
// Cancelling, timeout.
//
// CompilerRequest/TypedCompilerRequest --- interface protocol to CompilerWork.
//     Split in two because of Swift associated-type limitations
// ManagedCompilerRequest -- protocol to share timeout/cancelling behaviour
// CompilationRequest -- class modelling a compilation request
// VersionRequest -- class modelling a version request

// MARK: Request ID allocation

enum RequestID {
    private static var _next = NIOAtomic<UInt32>.makeAtomic(value: 4000)
    fileprivate static var next: UInt32 {
        _next.add(1)
    }
    // For tests
    static var peekNext: UInt32 {
        _next.load()
    }
}

// MARK: CompilerRequest

protocol CompilerRequest: AnyObject {
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

private protocol ManagedCompilerRequest: TypedCompilerRequest {
    var timer: Scheduled<Void>? { get set }
    var state: CompilerRequestState { get set }
    var stateLock: Lock { get }
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
        stateLock.locked {
            if !state.isInClient {
                promise.fail(error)
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
                promise.fail(error)
            }
        }
    }
}

// MARK: CompilationRequest

final class CompilationRequest: ManagedCompilerRequest {
    // Protocol reqs
    private(set) var promise: EventLoopPromise<CompilerResults>
    fileprivate var timer: Scheduled<Void>?
    fileprivate var state: CompilerRequestState
    fileprivate let stateLock: Lock

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
    init(promise: EventLoopPromise<CompilerResults>,
         input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
         outputStyle: CssStyle,
         sourceMapStyle: SourceMapStyle,
         settings: CompilerWork.Settings,
         importers: [ImportResolver],
         stringImporter: ImportResolver?,
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
            msg.id = RequestID.next
            msg.input = input
            msg.style = .init(outputStyle)
            msg.sourceMap = .init(sourceMapStyle)
            msg.importers = .init(importers, startingID: firstFreeImporterID)
            msg.globalFunctions = functionsMap.values.map { $0.0 }
            msg.alertAscii = false
            msg.alertColor = settings.messageStyle.isColored
            msg.verbose = settings.verboseDeprecations
            msg.quietDeps = settings.suppressDependencyWarnings
        }
        self.messages = []
        self.promise = promise
        self.state = .normal
        self.timer = nil
        self.stateLock = Lock()
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
        let promise = eventLoop.makePromise(of: Optional<IBM>.self)

        // Handle log-events synchronously because they can be sent back-to-back with compile-done and
        // are un-acked.  So if left to run async, can race with the compile-done and happen *after*
        // the client has received their done....
        switch message.message {
        case .logEvent(let rsp):
            promise.completeWith(.init(catching: { try self.receive(log: rsp) }))
        default:
            promise.completeWithTask { try await self.receiveAsync(message: message) }
            break
        }

        return promise.futureResult
    }

    func receiveAsync(message: Sass_EmbeddedProtocol_OutboundMessage) async throws -> Sass_EmbeddedProtocol_InboundMessage? {
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

        case .logEvent:
            preconditionFailure("Unreachable, should be handled synchronously")

        case nil, .error, .versionResponse:
            preconditionFailure("Unreachable: message type not associated with CompID: \(message)")
        }
    }

    /// Inbound `CompileResponse` handler
    private func receive(compileResponse: OBM.CompileResponse) throws -> IBM? {
        switch compileResponse.result {
        case .success(let s):
            promise.succeed(.init(s, messages: messages))
        case .failure(let f):
            promise.fail(CompilerError(f, messages: messages))
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
    private(set) var promise: EventLoopPromise<Versions>
    fileprivate var timer: Scheduled<Void>?
    fileprivate var state: CompilerRequestState
    fileprivate var stateLock: Lock

    // Version-specific
    let versionReq: Sass_EmbeddedProtocol_InboundMessage.VersionRequest

    // Debug
    var debugPrefix: String { "VerID=\(requestID)" }
    var requestName: String { "Version-Req" }

    var requestID: UInt32 {
        versionReq.id
    }

    init(promise: EventLoopPromise<Versions>) {
        self.promise = promise
        self.state = .normal
        self.timer = nil
        self.stateLock = Lock()
        self.versionReq = .with { $0.id = RequestID.next }
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
