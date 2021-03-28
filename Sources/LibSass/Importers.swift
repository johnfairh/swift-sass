//
//  Importers.swift
//  LibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import struct Foundation.URL

/// The results of loading a stylesheet through an importer.
public struct ImporterResults {
    // MARK: Initializers

    /// Initialize a new `ImporterResults`.
    ///
    /// - parameter contents: The stylesheet text.
    /// - parameter fileURL: A file URL to represent the imported file.  It's important that this is
    ///   unique for a piece of content across a compilation otherwise LibSass will be confused.  The filename
    ///   in the path is used in the generated source map.
    /// - parameter syntax: The syntax of `contents`, default `.scss`.
    public init(_ contents: String, fileURL: URL, syntax: Syntax = .scss) {
        self.contents = contents
        self.syntax = syntax
        self.fileURL = fileURL
    }

    // MARK: Properties

    /// The contents of the stylesheet.
    public let contents: String
    /// The syntax of the stylesheet.
    public let syntax: Syntax
    /// URL used to reference the stylesheet internally and in a source map.
    public let fileURL: URL
}

/// How the Sass compiler should resolve `@import`, `@use`, and `@forward` rules.
public enum ImportResolver {
    /// Search a filesystem directory to resolve the rule.  See [the Sass docs](https://sass-lang.com/documentation/at-rules/import#load-paths).
    case loadPath(URL)

    /// Interpret the rule and return a stylesheet.
    ///
    /// - `ruleURL` is the text following the `@import` as written in the rule.
    /// - `contextFileURL` is the URL of the stylesheet that contains the rule being processed.
    ///
    /// The routine must do one of:
    /// - return `nil` to indicate that this importer cannot resolve the required URL.  The Sass compiler
    ///   will try the next importer.
    /// - return a filled-in `ImporterResults` with the stylesheet to be imported.
    /// - throw an error of some kind indicating either that the import is ambiguous or some other kind
    ///   of serious error condition exists.  The Sass compiler will error out.
    case importer((_ ruleURL: String, _ contextFileURL: URL) throws -> ImporterResults?)

    /// Interpret the rule and return the filesystem location of a stylesheet.
    ///
    /// This is useful over `importer(...)` to take advantage of the filename searching and loading
    /// functions in LibSass.
    ///
    /// - `ruleURL` is the text following the `@import` as written in the rule.
    /// - `contextFileURL` is the URL of the stylesheet that contains the rule being processed.
    ///
    /// The routine must do one of:
    /// - return `nil` to indicate that this importer cannot resolve the required URL.  The Sass compiler
    ///   will try the next importer.
    /// - return the URL of the stylesheet to import.  The compiler performs standard Sass file resolution
    ///   on this, which in particular means you can return a directory path here as a dynamic version of
    ///   `loadPath(...)`.
    /// - throw an error of some kind indicating either that the import is ambiguous or some other kind
    ///   of serious error condition exists.  The Sass compiler will error out.
    case fileImporter((_ ruleURL: String, _ contextFileURL: URL) throws -> URL?)
}
