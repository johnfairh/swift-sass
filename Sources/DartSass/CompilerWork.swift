//
//  CompilerWork.swift
//  DartSass
//
//  Copyright 2020-2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIO
import Sass
import struct Foundation.URL

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
    /// Message formatting style, for all compilations
    private let messageStyle: CompilerMessageStyle
    /// Configured global importer rules, for all compilations
    private let globalImporters: [ImportResolver]
    /// Configured functions, for all compilations
    private let globalFunctions: SassAsyncFunctionMap

    /// Unstarted compilation work
    private var pendingCompilations: [CompilationRequest]
    /// Active compilation work indexed by CompilationID
    private var activeRequests: [UInt32 : CompilerRequest]
    /// Promise tracking active work quiesce
    private var quiescePromise: EventLoopPromise<Void>?

    init(eventLoop: EventLoop,
         resetRequest: @escaping (Error) -> Void,
         timeout: Int,
         messageStyle: CompilerMessageStyle,
         importers: [ImportResolver],
         functions: SassAsyncFunctionMap) {
        self.eventLoop = eventLoop
        self.resetRequest = resetRequest
        self.timeout = timeout
        self.messageStyle = messageStyle
        globalImporters = importers
        globalFunctions = functions
        pendingCompilations = []
        activeRequests = [:]
        quiescePromise = nil
    }

    deinit {
        precondition(pendingCompilations.isEmpty)
        precondition(!hasActiveRequests)
    }

    var hasActiveRequests: Bool {
        !activeRequests.isEmpty
    }

    /// Add a new compilation request to the pending queue.
    /// Return the future for the job.
    func addPendingCompilation(input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
                               outputStyle: CssStyle,
                               sourceMapStyle: SourceMapStyle,
                               importers: [ImportResolver],
                               stringImporter: ImportResolver? = nil,
                               functions: SassAsyncFunctionMap) -> EventLoopFuture<CompilerResults> {
        eventLoop.preconditionInEventLoop()

        // Figure out functions - semantic name does not include params so merge global
        // and per-job based on name alone, then pass the whole lot to the job.
        let localFnsNameMap = functions._asSassFunctionNameElementMap
        let globalFnsNameMap = globalFunctions._asSassFunctionNameElementMap
        let mergedFnsNameMap = globalFnsNameMap.merging(localFnsNameMap) { g, l in l }

        let promise = eventLoop.makePromise(of: CompilerResults.self)

        let compilation = CompilationRequest(
            promise: promise,
            input: input,
            outputStyle: outputStyle,
            sourceMapStyle: sourceMapStyle,
            messageStyle: messageStyle,
            importers: globalImporters + importers,
            stringImporter: stringImporter,
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
        pendingCompilations.forEach { self.start(request: $0) }
        defer { pendingCompilations = [] }
        return pendingCompilations.map { job in .with { $0.compileRequest = job.compileReq } }
    }

    private func start<R: TypedCompilerRequest>(request: R) {
        activeRequests[request.requestID] = request
        request.start(timeout: timeout)?.whenSuccess { [self] in
            resetRequest(
                ProtocolError("Timeout: \(request.debugPrefix) timed out after \(timeout)s"))
        }
        request.futureResult.whenComplete { result in
            self.activeRequests[request.requestID] = nil
            self.kickQuiesce()
        }
    }

    /// Start a version request.  Bypass any pending queue.
    func startVersionRequest() -> (EventLoopFuture<Versions>, Sass_EmbeddedProtocol_InboundMessage) {
        eventLoop.preconditionInEventLoop()
        let promise = eventLoop.makePromise(of: Versions.self)
        let request = VersionRequest(promise: promise)
        start(request: request)
        return (promise.futureResult, .with { $0.versionRequest = request.versionReq })
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

    /// Nudge the quiesce process.
    private func kickQuiesce() {
        if let quiescePromise = quiescePromise {
            if activeRequests.isEmpty {
                self.quiescePromise = nil
                quiescePromise.succeed(())
            } else {
                Compiler.logger.debug("Waiting for outstanding requests: \(activeRequests.count)")
            }
        }
    }

    /// Handle an inbound message from the Sass compiler.
    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) -> EventLoopFuture<Sass_EmbeddedProtocol_InboundMessage?> {
        if let requestID = message.requestID {
            guard let compilation = activeRequests[requestID] else {
                return eventLoop.makeProtocolError("Received message for unknown ReqID=\(requestID): \(message)")
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
