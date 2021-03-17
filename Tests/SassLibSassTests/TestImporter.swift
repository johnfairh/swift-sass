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

    class StaticImporter: LibSassImporter {
        private let content: String
        private let importedURL: URL?
        var disableNextLoad: Bool

        init(content: String, importedURL: URL? = nil) {
            self.content = content
            self.importedURL = importedURL
            self.disableNextLoad = false
        }

        func load(ruleURL: String, contextFileURL: URL) throws -> ImporterResults? {
            guard !disableNextLoad else {
                disableNextLoad = false
                return nil
            }
            return ImporterResults(content, sourceMapURL: importedURL)
        }
    }

    // Ordering

    func testImporterPriority() throws {
        let importers: [ImportResolver] = [
            .libSassImporter(StaticImporter(content: "a { b: 1 }")),
            .libSassImporter(StaticImporter(content: "a { c: 1 }"))
        ]

        let compiler = Compiler()
        let results1 = try compiler.compile(string: "@import 'something';",
                                            fileURL: URL(fileURLWithPath: "main.scss"),
                                            outputStyle: .compact,
                                            importers: importers)
        XCTAssertEqual("a { b: 1; }\n", results1.css)

        let results2 = try compiler.compile(string: "@import 'something';",
                                            fileURL: URL(fileURLWithPath: "main.scss"),
                                            outputStyle: .compact,
                                            importers: importers.reversed())
        XCTAssertEqual("a { c: 1; }\n", results2.css)
    }

    // Internal libsass importer rules, as we understand them...

    static let fileImportContent = "a { b: file }"
    static let dynImportContent = "a { b: dyn }"
    static let mainContent = "@import 'imported';"

    func assertFile(_ results: CompilerResults) { XCTAssertTrue(results.css.contains("b: file")) }
    func assertDyn(_ results: CompilerResults) { XCTAssertTrue(results.css.contains("b: dyn")) }

    func withRulesSetup(_ testFn: (Compiler, StaticImporter, URL, URL) throws -> Void) throws {
        let tmpDir = try FileManager.default.createTemporaryDirectory()

        let fileImportURL = tmpDir.appendingPathComponent("imported.scss")
        try Self.fileImportContent.write(to: fileImportURL)
        let mainURL = tmpDir.appendingPathComponent("main.scss")
        try Self.mainContent.write(to: mainURL)
        let importer = StaticImporter(content: Self.dynImportContent, importedURL: URL(fileURLWithPath: "dynimported.scss"))
        let compiler = Compiler(importers: [.libSassImporter(importer)])

        try testFn(compiler, importer, tmpDir, mainURL)
    }

    func testCustomBeforeNative() throws {
        try withRulesSetup { compiler, importer, tmpDir, mainURL in
            assertDyn(try compiler.compile(fileURL: mainURL))
        }
    }

    func testNativeAfterCustom() throws {
        try withRulesSetup { compiler, importer, tmpDir, mainURL in
            importer.disableNextLoad = true
            assertFile(try compiler.compile(fileURL: mainURL))
            XCTAssertFalse(importer.disableNextLoad)
        }
    }

    func testCustomBeforeLoadPath() throws {
        try withRulesSetup { compiler, importer, tmpDir, mainURL in
            assertDyn(try compiler.compile(string: Self.mainContent,
                                           importers: [.loadPath(tmpDir)]))
        }
    }

    func testLoadPathAfterCustom() throws {
        try withRulesSetup { compiler, importer, tmpDir, mainURL in
            importer.disableNextLoad = true
            assertFile(try compiler.compile(string: Self.mainContent,
                                            importers: [.loadPath(tmpDir)]))
            XCTAssertFalse(importer.disableNextLoad)
        }
    }

    func testCurrentDirectoryFallback() throws {
        try withRulesSetup { compiler, importer, tmpDir, mainURL in
            try tmpDir.withCurrentDirectory {
                importer.disableNextLoad = true
                assertFile(try compiler.compile(string: Self.mainContent))
                XCTAssertFalse(importer.disableNextLoad)
            }
        }
    }

    // errors

    class BadImporter: LibSassImporter {
        struct Error: Swift.Error {
        }

        func load(ruleURL: String, contextFileURL: URL) throws -> ImporterResults? {
            throw Error()
        }
    }

    func testFailedImporter() throws {
        let compiler = Compiler(importers: [.libSassImporter(BadImporter())])
        do {
            let results = try compiler.compile(string: "@import 'something';")
            XCTFail("Managed to compile: \(results)")
        } catch let error as CompilerError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// sourcemap
