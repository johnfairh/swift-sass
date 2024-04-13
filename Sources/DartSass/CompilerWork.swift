//
//  CompilerWork.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

@_spi(SassCompilerProvider) import Sass

extension Compiler {
    struct Settings {
        /// Configured max timeout, seconds
        let timeout: Int
        /// Configured global importer rules, for all compilations
        let globalImporters: [ImportResolver]
        /// Configured functions, for all compilations
        let globalFunctions: SassFunctionMap
        /// Message formatting style,
        let messageStyle: CompilerMessageStyle
        /// Deprecation warning verbosity
        let verboseDeprecations: Bool
        /// Deprecation control
        let deprecationControl: DeprecationControl
        /// Warning/Debug message scope
        let warningLevel: CompilerWarningLevel
    }
}

/// The part of the compiler that deals with actual Sass things rather than process management.
/// It understands the contents of the Sass protocol messages.
///
/// Looks after global Sass state, a queue of pending work and a set of active work.
/// It can quiesce active work.  It manages compiler timeouts.
///
/// This used to be a separate class but in concurrency-land it got messed up
extension Compiler {
    // MARK: Work Starting

    /// Create and start tracking  a compilation request
    func startCompilation(input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
                          outputStyle: CssStyle,
                          sourceMapStyle: SourceMapStyle,
                          includeCharset: Bool,
                          importers: [ImportResolver],
                          stringImporter: ImportResolver? = nil,
                          functions: SassFunctionMap,
                          continuation: Continuation<CompilerResults>) -> OutboundMessage {
        let compilationRequest = CompilationRequest(
            input: input,
            outputStyle: outputStyle,
            sourceMapStyle: sourceMapStyle,
            includeCharset: includeCharset,
            settings: settings,
            importers: settings.globalImporters + importers,
            stringImporter: stringImporter,
            functionsMap: settings.globalFunctions.overridden(with: functions),
            done: makeDone(continuation))

        start(request: compilationRequest)

        return compilationRequest.compileReq
    }

    /// Create and start tracking  version request
    func startVersionRequest(continuation: Continuation<Versions>) -> OutboundMessage {
        let request = VersionRequest(done: makeDone(continuation))
        start(request: request)
        return request.versionReq
    }

    private func makeDone<R>(_ continuation: Continuation<R>) ->
        (any CompilerRequest, Result<R, any Error>) -> Void {
            { req, res in
                Task {
                    if self.activeRequests.removeValue(forKey: req.requestID) != nil {
                        continuation.resume(with: res)
                        self.kickQuiesce()
                    }
                }
            }
    }

    private func start<R: CompilerRequest>(request: R) {
        activeRequests[request.requestID] = request
        let requestDebugPrefix = request.debugPrefix
        request.start(timeoutSeconds: settings.timeout) {
            await self.handleError(ProtocolError("Timeout: \(requestDebugPrefix) timed out after \(self.settings.timeout)s"))
        }
    }

    // MARK: Active work management

    var hasActiveRequests: Bool {
        !activeRequests.isEmpty
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
    nonisolated(unsafe) static var onStuckQuiesce: (() -> Void)? = nil

    /// Nudge the quiesce process.
    private func kickQuiesce() {
        if let quiesceContinuation {
            if activeRequests.isEmpty {
                self.quiesceContinuation = nil
                quiesceContinuation.resume()
            } else {
                debug("Waiting for outstanding requests: \(activeRequests.count)")
                Compiler.onStuckQuiesce?()
            }
        }
    }

    // MARK: Message Dispatch

    /// Handle an inbound message from the Sass compiler.
    func receive(message: InboundMessage, reply: @escaping ReplyFn) throws {
        if let requestID = message.requestID {
            guard let compilation = activeRequests[requestID] else {
                throw ProtocolError("Received message for unknown ReqID=\(requestID): \(message)")
            }
            try compilation.receive(message: message, reply: reply)
        } else {
            try receiveGlobal(message: message)
        }
    }

    /// Global message handler
    /// ie. messages not associated with a compilation ID.
    private func receiveGlobal(message: InboundMessage) throws {
        switch message.sassOutboundMessage.message {
        case .error(let error):
            throw ProtocolError("Sass compiler signalled a protocol error, type=\(error.type), ID=\(error.id): \(error.message)")
        default:
            throw ProtocolError("Sass compiler sent something uninterpretable: \(message)")
        }
    }
}
