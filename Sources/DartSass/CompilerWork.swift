//
//  CompilerWork.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIOCore
@_spi(SassCompilerProvider) import Sass
import struct Foundation.URL


// actor CompilerWork {
//    var outstandingWork: Int
//    var quiesced: CheckedContinuation<Void, Never>?
//
//    func quiesce() async {
//       guard outstandingWork > 0 else { return }
//       assert(quiesced.nil?)
//       await withCheckedContinuation { self.quiesced = $0 }
//       assert(outstandingWork == 0)
//       assert(quiesced.nil?)
//    }
//
//    func kickQuiesce() {
//       guard let quiesced, outstandingWork == 0 else { return }
//       self.quiesced = nil
//       quiesced.resume()
//    }


/// The part of the compiler that deals with actual Sass things rather than process management.
/// It understands the contents of the Sass protocol messages.
///
/// Looks after global Sass state, a queue of pending work and a set of active work.
/// It can quiesce active work.  It manages compiler timeouts.
/// It has an API back to CompilerControl to call for a reset if things get too much.
final class CompilerWork {
    /// Event loop we're all running on
    private let eventLoop: EventLoop
    /// Async callback to request the system be reset
    private let resetRequest: (Error) -> Void
    /// Configured max timeout, seconds
    private let timeout: Int
    /// Configured global importer rules, for all compilations
    private let globalImporters: [ImportResolver]
    /// Configured functions, for all compilations
    private let globalFunctions: SassAsyncFunctionMap

    /// Global settings passed through to Sass
    struct Settings {
        /// Message formatting style,
        let messageStyle: CompilerMessageStyle
        /// Deprecation warning verbosity
        let verboseDeprecations: Bool
        /// Warning scope
        let suppressDependencyWarnings: Bool
    }
    private let settings: Settings

    // These vars are protected by the event-loop thread, currently
    // unsafe to let async-await happen in this layer.

    /// Active compilation work indexed by CompilationID
    private var activeRequests: [UInt32 : CompilerRequest]
    /// Promise tracking active work quiesce
    private var quiescePromise: EventLoopPromise<Void>?

    init(eventLoop: EventLoop,
         resetRequest: @escaping (Error) -> Void,
         timeout: Int,
         settings: Settings,
         importers: [ImportResolver],
         functions: SassAsyncFunctionMap) {
        self.eventLoop = eventLoop
        self.resetRequest = resetRequest
        self.timeout = timeout
        self.settings = settings
        globalImporters = importers
        globalFunctions = functions
        activeRequests = [:]
        quiescePromise = nil
    }

    deinit {
        precondition(!hasActiveRequests)
    }

    var hasActiveRequests: Bool {
        !activeRequests.isEmpty
    }

    func startCompilation(input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
                          outputStyle: CssStyle,
                          sourceMapStyle: SourceMapStyle,
                          includeCharset: Bool,
                          importers: [ImportResolver],
                          stringImporter: ImportResolver? = nil,
                          functions: SassAsyncFunctionMap,
                          continuation: CheckedContinuation<CompilerResults, any Error>) -> Sass_EmbeddedProtocol_InboundMessage {
        let compilationRequest = CompilationRequest(
            input: input,
            outputStyle: outputStyle,
            sourceMapStyle: sourceMapStyle,
            includeCharset: includeCharset,
            settings: settings,
            importers: globalImporters + importers,
            stringImporter: stringImporter,
            functionsMap: globalFunctions.overridden(with: functions)) { req, res in
                Task {
                    self.activeRequests[req.requestID] = nil
                    continuation.resume(with: res)
                    self.kickQuiesce()
                }
            }

        start(request: compilationRequest)

        return .with { $0.compileRequest = compilationRequest.compileReq }
    }

    private func start<R: TypedCompilerRequest>(request: R) {
        activeRequests[request.requestID] = request
        request.start(timeoutSeconds: timeout) {
            resetRequest(
                ProtocolError("Timeout: \(request.debugPrefix) timed out after \(timeout)s"))
        }
    }

    /// Start a version request.  Bypass any pending queue.
    func startVersionRequest(continuation: CheckedContinuation<Versions, any Error>) -> Sass_EmbeddedProtocol_InboundMessage {
        let request = VersionRequest() { req, res in
            Task {
                self.activeRequests[req.requestID] = nil
                continuation.resume(with: res)
                self.kickQuiesce()
            }
        }
        start(request: request)
        return .with { $0.versionRequest = request.versionReq }
    }

    /// Try to cancel any active jobs.  This means stop waiting for the Sass compiler to respond,
    /// it has been taken care of elsewhere, but don't preempty any client completions.
    /// ie: after this routine, there may still be active jobs: see `quiesce()`.
    func cancelAllActive(with error: Error) {
        activeRequests.values.forEach {
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

    /// Test hook
    static var onStuckQuiesce: (() -> Void)? = nil

    /// Nudge the quiesce process.
    private func kickQuiesce() {
        if let quiescePromise = quiescePromise {
            if activeRequests.isEmpty {
                self.quiescePromise = nil
                quiescePromise.succeed(())
            } else {
                Compiler.logger.debug("Waiting for outstanding requests: \(activeRequests.count)")
                CompilerWork.onStuckQuiesce?()
            }
        }
    }

    /// Handle an inbound message from the Sass compiler.
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) async throws -> Sass_EmbeddedProtocol_InboundMessage? {
        if let requestID = message.requestID {
            guard let compilation = activeRequests[requestID] else {
                throw ProtocolError("Received message for unknown ReqID=\(requestID): \(message)")
            }
            return try await compilation.receive(message: message)
        }

        return try receiveGlobal(message: message)
    }

    /// Global message handler
    /// ie. messages not associated with a compilation ID.
    private func receiveGlobal(message: Sass_EmbeddedProtocol_OutboundMessage) throws -> Sass_EmbeddedProtocol_InboundMessage? {
        switch message.message {
        case .error(let error):
            throw ProtocolError("Sass compiler signalled a protocol error, type=\(error.type), ID=\(error.id): \(error.message)")
        default:
            throw ProtocolError("Sass compiler sent something uninterpretable: \(message)")
        }
    }
}
