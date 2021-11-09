//
//  Importers.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import struct Foundation.URL
import NIOCore

/// The results of loading a stylesheet through an importer.
public struct ImporterResults: Sendable {
    // MARK: Initializers

    /// Initialize a new `ImporterResults`.
    ///
    /// - parameter contents: The stylesheet text.
    /// - parameter syntax: The syntax of `contents`, default `.scss`.
    /// - parameter sourceMapURL: Optionally, an absolute, browser-accessible URL for
    ///   the stylesheet for reference from any source map that the compiler has been asked to
    ///   generate.  Ideally a `file:` URL, otherwise `https:`.  If `nil` then the compiler
    ///   uses an inline `data:` URL in the source map.
    public init(_ contents: String, syntax: Syntax = .scss, sourceMapURL: URL? = nil) {
        self.contents = contents
        self.syntax = syntax
        self.sourceMapURL = sourceMapURL
    }

    // MARK: Properties

    /// The contents of the stylesheet.
    public let contents: String
    /// The syntax of the stylesheet.
    public let syntax: Syntax
    /// URL used to reference the stylesheet from a source map.
    public let sourceMapURL: URL?
}

/// Methods required to implement a stylesheet importer.
///
/// Importers resolve `@import`, `@use`, and `@forward` rules in
/// stylesheets.  The methods are called back by the compiler during compilation.  You
/// don't need this to include the contents of a filesystem directory: see instead
/// `ImportResolver.loadPath(_:)`.
///
/// You could use this to present network resources or dynamically constructed content.
///
/// An import has two steps: canonicalization and loading.
///
/// `Importer.canonicalize(...)` is always called first with whatever URL
/// text the user has written in their rule.  The routine interprets that and returns a _canonical_
/// URL that is absolute with a scheme.
///
/// The compiler most likely implements a cache based on canonical URLs.  If the compiler
/// does not have a stylesheet cached for the canonical URL then it calls
/// `Importer.load(...)` with that URL to get at the content.
///
/// ### File extension rules
///
/// Sass itself handles imports from the filesystem using various filename conventions.
/// Users of your importer mostly likely expect the same behavior if the URLs you
/// are importing resemble filenames with extensions and directories.
///
/// From the Sass embedded protocol documentation:
///
/// The importer should look for stylesheets by adding the prefix `_` to the
/// URL's basename, and by adding the extensions `.sass` and `.scss` if the
/// URL doesn't already have one of those extensions. For example, given the URL
/// "foo/bar/baz" the importer should look for:
///
/// 1. `foo/bar/baz.sass`
/// 2. `foo/bar/baz.scss`
/// 3. `foo/bar/_baz.sass`
/// 4. `foo/bar/_baz.scss`
///
/// Given the URL "foo/bar/baz.scss" the importer should look for:
///
/// 1. `foo/bar/baz.scss`
/// 2. `foo/bar/_baz.scss`
///
/// If the importer finds a stylesheet at more than one of these URLs then it
/// must throw an error indicating that the import is ambiguous.
///
/// If none of the possible paths are valid then the importer should perform the
/// same resolution on the URL followed by `/index`. In the example above, it
/// should additionally look for:
///
/// 1. `foo/bar/baz/_index.sass`
/// 2. `foo/bar/baz/index.sass`
/// 3. `foo/bar/baz/_index.scss`
/// 4. `foo/bar/baz/index.scss`
///
/// If more than one of these implicit index resources exist then the importer must
/// throw an error indicating that the import is ambiguous.
public protocol Importer: Sendable {
    /// Convert an imported URL to its canonical format.
    ///
    /// The returned URL must be absolute and include a scheme.  If the routine
    /// happens to be called with a resource's canonical URL (including something
    /// the routine previously returned) then it must be returned unchanged.
    ///
    /// - parameter ruleURL: The text following `@import` or `@use` in
    ///   a stylesheet.
    /// - parameter fromImport: Whether this request comes from an `@import` rule.
    ///   See [import-only files](https://sass-lang.com/documentation/at-rules/import#import-only-files).
    /// - returns: The canonical absolute URL, or `nil` if the importer doesn't recognize the
    ///   import request to have the compiler try the next importer.
    /// - throws: Only when `ruleURL` cannot be canonicalized: it is definitely
    ///   this importer's responsibility to do so, but it can't.  For example, if the request is
    ///   "foo" but both `foo.sass` and `foo.css` are available.  If "foo" didn't match
    ///   anything then the importer should return `nil` instead.
    ///
    ///   Compilation will stop, quoting the description of the error thrown as the reason.
    func canonicalize(ruleURL: String, fromImport: Bool) async throws -> URL?

    /// Load a stylesheet from a canonical URL
    ///
    /// - parameter canonicalURL: A URL previously returned by
    ///   `canonicalize(...)` during this compilation.
    /// - returns: The stylesheet and optional source map.
    /// - throws: If the stylesheet cannot be loaded.  Compilation will stop, quoting
    ///   the description of this error as the reason.
    func load(canonicalURL: URL) async throws -> ImporterResults
}

/// Methods required to implement a stylesheet importer - NIO-style.
///
/// See `Importer`.
public protocol ImporterNIO: Sendable {
    /// NIO-style version of `Importer.canonicalize(...)`.
    func canonicalize(eventLoop: EventLoop, ruleURL: String, fromImport: Bool) -> EventLoopFuture<URL?>
    /// NIO-style version of `Importer.load(...)`.
    func load(eventLoop: EventLoop, canonicalURL: URL) -> EventLoopFuture<ImporterResults>
}

/// How the Sass compiler should resolve `@import`, `@use`, and `@forward` rules.
public enum ImportResolver: Sendable {
    /// Search a filesystem directory to resolve the rule.  See [the Sass docs](https://sass-lang.com/documentation/at-rules/import#load-paths).
    case loadPath(URL)
    /// Call back through the `Importer` to resolve the rule.
    case importer(Importer)
    /// Call back through the `ImporterNIO` to resolve the rule.
    case importerNIO(ImporterNIO)
}
