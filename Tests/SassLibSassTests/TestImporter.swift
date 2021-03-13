//
//  TestImporter.swift
//  SassLibSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import TestHelpers
import SassLibSass

/// Custom importers, libsass-style
class TestImporter: XCTestCase {

    class CustomImporter: LibSassImporter {
        func load(ruleURL: String, contextFileURL: URL) throws -> ImporterResults? {
            print("rule: \(ruleURL)\nctxt: \(contextFileURL)\npath: \(contextFileURL.path)")
            return ImporterResults("a { b: 1 }")
        }
    }

    func testExplore() throws {
        let compiler = Compiler(importers: [.libSassImporter(CustomImporter())])
        let results = try compiler.compile(string: "@import 'fred';\n@import 'fred';\n@import 'jane/fred';",
                                           fileURL: URL(fileURLWithPath: "base.scss"))
        print(results)
    }
}

