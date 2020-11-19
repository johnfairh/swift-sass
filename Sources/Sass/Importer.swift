//
//  Importer.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

// Types used as part of resolving `@import` and `@use` rules.

public struct ImportResults {
    public let contents: String
    public let syntax: Syntax
    public let sourceMapURL: URL?

    public init(_ contents: String, syntax: Syntax, sourceMapURL: URL? = nil) {
        self.contents = contents
        self.syntax = syntax
        self.sourceMapURL = sourceMapURL
    }
}

public protocol CustomImporter {
    /// - returns: `nil` means cannot resolve filespec to a stylesheet.
    ///            Otherwise the canonical URL for the filespec.
    /// - throws: something if the filespec is ambiguous and matches multiple stylesheets meaning
    ///           the canonical URL cannot be determined.
    func canonicalize(filespec: String) throws -> URL?
    func `import`(canonicalURL: URL) throws -> ImportResults
}

public enum ImportResolver {
    /// Search a filesystem directory to resolve the rule.
    case loadPath(URL)
    /// Call back through the `CustomImporter` to resolve the rule.
    case custom(CustomImporter)
}
