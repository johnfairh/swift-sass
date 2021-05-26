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
        case relativeSourceRoot(String)
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

        case .relativeSourceRoot(let sourceRoot):
            sourceMap.sourceRoot = sourceRoot
            fallthrough

        case .relative:
            sourceMap.sources = sourceMap.sources.map {
                .init(url: URL(string: $0.url)!.asRelativeURL(from: cssFileURL), content: $0.content)
            }
            fallthrough

        case .sourcesAbsolute:
            actualSourceMapURL = sourceMapFileURL.asRelativeURL(from: cssFileURL)
        }

        return CompilerResults(
            css: css + "\n/*# sourceMappingURL=\(actualSourceMapURL) */\n",
            sourceMap: try sourceMap.encodeString(continueOnError: true),
            messages: messages)
    }
}

extension URL {
    /// Rework a file URL relative to some other file - only useful if both are file:
    func asRelativeURL(from: URL) -> String {
        guard isFileURL && from.isFileURL else {
            return absoluteString
        }
        let myComponents = pathComponents
        let fromComponents = from.pathComponents
        let pieces = zip(myComponents, fromComponents)
        let shared = pieces.prefix(while: { $0 == $1 }).count
        let comps = Array(repeating: "..", count: fromComponents.count - shared - 1) +
            myComponents.suffix(myComponents.count - shared)
        return comps.joined(separator: "/")
    }
}
