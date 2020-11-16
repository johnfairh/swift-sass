//
//  TestUtils.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
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

    static func newCompiler() throws -> Compiler {
        let c = try Compiler(embeddedCompilerURL: TestUtils.dartSassEmbeddedURL)
        c.debugHandler = { m in print("debug: \(m)") }
        return c
    }

    static func tempFile(filename: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try contents.write(toFile: url.path, atomically: false, encoding: .utf8)
        return url
    }
}
