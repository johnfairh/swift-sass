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

    // Configuration
    private let overallTimeout: Int
    private let globalImporters: [ImportResolver]
    private let globalFunctions: SassFunctionMap

    // State of the current job
    private var compilationID: UInt32
    private var messages: [CompilerMessage]
    private var currentImporters: [ImportResolver]
    private var currentFunctions: SassFunctionMap

    /// Initialize using the given program as the embedded Sass compiler.
    ///
    /// - parameter embeddedCompilerURL: The file URL to `dart-sass-embedded`
    ///   or something else that speaks the embedded Sass protocol.
    /// - parameter overallTimeoutSeconds: The maximum time allowed  for the embedded
    ///   compiler to compile a stylesheet.  Detects hung compilers.  Default is a minute; set
    ///   -1 to disable timeouts.
    /// - parameter importers: Rules for resolving `@import` that cannot be satisfied relative to
    ///   the source file's URL, used for all compile requests made of this instance.
    /// - parameter functions: Custom SassScript functions available to all compile requests made
    ///   of this instance.
    ///
    /// - throws: Something from Foundation if the program does not start.
    public init(embeddedCompilerURL: URL,
                overallTimeoutSeconds: Int = 60,
                importers: [ImportResolver] = [],
                functions: SassFunctionMap = [:]) throws {
        precondition(embeddedCompilerURL.isFileURL, "Not a file: \(embeddedCompilerURL)")
        childRestart = { try Exec.spawn(embeddedCompilerURL) }
        child = try childRestart()
        state = .idle
        overallTimeout = overallTimeoutSeconds
        globalImporters = importers
        globalFunctions = functions
        compilationID = 1000
        messages = []
        currentImporters = []
        currentFunctions = [:]
    }

    private func restart() throws {
        child = try childRestart()
        state = .idle
    }

    /// Initialize using a program found on `PATH` as the embedded Sass compiler.
    ///
    /// - parameter embeddedCompilerName: Name of the program, default `dart-sass-embedded`.
    /// - parameter timeoutSeconds: The maximum time allowed  for the embedded
    ///   compiler to compile a stylesheet.  Detects hung compilers.  Default is a minute; set
    ///   -1 to disable timeouts.
    /// - parameter importers: Rules for resolving `@import` that cannot be satisfied relative to
    ///   the source file's URL, used for all compile requests to this instance.
    /// - parameter functions: Custom SassScript functions available to all compile requests made
    ///   of this instance.
    ///
    /// - throws: `ProtocolError()` if the program can't be found.
    ///           Everything from `init(embeddedCompilerURL:)`
    public convenience init(embeddedCompilerName: String = "dart-sass-embedded",
                            overallTimeoutSeconds: Int = 60,
                            importers: [ImportResolver] = [],
                            functions: SassFunctionMap = [:]) throws {
        let results = Exec.run("/usr/bin/env", "which", embeddedCompilerName, stderr: .discard)
        guard let path = results.successString else {
            throw ProtocolError("Can't find `\(embeddedCompilerName)` on PATH.\n\(results.failureReport)")
        }
        try self.init(embeddedCompilerURL: URL(fileURLWithPath: path),
                      overallTimeoutSeconds: overallTimeoutSeconds,
                      importers: importers,
                      functions: functions)
    }

    deinit {
        child.process.terminate()
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

    /// An optional callback to receive debug log messages from us and the compiler.
    public var debugHandler: DebugHandler?

    private func debug(_ msg: @autoclosure () -> String) {
        debugHandler?(DebugMessage("[compid=\(compilationID)] \(msg())"))
    }

    /// Compile to CSS from a file.
    ///
    /// - parameters:
    ///   - fileURL: The `file:` URL to compile.  The file extension determines the
    ///     expected syntax of the contents, so it must be css/scss/sass.
    ///   - outputStyle: How to format the produced CSS.
    ///   - createSourceMap: Create a JSON source map for the CSS.
    ///   - importers: Rules for resolving `@import` etc. for this compilation, used in order after
    ///     `sourceFileURL`'s directory and any set at the `Compiler` level.
    ///   - functions: Custom functions for this compilation, overriding any with the same name set
    ///     at the `Compiler` level.
    /// - throws: `CompilerError()` if there is a critical error with the input, for example a syntax error.
    ///           `ProtocolError()` if something goes wrong with the compiler infrastructure itself.
    /// - returns: CSS and optional source map.
    /// - precondition: no call to `compile(...)` outstanding on this instance.
    public func compile(fileURL: URL,
                        outputStyle: CssStyle = .expanded,
                        createSourceMap: Bool = false,
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        try compile(input: .path(fileURL.path),
                    outputStyle: outputStyle,
                    createSourceMap: createSourceMap,
                    importers: importers,
                    functions: functions)
    }

    /// Compile to CSS from some text.
    ///
    /// - parameters:
    ///   - text: The document to compile.
    ///   - syntax: The syntax of `text`.
    ///   - url: Optionally, the absolute URL whence came `text`.
    ///   - outputStyle: How to format the produced CSS.
    ///   - createSourceMap: Create a JSON source map for the CSS.
    ///   - importers: Rules for resolving `@import` etc. for this compilation, used in order after
    ///     `sourceFileURL`'s directory and any set at the `Compiler` level.
    ///   - functions: Custom functions for this compilation, overriding any with the same name set
    ///     at the `Compiler` level.
    /// - throws: `CompilerError()` if there is a critical error with the input, for example a syntax error.
    ///           `ProtocolError()` if something goes wrong with the compiler infrastructure itself.
    /// - returns: CSS and optional source map.
    /// - precondition: no call to `compile(...)` outstanding on this instance.
    /// - todo: Mebbe ought to have a special importer to go with `url` but compiler doesn't implement
    ///         it so ....
    public func compile(text: String,
                        syntax: Syntax = .scss,
                        url: URL? = nil,
                        outputStyle: CssStyle = .expanded,
                        createSourceMap: Bool = false,
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        try compile(input: .string(.with { m in
                        m.source = text
                        m.syntax = .init(syntax)
                        url.flatMap { m.url = $0.absoluteString }
                    }),
                    outputStyle: outputStyle,
                    createSourceMap: createSourceMap,
                    importers: importers,
                    functions: functions)
    }

    /// Helper to generate the compile request message
    private func compile(input: Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OneOf_Input,
                         outputStyle: CssStyle,
                         createSourceMap: Bool,
                         importers: [ImportResolver],
                         functions: SassFunctionMap) throws -> CompilerResults {
        compilationID += 1
        messages = []
        currentImporters = globalImporters + importers

        // Discard any signatures in global with names matching local.
        // Pass the resulting signatures to the compiler.
        // Retain a map from function name (not signature) to callback.
        let localFnsNameMap = functions.asSassFunctionNameElementMap
        let globalFnsNameMap = globalFunctions.asSassFunctionNameElementMap
        let mergedFnsNameMap = globalFnsNameMap.merging(localFnsNameMap) { g, l in l }
        let signatures = mergedFnsNameMap.values.map { $0.0 }
        currentFunctions = mergedFnsNameMap.mapValues { $0.value }

        return try compile(message: .with {
            $0.message = .compileRequest(.with { msg in
                msg.id = compilationID
                msg.input = input
                msg.style = .init(outputStyle)
                msg.sourceMap = createSourceMap
                msg.importers = .init(currentImporters, startingID: Self.baseImporterID)
                msg.globalFunctions = signatures
            })
        })
    }

    /// Top-level compiler protocol runner.  Handles erp, such as there is.

    private func compile(message: Sass_EmbeddedProtocol_InboundMessage) throws -> CompilerResults {
        precondition(state.compileRequestLegal, "Call to `compile(...)` already active")
        if case .idle_broken = state {
            throw ProtocolError("Sass compiler failed to restart after previous errors.")
        }

        do {
            state = .active
            debug("start")
            try child.send(message: message)
            let results = try receiveMessages()
            state = .idle
            debug("end-success")
            return results
        }
        catch let error as CompilerError {
            state = .idle
            debug("end-compiler-error")
            throw error
        }
        catch {
            // error with some layer of the protocol.
            // the only erp we have to is to try and restart it into a known
            // clean state.  seems ott to retry the command here, see how we go.
            do {
                debug("end-protocol-error - restarting compiler...")
                child.process.terminate()
                try restart()
                debug("end-protocol-error - restart ok")
            } catch {
                // the system looks to be broken, sadface
                state = .idle_broken
                debug("end-protocol-error - restart failed: \(error)")
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
            debug("  rx \(response.logMessage)")
            if let rspCompilationID = response.compilationID,
               rspCompilationID != compilationID {
                throw ProtocolError("Bad compilation ID, expected \(compilationID) got \(rspCompilationID)")
            }

            switch response.message {
            case .compileResponse(let rsp):
                return try receive(compileResponse: rsp)

            case .error(let rsp):
                try receive(error: rsp)

            case .logEvent(let rsp):
                try receive(log: rsp)

            case .canonicalizeRequest(let req):
                try receive(canonicalizeRequest: req)

            case .importRequest(let req):
                try receive(importRequest: req)

            case .functionCallRequest(let req):
                try receive(functionCallRequest: req)

            default:
                throw ProtocolError("Unexpected response: \(response)")
            }
        }
    }

    /// Inbound `CompileResponse` handler
    private func receive(compileResponse: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse) throws -> CompilerResults {
        switch compileResponse.result {
        case .success(let s):
            return .init(s, messages: messages)
        case .failure(let f):
            throw CompilerError(f, messages: messages)
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
        switch log.type {
        case .warning, .deprecationWarning, .debug:
            messages.append(.init(log))
        case .UNRECOGNIZED(let value):
            throw ProtocolError("Unrecognized warning type \(value) from compiler: \(log.message)")
        }
    }

    // MARK: Importers

    static let baseImporterID = UInt32(4000)

    /// Helper
    private func getCustomImporter(importerID: UInt32) throws -> CustomImporter {
        let minImporterID = Self.baseImporterID
        let maxImporterID = minImporterID + UInt32(currentImporters.count) - 1
        guard importerID >= minImporterID, importerID <= maxImporterID else {
            throw ProtocolError("Bad importer ID \(importerID), out of range (\(minImporterID)-\(maxImporterID))")
        }
        guard let customImporter = currentImporters[Int(importerID - minImporterID)].customImporter else {
            throw ProtocolError("Bad importer ID \(importerID), not a custom importer")
        }
        return customImporter
    }

    /// Inbound `CanonicalizeRequest` handler
    private func receive(canonicalizeRequest req: Sass_EmbeddedProtocol_OutboundMessage.CanonicalizeRequest) throws {
        let importer = try getCustomImporter(importerID: req.importerID)
        var rsp = Sass_EmbeddedProtocol_InboundMessage.CanonicalizeResponse()
        rsp.id = req.id
        do {
            if let canonicalURL = try importer.canonicalize(importURL: req.url) {
                rsp.url = canonicalURL.absoluteString
                debug("  tx canon-rsp-success reqid=\(req.id)")
            } else {
                // leave result nil -> can't deal with this request
                debug("  tx canon-rsp-nil reqid=\(req.id)")
            }
        } catch {
            rsp.error = String(describing: error)
            debug("  tx canon-rsp-error reqid=\(req.id)")
        }
        try child.send(message: .with { $0.message = .canonicalizeResponse(rsp) })
    }

    /// Inbound `ImportRequest` handler
    private func receive(importRequest req: Sass_EmbeddedProtocol_OutboundMessage.ImportRequest) throws {
        let importer = try getCustomImporter(importerID: req.importerID)
        guard let url = URL(string: req.url) else {
            throw ProtocolError("Malformed import URL \(req.url)")
        }
        var rsp = Sass_EmbeddedProtocol_InboundMessage.ImportResponse()
        rsp.id = req.id
        do {
            let results = try importer.load(canonicalURL: url)
            rsp.success = .with { msg in
                msg.contents = results.contents
                msg.syntax = .init(results.syntax)
                results.sourceMapURL.flatMap { msg.sourceMapURL = $0.absoluteString }
            }
            debug("  tx import-rsp-success reqid=\(req.id)")
        } catch {
            rsp.error = String(describing: error)
            debug("  tx import-rsp-error reqid=\(req.id)")
        }
        try child.send(message: .with { $0.message = .importResponse(rsp) })
    }

    // MARK: Functions

    /// Inbound 'FunctionCallRequest' handler
    private func receive(functionCallRequest req: Sass_EmbeddedProtocol_OutboundMessage.FunctionCallRequest) throws {
        switch req.identifier {
        case .functionID(_):
            throw ProtocolError("FunctionCallRequest-by-ID not supported")
        case .name(let name):
            guard let customFunc = currentFunctions[name] else {
                throw ProtocolError("Host function \(name) not registered.")
            }
            var rsp = Sass_EmbeddedProtocol_InboundMessage.FunctionCallResponse()
            rsp.id = req.id
            do {
                let resultValue = try customFunc(req.arguments.map { try $0.asSassValue() })
                rsp.success = .init(resultValue)
                debug("  tx fncall-rsp-success reqid=\(req.id)")
            } catch {
                rsp.error = String(describing: error)
                debug("  tx fncall-rsp-error reqid=\(req.id)")
            }
            try child.send(message: .with { $0.message = .functionCallResponse(rsp) })
        case nil:
            throw ProtocolError("Missing 'identifier' field in FunctionCallRequest")
        }
    }
}

private extension ImportResolver {
    var customImporter: CustomImporter? {
        switch self {
        case .loadPath(_): return nil
        case .custom(let c): return c
        }
    }
}
