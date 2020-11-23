//
//  TestUtils.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import Foundation
import EmbeddedSass

enum TestUtils {
    static var unitTestDirURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    static var dartSassEmbeddedDirURL: URL {
        let rootURL = unitTestDirURL.appendingPathComponent("dart-sass-embedded")
        #if os(Linux)
        let platformURL = rootURL.appendingPathComponent("linux")
        #else
        let platformURL = rootURL.appendingPathComponent("macos")
        #endif
        return platformURL.appendingPathComponent("sass_embedded")
    }

    static var dartSassEmbeddedURL: URL {
        dartSassEmbeddedDirURL.appendingPathComponent("dart-sass-embedded")
    }

    static func newCompiler(importers: [ImportResolver] = [], functions: SassFunctionMap = [:]) throws -> Compiler {
        let c = try Compiler(embeddedCompilerURL: TestUtils.dartSassEmbeddedURL,
                             importers: importers,
                             functions: functions)
        c.debugHandler = { m in print("debug: \(m)") }
        return c
    }
}

extension String {
    func write(to url: URL) throws {
        try write(toFile: url.path, atomically: false, encoding: .utf8)
    }
}
extension FileManager {

    func createTempFile(filename: String, contents: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: url)
        return url
    }

    /// Create a new empty temporary directory.  Caller must delete.
    func createTemporaryDirectory(inDirectory directory: URL? = nil, name: String? = nil) throws -> URL {
        let directoryName = name ?? UUID().uuidString
        let parentDirectoryURL = directory ?? temporaryDirectory
        let directoryURL = parentDirectoryURL.appendingPathComponent(directoryName)
        try createDirectory(at: directoryURL, withIntermediateDirectories: false)
        return directoryURL
    }
}
