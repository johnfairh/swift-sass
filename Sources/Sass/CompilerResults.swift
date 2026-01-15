//
//  CompilerResults.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation
import SourceMapper

/// The output from a successful compilation.
public struct CompilerResults: Sendable {
    /// The  CSS produced by the Sass compiler.
    public let css: String

    /// The JSON sourcemap for `css`, style according to the `SourceMapStyle` provided at compile time.
    public let sourceMap: String?

    /// Any compiler warnings and debug statements.
    public let messages: [CompilerMessage]

    /// The canonical URLs of all source files used to produce `css`.
    ///
    /// This includes the URL of the initial Sass file if it is known.
    public let loadedURLs: [URL]

    /// :nodoc:
    public init(css: String, sourceMap: String?, messages: [CompilerMessage], loadedURLs: [URL]) {
        self.css = css
        self.sourceMap = sourceMap
        self.messages = messages
        self.loadedURLs = loadedURLs
    }

    // MARK: Source Map URL Control

    /// How to reference source map resources from CSS.
    ///
    /// There are two references here: the CSS pointing at the source map, and the source map
    /// pointing at the original sources.  The Sass compiler uses absolute (typically `file:`) URLs
    /// for original sources.  This can be modified and the CSS -> source map reference added using
    /// `CompilerResults.withFileLocations(...)`.
    ///
    /// If you plan to ship the source map (so it is accessed through `http:` URLs by a browser)
    /// then you need to use one of the `.relative` options to avoid `file:` URLs that won't
    /// make sense to clients.
    ///
    public enum URLStyle: Sendable {
        /// Use absolute (`file:` for filesystem files) URLs everywhere.
        case allAbsolute

        /// Use absolute URLs in the source map to refer to the original sources, but use a relative
        /// URL to refer to the source map from the CSS.
        case sourcesAbsolute

        /// Use relative URLs everywhere possible.  For example if an original source is referenced
        /// with an `https:` or `data:` URL then that version is preserved.
        case relative

        /// Like `relative`, but also set the `sourceRoot` source map field to add extra path
        /// segments between the source map and the original sources.
        case relativeSourceRoot(String)
    }

    /// Error indicating there is no source map present when one is required.  :nodoc:
    public struct NoSourceMapError: Swift.Error {}

    /// Add filenames to the CSS and its source map.
    ///
    /// The CSS and source map come out of the Sass compiler without references to each other.  Sources
    /// are referenced from the source map using absolute URLs.  This routine updates various metadata to
    /// make the source map load correctly in a browser.
    ///
    /// This routine does not write any files.
    ///
    /// - parameter cssFileURL: The file URL for the CSS.  This is used to update the source map
    ///   with the name of the file it's describing and, if `style` requires it, calculation of relative paths.
    /// - parameter sourceMapFileURL: The file URL for the source map.  This is used to generate the
    ///   *sourceMappingURL* comment in the CSS.
    /// - parameter style: How to reference the source map from the CSS and the sources from the
    ///   source map.  See `URLStyle`; the default is `.relative`.
    /// - throws: If the `CompilerResults` does not have a source map, or if JSON encoding/
    ///   decoding goes wrong.
    /// - returns: A new `CompilerResults` with updated `css` and `sourceMap` fields.  The
    ///   `messages` and `loadedURLs` fields are copied over unchanged.
    public func withFileLocations(cssFileURL: URL, sourceMapFileURL: URL, style: URLStyle = .relative) throws -> CompilerResults {
        guard let sourceMapString = self.sourceMap else {
            throw NoSourceMapError()
        }

        var sourceMap = try SourceMap(sourceMapString)
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
            sourceMap: try sourceMap.encodeString(),
            messages: messages,
            loadedURLs: loadedURLs)
    }
}

// internal for test
extension URL {
    /// Rework a file URL relative to some other file - only useful if both are `file:`
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
