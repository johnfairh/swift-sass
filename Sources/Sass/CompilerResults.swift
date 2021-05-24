//
//  CompilerResults.swift
//  Sass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation
@_implementationOnly import SourceMapper

/// The output from a successful compilation.
public struct CompilerResults {
    /// The  CSS produced by the Sass compiler.
    public let css: String

    /// The JSON sourcemap for `css`, style according to the `SourceMapStyle` provided at compile time.
    public let sourceMap: String?

    /// Any compiler warnings and debug statements.
    public let messages: [CompilerMessage]

    /// :nodoc:
    public init(css: String, sourceMap: String?, messages: [CompilerMessage]) {
        self.css = css
        self.sourceMap = sourceMap
        self.messages = messages
    }

    public enum URLStyle {
        case allAbsolute
        case sourcesAbsolute
        case relative
        case relativeSrcRoot(String)
    }

    public struct Error: Swift.Error {}

    public func withFileLocations(cssFileURL: URL, sourceMapFileURL: URL, style: URLStyle = .relative) throws -> CompilerResults {
        guard let sourceMapString = self.sourceMap else {
            throw Error() // XXX
        }

        let sourceMap = try SourceMap(string: sourceMapString)
        sourceMap.file = cssFileURL.lastPathComponent

        let actualSourceMapURL: String

        switch style {
        case .allAbsolute:
            actualSourceMapURL = sourceMapFileURL.absoluteString

        default:
            preconditionFailure()
        }

        return CompilerResults(
            css: css + "\n/*# sourceMappingURL=\(actualSourceMapURL) */\n",
            sourceMap: try sourceMap.encodeString(continueOnError: true),
            messages: messages)
    }
}
