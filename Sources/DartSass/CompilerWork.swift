//
//  CompilerWork.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIOCore
@_spi(SassCompilerProvider) import Sass
import struct Foundation.URL

extension Compiler {
    struct Settings {
        /// Configured max timeout, seconds
        let timeout: Int
        /// Configured global importer rules, for all compilations
        let globalImporters: [ImportResolver]
        /// Configured functions, for all compilations
        let globalFunctions: SassAsyncFunctionMap
        /// Message formatting style,
        let messageStyle: CompilerMessageStyle
        /// Deprecation warning verbosity
        let verboseDeprecations: Bool
        /// Warning scope
        let suppressDependencyWarnings: Bool
    }
}

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
    /// Compiler settings
    private let settings: Compiler.Settings

    // These vars are protected by the event-loop thread, currently
    // unsafe to let async-await happen in this layer.

    /// Active compilation work indexed by CompilationID
    private var activeRequests: [UInt32 : CompilerRequest]
    /// Task waiting for quiesce
    private var quiesceContinuation: CheckedContinuation<Void, Never>?

    init(eventLoop: EventLoop,
         resetRequest: @escaping (Error) -> Void,
         settings: Compiler.Settings) {
        self.eventLoop = eventLoop
        self.resetRequest = resetRequest
        self.settings = settings
        activeRequests = [:]
        quiesceContinuation = nil
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
            importers: settings.globalImporters + importers,
            stringImporter: stringImporter,
            functionsMap: settings.globalFunctions.overridden(with: functions)) { req, res in
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
        request.start(timeoutSeconds: settings.timeout) {
            self.resetRequest(
                ProtocolError("Timeout: \(request.debugPrefix) timed out after \(self.settings.timeout)s"))
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
    func quiesce() async {
        precondition(quiesceContinuation == nil, "Overlapping quiesce requests")
        await withCheckedContinuation {
            quiesceContinuation = $0
            kickQuiesce()
        }
    }

    /// Test hook
    static var onStuckQuiesce: (() -> Void)? = nil

    /// Nudge the quiesce process.
    private func kickQuiesce() {
        if let quiesceContinuation {
            if activeRequests.isEmpty {
                self.quiesceContinuation = nil
                quiesceContinuation.resume()
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
