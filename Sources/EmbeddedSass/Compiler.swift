//
//  Compiler.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

import Foundation

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

    private var compilationID: UInt32

    /// Initialize using the given program as the embedded Sass compiler.
    ///
    /// - parameter embeddedCompilerURL: The file URL to `dart-sass-embedded`
    ///   or something else that speaks the embedded Sass protocol.
    /// - throws: Something from Foundation if the program does not start.
    ///
    /// Blocks while the compiler starts up.
    public init(embeddedCompilerURL: URL) throws {
        childRestart = { try Exec.spawn(embeddedCompilerURL) }
        child = try childRestart()
        state = .idle
        compilationID = 8000
    }

    private func restart() throws {
        child = try childRestart()
    }

    /// Initialize using a program found on `PATH` as the embedded Sass compiler.
    ///
    /// - parameter embeddedCompilerName: Name of the program, default `dart-sass-embedded`.
    /// - throws: `ProtocolError()` if the program can't be found.
    ///           Everything from `init(embeddedCompilerURL:)`
    ///
    /// Blocks while the compiler starts up.
    public convenience init(embeddedCompilerName: String = "dart-sass-embedded") throws {
        let results = Exec.run("/usr/bin/env", "which", embeddedCompilerName, stderr: .discard)
        guard let path = results.successString else {
            throw ProtocolError("Can't find `\(embeddedCompilerName)` on PATH.\n\(results.failureReport)")
        }
        try self.init(embeddedCompilerURL: URL(fileURLWithPath: path))
    }

    deinit {
        child.process.terminate()
    }

    /// An optional callback to receive warning messages from the compiler.
    public var warningHandler: Sass.WarningHandler?

    /// An optional callback to receive debug log messages from us and the compiler.
    public var debugHandler: Sass.DebugHandler?

    private func debug(_ msg: @autoclosure () -> String) {
        debugHandler?(.init(message: "Host: \(msg())", span: nil))
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
                        outputStyle: Sass.OutputStyle = .expanded,
                        createSourceMap: Bool = false) throws -> Sass.Results {
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
                        sourceSyntax: Sass.InputSyntax = .scss,
                        outputStyle: Sass.OutputStyle = .expanded,
                        createSourceMap: Bool = false) throws -> Sass.Results {
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
    /// Don't use this to unstick a stuck `compile(...)` call, that will terminate eventually
    /// unless I haven't written the timeout logic yet, in which case you can try poking the `compilerPid`.
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
                         outputStyle: Sass.OutputStyle,
                         createSourceMap: Bool) throws -> Sass.Results {
        compilationID += 1
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
    private func compile(message: Sass_EmbeddedProtocol_InboundMessage) throws -> Sass.Results {
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
        catch let error as Sass.CompilerError {
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
                state = .idle
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
    private func receiveMessages() throws -> Sass.Results {
        while true {
            let response = try child.receive()
            switch response.message {
            case .compileResponse(let rsp):
                debug("  Got CompileResponse")
                return try receive(compileResponse: rsp)

            case .error(let rsp):
                debug("  Got Error")
                try receive(error: rsp)

            default:
                throw ProtocolError("Unexpected response: \(response)")
            }
        }
    }

    /// Inbound `CompileResponse` handler
    private func receive(compileResponse: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse) throws -> Sass.Results {
        if compileResponse.id != compilationID {
            throw ProtocolError("Bad compilation ID, expected \(compilationID) got \(compileResponse.id)")
        }
        switch compileResponse.result {
        case .success(let s):
            return .init(s)
        case .failure(let f):
            throw Sass.CompilerError(f)
        case nil:
            throw ProtocolError("Malformed CompileResponse, missing `result`: \(compileResponse)")
        }
    }

    /// Inbound `Error` handler
    private func receive(error: Sass_EmbeddedProtocol_ProtocolError) throws {
        throw ProtocolError("Sass compiler signalled a protocol error, type=\(error.type), id=\(error.id): \(error.message)")
    }
}

// MARK: Protobuf <-> Public type conversions

extension Sass.InputSyntax {
    var forProtobuf: Sass_EmbeddedProtocol_InboundMessage.Syntax {
        switch self {
        case .css: return .css
        case .indented, .sass: return .indented
        case .scss: return .scss
        }
    }
}

extension Sass.OutputStyle {
    var forProtobuf: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OutputStyle {
        switch self {
        case .compact: return .compact
        case .compressed: return .compressed
        case .expanded: return .expanded
        case .nested: return .nested
        }
    }
}

extension Sass.SourceSpan {
    init(_ protobuf: Sass_EmbeddedProtocol_SourceSpan) {
        text = protobuf.text.nonEmptyString
        url = protobuf.url.nonEmptyString
        start = Location(protobuf.start)
        end = protobuf.hasEnd ? Location(protobuf.end) : nil
        context = protobuf.context.nonEmptyString
    }
}

extension Sass.SourceSpan.Location {
    init(_ protobuf: Sass_EmbeddedProtocol_SourceSpan.SourceLocation) {
        offset = Int(protobuf.offset)
        line = Int(protobuf.line)
        column = Int(protobuf.column)
    }
}

extension Sass.Results {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse.CompileSuccess) {
        css = protobuf.css
        sourceMap = protobuf.sourceMap.nonEmptyString
    }
}
extension Sass.CompilerError {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse.CompileFailure) {
        message = protobuf.message
        span = protobuf.hasSpan ? .init(protobuf.span) : nil
        stackTrace = protobuf.stackTrace.nonEmptyString
    }
}

private extension String {
    var nonEmptyString: String? {
        isEmpty ? nil : self
    }
}
