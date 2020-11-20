//
//  ProtobufConversion.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Helpers to shuffle data in and out of the protobuf types.

import Foundation

// MARK: PB -> Native

extension String {
    var nonEmptyString: String? {
        isEmpty ? nil : self
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

// MARK: Native -> PB

extension Sass_EmbeddedProtocol_InboundMessage.Syntax {
    init(_ syntax: Syntax) {
        switch syntax {
        case .css: self = .css
        case .indented, .sass: self = .indented
        case .scss: self = .scss
        }
    }
}

extension Sass_EmbeddedProtocol_InboundMessage.CompileRequest.OutputStyle {
    init(_ style: CssStyle) {
        switch style {
        case .compact: self = .compact
        case .compressed: self = .compressed
        case .expanded: self = .expanded
        case .nested: self = .nested
        }
    }
}

extension Sass_EmbeddedProtocol_InboundMessage.CompileRequest.Importer {
    init(_ importer: ImportResolver, id: UInt32) {
        self.init()
        switch importer {
        case .loadPath(let url):
            path = url.path
        case .custom(_):
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
