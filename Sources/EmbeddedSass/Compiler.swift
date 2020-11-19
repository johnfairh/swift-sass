//
//  Compiler.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import Foundation
@_exported import Sass

/// An instance of the embedded Sass compiler hosted in Swift.
///
/// It runs the compiler as a child process and lets you provide importers and Sass Script routines
/// in your Swift code.
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
/// Xxx importers
/// Xxx SassScript
///
/// To debug problems, start with the output from `Compiler.debugHandler`, all the source files
/// being given to the compiler, and the description of any errors thrown.
public final class Compiler {
    private(set) var child: Exec.Child // internal getter for testing
    private let childRestart: () throws -> Exec.Child

    private enum State {
        /// Nothing happening
        case idle
        /// CompileRequest outstanding, it has initiative
        case active
        /// CompileRequest outstanding, InboundAckedRequest outstanding, user closure active, we have initiative
        case active_callback(String)
        /// Killed them because of error, won't restart
        case idle_broken

        var compileRequestLegal: Bool {
            switch self {
            case .idle, .idle_broken: return true
            case .active, .active_callback(_): return false
            }
        }
    }
    private var state: State

    private let overallTimeout: Int

    // State of the current job
    private var compilationID: UInt32
    private var warnings: [CompilerWarning]

    /// Initialize using the given program as the embedded Sass compiler.
    ///
    /// - parameter embeddedCompilerURL: The file URL to `dart-sass-embedded`
    ///   or something else that speaks the embedded Sass protocol.
    /// - parameter timeoutSeconds: The maximum time allowed  for the embedded
    ///   compiler to compile a stylesheet.  Detects hung compilers.  Default is a minute; set
    ///   -1 to disable timeouts.
    ///
    /// - throws: Something from Foundation if the program does not start.
    public init(embeddedCompilerURL: URL,
                overallTimeoutSeconds: Int = 60) throws {
        precondition(embeddedCompilerURL.isFileURL, "Not a file: \(embeddedCompilerURL)")
        childRestart = { try Exec.spawn(embeddedCompilerURL) }
        child = try childRestart()
        state = .idle
        overallTimeout = overallTimeoutSeconds
        compilationID = 8000
        warnings = []
    }

    private func restart() throws {
        child = try childRestart()
        state = .idle
    }

    /// Initialize using a program found on `PATH` as the embedded Sass compiler.
    ///
    /// - parameter embeddedCompilerName: Name of the program, default `dart-sass-embedded`.
    /// - throws: `ProtocolError()` if the program can't be found.
    ///           Everything from `init(embeddedCompilerURL:)`
    public convenience init(embeddedCompilerName: String = "dart-sass-embedded",
                            overallTimeoutSeconds: Int = 60) throws {
        let results = Exec.run("/usr/bin/env", "which", embeddedCompilerName, stderr: .discard)
        guard let path = results.successString else {
            throw ProtocolError("Can't find `\(embeddedCompilerName)` on PATH.\n\(results.failureReport)")
        }
        try self.init(embeddedCompilerURL: URL(fileURLWithPath: path),
                      overallTimeoutSeconds: overallTimeoutSeconds)
    }

    deinit {
        child.process.terminate()
    }

    /// An optional callback to receive debug log messages from us and the compiler.
    public var debugHandler: DebugHandler?

    private func debug(_ msg: @autoclosure () -> String) {
        debugHandler?(DebugMessage("Host: \(msg())"))
    }

    /// Compile to CSS from a file.
    ///
    /// - parameters:
    ///   - sourceFileURL: The file:// URL to compile.  The file extension is used to guess the
    ///                    syntax of the contents, so it must be css/scss/sass.
    ///   - outputStyle: How to format the produced CSS.
    ///   - createSourceMap: Create a JSON source map for the CSS.
    /// - throws: `SassError.compilerError()` if there is a critical error with the input, for
    ///           example a syntax error.
    ///           `SassError.protocolError()` if something goes wrong with the compiler
    ///           infrastructure itself.
    /// - returns: CSS and optional source map.
    /// - precondition: no call to `compile(...)` outstanding on this instance.
    ///
    /// XXX describe callbacks
    /// XXX importer rules
    public func compile(sourceFileURL: URL,
                        outputStyle: CssStyle = .expanded,
                        createSourceMap: Bool = false) throws -> CompilerResults {
        try compile(input: .path(sourceFileURL.path),
                    outputStyle: outputStyle,
                    createSourceMap: createSourceMap)
    }

    /// Compile to CSS from some text.
    ///
    /// - parameters:
    ///   - sourceText: The document to compile.
    ///   - sourceSyntax: The syntax of `sourceText`.
    ///   - outputStyle: How to format the produced CSS.
    ///   - createSourceMap: Create a JSON source map for the CSS.
    /// - throws: `SassError.compilerError()` if there is a critical error with the input, for
    ///           example a syntax error.
    ///           `SassError.protocolError()` if something goes wrong with the compiler
    ///           infrastructure itself.
    /// - returns: CSS and optional source map.
    /// - precondition: no call to `compile(...)` outstanding on this instance.
    ///
    /// XXX describe callbacks
    /// XXX special importer + rules
    public func compile(sourceText: String,
                        sourceSyntax: Syntax = .scss,
                        outputStyle: CssStyle = .expanded,
                        createSourceMap: Bool = false) throws -> CompilerResults {
        try compile(input: .string(.with { m in
                        m.source = sourceText
                        m.syntax = sourceSyntax.forProtobuf
                    }),
                    outputStyle: outputStyle,
                    createSourceMap: createSourceMap)
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
    public func reinit() throws {
        precondition(state.compileRequestLegal)
        child.process.terminate()
        try restart()
    }

    /// The process ID of the compiler process.
    ///
    /// Not normally needed; can be used to adjust resource usage or maybe send it a signal if stuck.
    public var compilerProcessIdentifier: Int32 {
        child.process.processIdentifier
    }

    /// Helper to generate the compile request message
    private func compile(input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
                         outputStyle: CssStyle,
                         createSourceMap: Bool) throws -> CompilerResults {
        compilationID += 1
        warnings = []

        return try compile(message: .with { wrapper in
            wrapper.message = .compileRequest(.with { msg in
                msg.id = compilationID
                msg.input = input
                msg.style = outputStyle.forProtobuf
                msg.sourceMap = createSourceMap
            })
        })
    }

    /// Top-level compiler protocol runner.  Handles erp, such as there is.

    private func compile(message: Sass_EmbeddedProtocol_InboundMessage) throws -> CompilerResults {
        precondition(state.compileRequestLegal, "Call to `compile(...)` already active")
        if case .idle_broken = state {
            throw ProtocolError("Sass compiler failed to restart after previous errors.")
        }

        let compilationId = message.compileRequest.id

        do {
            state = .active
            debug("Start CompileRequest id=\(compilationId)")
            try child.send(message: message)
            let results = try receiveMessages()
            state = .idle
            debug("End-Success CompileRequest id=\(compilationId)")
            return results
        }
        catch let error as CompilerError {
            state = .idle
            debug("End-CompilerError CompileRequest id=\(compilationId)")
            throw error
        }
        catch {
            // error with some layer of the protocol.
            // the only erp we have to is to try and restart it into a known
            // clean state.  seems ott to retry the command here, see how we go.
            do {
                debug("End-ProtocolError CompileRequest id=\(compilationId), restarting compiler")
                child.process.terminate()
                try restart()
                debug("End-ProtocolError CompileRequest id=\(compilationId), restart OK")
            } catch {
                // the system looks to be broken, sadface
                state = .idle_broken
                debug("End-ProtocolError CompileRequest id=\(compilationId), restart failed (\(error))")
            }
            // Propagate original error
            throw error
        }
    }

    /// Inbound message dispatch, top-level validation
    private func receiveMessages() throws -> CompilerResults {
        let timer = Timer()

        while true {
            let elapsedTime = timer.elapsed
            let timeout = overallTimeout < 0 ? -1 : max(1, overallTimeout - elapsedTime)
            let response = try child.receive(timeout: timeout)

            switch response.message {
            case .compileResponse(let rsp):
                debug("  Got CompileResponse, \(elapsedTime)s")
                return try receive(compileResponse: rsp)

            case .error(let rsp):
                debug("  Got Error, \(elapsedTime)s")
                try receive(error: rsp)

            case .logEvent(let rsp):
                debug("  Got Log, \(elapsedTime)")
                try receive(log: rsp)

            default:
                throw ProtocolError("Unexpected response: \(response)")
            }
        }
    }

    /// Inbound `CompileResponse` handler
    private func receive(compileResponse: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse) throws -> CompilerResults {
        guard compileResponse.id == compilationID else {
            throw ProtocolError("Bad compilation ID, expected \(compilationID) got \(compileResponse.id)")
        }
        switch compileResponse.result {
        case .success(let s):
            return .init(s, warnings: warnings)
        case .failure(let f):
            throw CompilerError(f, warnings: warnings)
        case nil:
            throw ProtocolError("Malformed CompileResponse, missing `result`: \(compileResponse)")
        }
    }

    /// Inbound `Error` handler
    private func receive(error: Sass_EmbeddedProtocol_ProtocolError) throws {
        throw ProtocolError("Sass compiler signalled a protocol error, type=\(error.type), id=\(error.id): \(error.message)")
    }

    /// Inbound `Log` handler
    private func receive(log: Sass_EmbeddedProtocol_OutboundMessage.LogEvent) throws {
        guard log.compilationID == compilationID else {
            throw ProtocolError("Bad compilation ID, expected \(compilationID) got \(log.compilationID)")
        }
        switch log.type {
        case .debug:
            debug(log.message)
        case .warning, .deprecationWarning:
            warnings.append(.init(log))
        case .UNRECOGNIZED(let value):
            throw ProtocolError("Unrecognized warning type \(value) from compiler: \(log.message)")
        }
    }
}

// MARK: Protobuf <-> Public type conversions

extension Syntax {
    var forProtobuf: Sass_EmbeddedProtocol_InboundMessage.Syntax {
        switch self {
        case .css: return .css
        case .indented, .sass: return .indented
        case .scss: return .scss
        }
    }
}

extension CssStyle {
    var forProtobuf: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OutputStyle {
        switch self {
        case .compact: return .compact
        case .compressed: return .compressed
        case .expanded: return .expanded
        case .nested: return .nested
        }
    }
}

extension Span {
    init(_ protobuf: Sass_EmbeddedProtocol_SourceSpan) {
        self = Self(text: protobuf.text.nonEmptyString,
                    url: protobuf.url.nonEmptyString,
                    start: Location(protobuf.start),
                    end: protobuf.hasEnd ? Location(protobuf.end) : nil,
                    context: protobuf.context.nonEmptyString)
    }
}

extension Span.Location {
    init(_ protobuf: Sass_EmbeddedProtocol_SourceSpan.SourceLocation) {
        self = Self(offset: Int(protobuf.offset),
                    line: Int(protobuf.line),
                    column: Int(protobuf.column))
    }
}

extension CompilerResults {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse.CompileSuccess,
         warnings: [CompilerWarning]) {
        self = Self(css: protobuf.css,
                    sourceMap: protobuf.sourceMap.nonEmptyString,
                    warnings: warnings)
    }
}

extension CompilerError {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse.CompileFailure,
         warnings: [CompilerWarning]) {
        self = Self(message: protobuf.message,
                    span: protobuf.hasSpan ? .init(protobuf.span) : nil,
                    stackTrace: protobuf.stackTrace.nonEmptyString,
                    warnings: warnings)
    }
}

extension CompilerWarning.Kind {
    init(_ type: Sass_EmbeddedProtocol_OutboundMessage.LogEvent.TypeEnum) {
        switch type {
        case .deprecationWarning: self = .deprecation
        case .warning: self = .warning
        default: preconditionFailure() // handled at callsite
        }
    }
}

extension CompilerWarning {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.LogEvent) {
        self = Self(kind: Kind(protobuf.type),
                    message: protobuf.message,
                    span: protobuf.hasSpan ? .init(protobuf.span) : nil,
                    stackTrace: protobuf.stackTrace.nonEmptyString)
    }
}

private extension String {
    var nonEmptyString: String? {
        isEmpty ? nil : self
    }
}
