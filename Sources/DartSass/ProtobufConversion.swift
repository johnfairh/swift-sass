//
//  ProtobufConversion.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Helpers to shuffle data in and out of the protobuf types.

import struct Foundation.URL
import Sass

// MARK: PB -> Native

extension String {
    var nonEmptyString: String? {
        isEmpty ? nil : self
    }
}

extension Span {
    init(_ protobuf: Sass_EmbeddedProtocol_SourceSpan) {
        self = .init(text: protobuf.text.nonEmptyString,
                     url: protobuf.url.nonEmptyString.flatMap { URL(string: $0) },
                     start: Location(protobuf.start),
                     end: protobuf.hasEnd ? Location(protobuf.end) : nil,
                     context: protobuf.context.nonEmptyString)
    }
}

extension Span.Location {
    init(_ protobuf: Sass_EmbeddedProtocol_SourceSpan.SourceLocation) {
        self = .init(offset: Int(protobuf.offset),
                     line: Int(protobuf.line + 1),
                     column: Int(protobuf.column + 1))
    }
}

extension CompilerResults {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse.CompileSuccess,
         messages: [CompilerMessage],
         loadedURLs: [URL]) {
        self = .init(css: protobuf.css,
                     sourceMap: protobuf.sourceMap.nonEmptyString,
                     messages: messages,
                     loadedURLs: loadedURLs)
    }
}

extension CompilerError {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse.CompileFailure,
         messages: [CompilerMessage],
         loadedURLs: [URL]) {
        self = .init(message: protobuf.message,
                     span: protobuf.hasSpan ? .init(protobuf.span) : nil,
                     stackTrace: protobuf.stackTrace.nonEmptyString,
                     messages: messages,
                     loadedURLs: loadedURLs,
                     description: protobuf.formatted.nonEmptyString ?? protobuf.message)
    }
}

extension CompilerMessage.Kind {
    init(_ type: Sass_EmbeddedProtocol_LogEventType) throws {
        switch type {
        case .deprecationWarning: self = .deprecation
        case .warning: self = .warning
        case .debug: self = .debug
        case .UNRECOGNIZED(let i):
            throw ProtocolError("Unrecognized warning type \(i) from compiler")
        }
    }
}

extension CompilerMessage {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.LogEvent) throws {
        self = .init(kind: try Kind(protobuf.type),
                     message: protobuf.message,
                     span: protobuf.hasSpan ? .init(protobuf.span) : nil,
                     stackTrace: protobuf.stackTrace.nonEmptyString,
                     description: protobuf.formatted)
    }
}

extension Versions {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.VersionResponse) {
        protocolVersionString = protobuf.protocolVersion
        packageVersionString = protobuf.compilerVersion
        compilerVersionString = protobuf.implementationVersion
        compilerName = protobuf.implementationName
    }
}

extension CompilerMessageStyle {
    var isColored: Bool {
        switch self {
        case .plain: return false
        case .terminalColored: return true
        }
    }
}

extension CompilerWarningLevel {
    var isSilent: Bool {
        self == .none
    }

    var suppressDependencyWarnings: Bool {
        self != .all
    }
}

// MARK: Native -> PB

extension Sass_EmbeddedProtocol_Syntax {
    init(_ syntax: Syntax) {
        switch syntax {
        case .css: self = .css
        case .indented, .sass: self = .indented
        case .scss: self = .scss
        }
    }
}

extension Sass_EmbeddedProtocol_OutputStyle {
    init(_ style: CssStyle) {
        switch style {
        case .compressed: self = .compressed
        case .expanded: self = .expanded
        case .nested, .compact: self = .expanded
        }
    }
}

extension Sass_EmbeddedProtocol_InboundMessage.CompileRequest.Importer {
    init(_ importer: ImportResolver, id: UInt32) {
        self.init()
        switch importer {
        case .loadPath(let url):
            precondition(url.isFileURL)
            path = url.path
        case .importer(let i):
            importerID = id
            nonCanonicalScheme = i.noncanonicalURLSchemes
        case .filesystemImporter:
            fileImporterID = id
        case .nodePackageImporter(let url):
            precondition(url.isFileURL)
            nodePackageImporter = .with { $0.entryPointDirectory = url.path }
        }
    }
}

extension Array where Element == Sass_EmbeddedProtocol_InboundMessage.CompileRequest.Importer {
    init(_ importers: [ImportResolver], startingID: UInt32) {
        self = importers.enumerated().map {
            .init($0.1, id: UInt32($0.0) + startingID)
        }
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.VersionResponse {
    init(_ versions: Versions, id: UInt32) {
        self.id = id
        protocolVersion = versions.protocolVersionString
        compilerVersion = versions.packageVersionString
        implementationVersion = versions.compilerVersionString
        implementationName = versions.compilerName
    }
}

extension SourceMapStyle {
    var createSourceMap: Bool {
        self != .none
    }

    var embedSourceMap: Bool {
        self == .embeddedSources
    }
}

// MARK: Inbound message polymorphism

extension InboundMessage {
    var requestID: UInt32? {
        switch sassOutboundMessage.message {
        case .error, nil:
            return nil
        case .compileResponse, .canonicalizeRequest, .importRequest, .fileImportRequest, .functionCallRequest, .logEvent:
            return compilationID
        case .versionResponse(let m):
            return m.id
        }
    }

    var logMessage: String {
        let compID = "CompID=\(compilationID)"
        return sassOutboundMessage.message?.logMessage(compID: compID) ?? "\(compID) missing message"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.OneOf_Message {
    func logMessage(compID: String) -> String {
        switch self {
        case .canonicalizeRequest(let m): return m.logMessage(compID: compID)
        case .compileResponse(let m): return m.logMessage(compID: compID)
        case .error(let m): return m.logMessage(compID: compID)
        case .fileImportRequest(let m): return m.logMessage(compID: compID)
        case .functionCallRequest(let m): return m.logMessage(compID: compID)
        case .importRequest(let m): return m.logMessage(compID: compID)
        case .logEvent(let m): return m.logMessage(compID: compID)
        case .versionResponse(let m): return m.logMessage(compID: compID)
        }
    }
}

extension Sass_EmbeddedProtocol_ProtocolError {
    func logMessage(compID: String) -> String {
        "Protocol-Error \(compID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.CompileResponse {
    func logMessage(compID: String) -> String {
        "Compile-Rsp \(compID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.LogEvent {
    func logMessage(compID: String) -> String {
        "LogEvent \(compID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.CanonicalizeRequest {
    func logMessage(compID: String) -> String {
        "Canon-Req \(compID) ReqID=\(id) ImpID=\(importerID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.ImportRequest {
    func logMessage(compID: String) -> String {
        "Import-Req \(compID) ReqID=\(id) ImpID=\(importerID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.FileImportRequest {
    func logMessage(compID: String) -> String {
        "FileImport-Req \(compID) ReqID=\(id) ImpID=\(importerID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.FunctionCallRequest {
    func logMessage(compID: String) -> String {
        "FnCall-Req \(compID) ReqID=\(id) FnID=\(identifier?.logMessage ?? "[nil]")"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.FunctionCallRequest.OneOf_Identifier {
    var logMessage: String {
        switch self {
        case .functionID(let id): return String(id)
        case .name(let name): return name
        }
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.VersionResponse {
    func logMessage(compID: String) -> String {
        "Version-Rsp VerID=\(id) Proto=\(protocolVersion) Pkg=\(compilerVersion) Compiler=\(implementationVersion) Name=\(implementationName)"
    }
}
