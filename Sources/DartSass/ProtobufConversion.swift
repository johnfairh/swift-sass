//
//  ProtobufConversion.swift
//  DartSass
//
//  Copyright 2020-2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Helpers to shuffle data in and out of the protobuf types.

import struct Foundation.URL
import Sass
import NIO

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
         messages: [CompilerMessage]) {
        self = .init(css: protobuf.css,
                     sourceMap: protobuf.sourceMap.nonEmptyString,
                     messages: messages,
                     loadedURLs: protobuf.loadedUrls.compactMap { URL(string: $0) })
    }
}

extension CompilerError {
    init(_ protobuf: Sass_EmbeddedProtocol_OutboundMessage.CompileResponse.CompileFailure,
         messages: [CompilerMessage]) {
        self = .init(message: protobuf.message,
                     span: protobuf.hasSpan ? .init(protobuf.span) : nil,
                     stackTrace: protobuf.stackTrace.nonEmptyString,
                     messages: messages,
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
        case .importer:
            importerID = id
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

extension Bool {
    init(_ sourceMapStyle: SourceMapStyle) {
        switch sourceMapStyle {
        case .none: self = false
        case .embeddedSources, .separateSources: self = true
        }
    }
}

// MARK: Inbound message polymorphism

extension Sass_EmbeddedProtocol_OutboundMessage {
    var logMessage: String {
        message?.logMessage ?? "unknown-1"
    }

    var requestID: UInt32? {
        message?.requestID
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.OneOf_Message {
    var logMessage: String {
        switch self {
        case .canonicalizeRequest(let m): return m.logMessage
        case .compileResponse(let m): return m.logMessage
        case .error(let m): return m.logMessage
        case .fileImportRequest(let m): return m.logMessage
        case .functionCallRequest(let m): return m.logMessage
        case .importRequest(let m): return m.logMessage
        case .logEvent(let m): return m.logMessage
        case .versionResponse(let m): return m.logMessage
        }
    }

    var requestID: UInt32? {
        switch self {
        case .canonicalizeRequest(let m): return m.compilationID
        case .compileResponse(let m): return m.id
        case .error: return nil
        case .fileImportRequest(let m): return m.compilationID
        case .functionCallRequest(let m): return m.compilationID
        case .importRequest(let m): return m.compilationID
        case .logEvent(let m): return m.compilationID
        case .versionResponse(let m): return m.id
        }
    }
}

extension Sass_EmbeddedProtocol_ProtocolError {
    var logMessage: String {
        "Protocol-Error CompID=\(id)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.CompileResponse {
    var logMessage: String {
        "Compile-Rsp CompID=\(id)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.LogEvent {
    var logMessage: String {
        "LogEvent CompID=\(compilationID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.CanonicalizeRequest {
    var logMessage: String {
        "Canon-Req CompID=\(compilationID) ReqID=\(id) ImpID=\(importerID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.ImportRequest {
    var logMessage: String {
        "Import-Req CompID=\(compilationID) ReqID=\(id) ImpID=\(importerID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.FileImportRequest {
    var logMessage: String {
        "FileImport-Req CompID=\(compilationID) ReqID=\(id) ImpID=\(importerID)"
    }
}

extension Sass_EmbeddedProtocol_OutboundMessage.FunctionCallRequest {
    var logMessage: String {
        "FnCall-Req CompID=\(compilationID) ReqID=\(id) FnID=\(identifier?.logMessage ?? "[nil]")"
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
    var logMessage: String {
        "Version-Rsp VerID=\(id) Proto=\(protocolVersion) Pkg=\(compilerVersion) Compiler=\(implementationVersion) Name=\(implementationName)"
    }
}

// MARK: SassValue conversion

// Protobuf -> SassValue

extension SassList.Separator {
    init(_ separator: Sass_EmbeddedProtocol_ListSeparator) throws {
        switch separator {
        case .comma: self = .comma
        case .slash: self = .slash
        case .space: self = .space
        case .undecided: self = .undecided
        case .UNRECOGNIZED(let u):
            throw ProtocolError("Unrecognized list separator: \(u)")
        }
    }
}

// Some stuff to handle requirements introduced by 'argument list', basically
// side-effects of access to the value types.

final class SassValueMonitor {
    typealias ArgListAccessFn = (UInt32) -> Void
    var argListAccess: ArgListAccessFn
    init(_ argListAccess: @escaping ArgListAccessFn = { _ in }) {
        self.argListAccess = argListAccess
    }

    static func with<T>(_ accessFn: @escaping ArgListAccessFn, work: () throws -> T) rethrows -> T {
        _current.currentValue = SassValueMonitor(accessFn)
        defer { _current.currentValue = nil }
        return try work()
    }

    fileprivate static var _current = ThreadSpecificVariable(value: SassValueMonitor())
    fileprivate static var current: SassValueMonitor {
        _current.currentValue ?? SassValueMonitor()
    }
}

extension Sass_EmbeddedProtocol_Value {
    var monitor: SassValueMonitor {
        SassValueMonitor.current
    }
}

extension Sass_EmbeddedProtocol_Value {
    func asSassValue() throws -> SassValue {
        switch value {
        case .string(let m):
            return SassString(m.text, isQuoted: m.quoted)

        case .number(let n):
            return try SassNumber(n.value,
                                  numeratorUnits: n.numerators,
                                  denominatorUnits: n.denominators)

        case .rgbColor(let c):
            return try SassColor(red: Int(c.red),
                                 green: Int(c.green),
                                 blue: Int(c.blue),
                                 alpha: c.alpha)

        case .hslColor(let c):
            return try SassColor(hue: c.hue,
                                 saturation: c.saturation,
                                 lightness: c.lightness,
                                 alpha: c.alpha)

        case .list(let l):
            return try SassList(l.contents.map { try $0.asSassValue() },
                                separator: .init(l.separator),
                                hasBrackets: l.hasBrackets_p)

        case .argumentList(let l):
            let monitorFn = monitor.argListAccess
            return try SassArgumentList(l.contents.map { try $0.asSassValue() },
                                        keywords: l.keywords.mapValues { try $0.asSassValue() },
                                        keywordsObserver: { monitorFn(l.id) },
                                        separator: .init(l.separator))

        case .map(let m):
            var dict = [SassValue: SassValue]()
            try m.entries.forEach { entry in
                let key = try entry.key.asSassValue()
                let value = try entry.value.asSassValue()
                guard dict[key] == nil else {
                    throw ProtocolError("Bad map from compiler, duplicate key \(key).")
                }
                dict[key] = value
            }
            return SassMap(dict)

        case .singleton(let s):
            switch s {
            case .false: return SassConstants.false
            case .true: return SassConstants.true
            case .null: return SassConstants.null
            case .UNRECOGNIZED(let i):
                throw ProtocolError("Unknown singleton type \(i)")
            }

        case .compilerFunction(let c):
            return SassCompilerFunction(id: Int(c.id))

        case .hostFunction(let h):
            // not supposed to receive these in arguments
            throw ProtocolError("Don't know how to deserialize hostfunction \(h)")

        case nil:
            throw ProtocolError("Missing SassValue type.")
        }
    }
}

// SassValue -> Protobuf

extension Sass_EmbeddedProtocol_ListSeparator {
    init(_ separator: SassList.Separator) {
        switch separator {
        case .comma: self = .comma
        case .slash: self = .slash
        case .space: self = .space
        case .undecided: self = .undecided
        }
    }
}

extension Sass_EmbeddedProtocol_Value: SassValueVisitor {
    func visit(string: SassString) throws -> OneOf_Value {
        .string(.with {
            $0.text = string.string
            $0.quoted = string.isQuoted
        })
    }

    func visit(number: SassNumber) throws -> OneOf_Value {
        .number(.with {
            $0.value = number.double
            $0.numerators = number.numeratorUnits
            $0.denominators = number.denominatorUnits
        })
    }

    func visit(color: SassColor) throws -> OneOf_Value {
        switch color.preferredFormat {
        case .rgb:
            return .rgbColor(.with {
                $0.red = UInt32(color.red)
                $0.green = UInt32(color.green)
                $0.blue = UInt32(color.blue)
                $0.alpha = color.alpha
            })
        case .hsl:
            return .hslColor(.with {
                $0.hue = color.hue
                $0.saturation = color.saturation
                $0.lightness = color.lightness
                $0.alpha = color.alpha
            })
        }
    }

    func visit(list: SassList) throws -> OneOf_Value {
        .list(.with {
            $0.separator = .init(list.separator)
            $0.hasBrackets_p = list.hasBrackets
            $0.contents = list.map { .init($0) }
        })
    }

    func visit(argumentList: SassArgumentList) throws -> OneOf_Value {
        .argumentList(.with {
            // id / keywords access, an essay:
            // We're really creating a _new_ ArgList here, that sure may
            // be copied wholesale from something the compiler gave us, so
            // we set id=0 and don't worry about accessing the keywords: even
            // if the user is passing back an ArgList, they could just as well
            // be copying it manually themselves which would trigger the callback.
            $0.id = 0
            $0.separator = .init(argumentList.separator)
            $0.contents = argumentList.map { .init($0) }
            $0.keywords = argumentList.keywords.mapValues { .init($0) }
        })
    }

    func visit(map: SassMap) throws -> OneOf_Value {
        .map(.with { mapVal in
            mapVal.entries = map.dictionary.map { kv in
                .with {
                    $0.key = .init(kv.key)
                    $0.value = .init(kv.value)
                }
            }
        })
    }

    func visit(bool: SassBool) throws -> OneOf_Value {
        .singleton(bool.value ? .true : .false)
    }

    func visit(null: SassNull) throws -> OneOf_Value {
        .singleton(.null)
    }

    func visit(compilerFunction: SassCompilerFunction) throws -> OneOf_Value {
        .compilerFunction(.with {
            $0.id = UInt32(compilerFunction.id)
        })
    }

    func visit(dynamicFunction: SassDynamicFunction) throws -> OneOf_Value {
        .hostFunction(.with {
            $0.id = dynamicFunction.id
            $0.signature = dynamicFunction.signature
        })
    }

    init(_ val: SassValue) {
        self.value = try! val.accept(visitor: self)
    }
}
