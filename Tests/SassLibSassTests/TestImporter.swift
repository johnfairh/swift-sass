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

    class StaticImporter: Importer {
        private let content: String
        private let importedName: String
        var disableNextLoad: Bool

        init(content: String, importedName: String = "") {
            self.content = content
            self.importedName = importedName
            self.disableNextLoad = false
        }

        func load(ruleURL: String, contextFileURL: URL) throws -> ImporterResults? {
            guard !disableNextLoad else {
                disableNextLoad = false
                return nil
            }
            return ImporterResults(content, fileURL: URL(fileURLWithPath: importedName))
        }
    }

    // Ordering

    func testImporterPriority() throws {
        let importers: [ImportResolver] = [
            .importer(StaticImporter(content: "a { b: 1 }")),
            .importer(StaticImporter(content: "a { c: 1 }"))
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
        let importer = StaticImporter(content: Self.dynImportContent, importedName: "dynimported.scss")
        let compiler = Compiler(importers: [.importer(importer)])

        try testFn(compiler, importer, tmpDir, mainURL)
    }

    func testUseIsBroken() throws {
        try withRulesSetup { compiler, importer, tmpDir, mainURL in
            assertFile(try compiler.compile(string: "@use 'imported';", fileURL: mainURL))
        }
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

    class BadImporter: Importer {
        struct Error: Swift.Error {
        }

        func load(ruleURL: String, contextFileURL: URL) throws -> ImporterResults? {
            throw Error()
        }
    }

    func testFailedImporter() throws {
        let compiler = Compiler(importers: [.importer(BadImporter())])
        do {
            let results = try compiler.compile(string: "@import 'something';")
            XCTFail("Managed to compile: \(results)")
        } catch let error as CompilerError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // sourcemap

    func testSourceMap() throws {
        let importer1 = StaticImporter(content: "div { a: b }", importedName: "x")
        let importer2 = StaticImporter(content: "span { a: b }", importedName: "imported.scss")
        importer1.disableNextLoad = true
        let compiler = Compiler()
        let results = try compiler.compile(string: "@import 'one';\n@import 'two';",
                                           fileURL: URL(fileURLWithPath: "main.scss"),
                                           createSourceMap: true,
                                           importers: [
                                            .importer(importer1),
                                            .importer(importer2)
                                           ])
        let json = try XCTUnwrap(results.sourceMap)
        // Check we have a reasonable-looking source map, details don't matter
        let map = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String:Any]
        let sources = try XCTUnwrap(map["sources"] as? Array<String>)
        XCTAssertEqual("main.scss", sources[0])
        XCTAssertEqual("imported.scss", sources[1])
        XCTAssertEqual("x", sources[2])
    }
}
