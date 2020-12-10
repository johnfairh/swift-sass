//
//  TestImporters.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import EmbeddedSass

///
/// Tests for importers.
///
class TestImporters: EmbeddedSassTestCase {

    // MARK: Load Paths

    let importingSass = """
    @import secondary
    """
    let usingSass = """
    @use 'secondary'
    """

    let secondaryCssBlue = """
    a{color:blue}
    """
    let secondaryCssRed = """
    a{color:red}
    """
    let secondaryCssFilename = "secondary.css"

    private func createFileInNewDir(_ content: String, filename: String) throws -> URL {
        let tmpDir = try FileManager.default.createTemporaryDirectory()
        let url = tmpDir.appendingPathComponent(filename)
        try content.write(to: url)
        return tmpDir
    }

    // compiler loadpath works
    func testCompilerLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let compiler = try newCompiler(importers: [.loadPath(tmpDir)])
        let results = try compiler.compile(text: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // job loadpath works
    func testJobLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let compiler = try newCompiler()
        let results = try compiler.compile(text: usingSass, syntax: .sass,
                                           outputStyle: .compressed,
                                           importers: [.loadPath(tmpDir)])
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // job loadpath searched after compiler loadpath
    func testLoadPathOrder() throws {
        let tmpDirBlue = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let tmpDirRed = try createFileInNewDir(secondaryCssRed, filename: secondaryCssFilename)
        let compiler = try newCompiler(importers: [.loadPath(tmpDirRed)])
        let results = try compiler.compile(text: usingSass, syntax: .sass,
                                           outputStyle: .compressed,
                                           importers: [.loadPath(tmpDirBlue)])
        XCTAssertEqual(secondaryCssRed, results.css)
    }

    // nonsense in loadpath doesn't affect anyone (not even a warning!)
    func testNonsenseLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let nonsenseDir = URL(fileURLWithPath: "/not/a/directory")
        let compiler = try newCompiler(importers: [.loadPath(nonsenseDir), .loadPath(tmpDir)])
        let results = try compiler.compile(text: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // MARK: Custom Importers

    // A custom importer
    final class TestImporter: Importer {
        let css: String

        init(css: String) {
            self.css = css
        }

        /// State next request 'cannot be canonicalized'
        var failNextCanon: String? = nil
        var failedCanonCount = 0
        struct Error: Swift.Error, CustomStringConvertible {
            let message: String
            var description: String { message }
        }

        /// Claim next request
        var claimRequest: Bool = true
        var unclaimedRequestCount = 0

        func canonicalize(importURL: String) throws -> URL? {
            if let failNextCanon = failNextCanon {
                failedCanonCount += 1
                throw Error(message: failNextCanon)
            }
            guard claimRequest else {
                unclaimedRequestCount += 1
                return nil
            }
            return URL(string: "test://\(importURL)")
        }

        /// Fail the next import
        var failNextImport: String? = nil
        var failedImportCount = 0

        func load(canonicalURL: URL) throws -> ImporterResults {
            if let failNextImport = failNextImport {
                failedImportCount += 1
                throw Error(message: failNextImport)
            }
            return ImporterResults(css, syntax: .css)
        }
    }

    // Goodpath.
    func testCustomImporter() throws {
        let importer = TestImporter(css: secondaryCssRed)
        let compiler = try newCompiler(importers: [.importer(importer)])
        let results = try compiler.compile(text: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssRed, results.css)
    }

    // Bad path harness
    func checkFaultyImporter(customize: (TestImporter) -> Void, check: (TestImporter, CompilerError) -> Void) throws {
        let importer = TestImporter(css: secondaryCssRed)
        customize(importer)
        let compiler = try newCompiler(importers: [.importer(importer)])
        do {
            let results = try compiler.compile(text: usingSass, syntax: .sass)
            XCTFail("Compiled something: \(results)")
        } catch let error as CompilerError {
            check(importer, error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Canon says nil (not recognized)
    func testImportNotFound() throws {
        try checkFaultyImporter(customize: { $0.claimRequest = false }) { i, e in
            XCTAssertEqual(1, i.unclaimedRequestCount)
            XCTAssertTrue(e.message.contains("Can't find stylesheet"))
        }
    }

    // Canon fails (ambiguous)
    func testImportCanonFails() throws {
        try checkFaultyImporter(customize: { $0.failNextCanon = "Objection" }) { i, e in
            XCTAssertEqual(i.failNextCanon, e.message)
            XCTAssertEqual(1, i.failedCanonCount)
        }
    }

    // load fails
    func testImportFails() throws {
        try checkFaultyImporter(customize: { $0.failNextImport = "Objection" }) { i, e in
            XCTAssertEqual(i.failNextImport, e.message)
            XCTAssertEqual(1, i.failedImportCount)
        }
    }

    // Async importer
    func testAsyncImporter() throws {
        let importer = HangingAsyncImporter()
        let compiler = try newCompiler(importers: [.importer(importer)])
        let results = try compiler.compile(text: "@import 'something';")
        XCTAssertEqual("", results.css)
    }

    // Async importer goodpath - hangable.  In utils.
    // Async importer stuck path, in TestResetShutdown, quiesce and reset.
    // malformed messages (over in TestProtocolErrors I suppose)
    // some missing good-path thing?
}
