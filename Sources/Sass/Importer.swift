//
//  Importer.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

// Types used as part of custom importers.

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

public protocol Importer {
    func canonicalize(filespec: String) throws -> URL?
    func `import`(canonicalURL: URL) throws -> ImportResults
}

