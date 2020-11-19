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
class TestImporters: XCTestCase {

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
        let compiler = try TestUtils.newCompiler(importers: [.loadPath(tmpDir)])
        let results = try compiler.compile(sourceText: importingSass, sourceSyntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // job loadpath works
    func testJobLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let compiler = try TestUtils.newCompiler()
        let results = try compiler.compile(sourceText: usingSass, sourceSyntax: .sass,
                                           outputStyle: .compressed,
                                           importers: [.loadPath(tmpDir)])
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // job loadpath searched after compiler loadpath
    func testLoadPathOrder() throws {
        let tmpDirBlue = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let tmpDirRed = try createFileInNewDir(secondaryCssRed, filename: secondaryCssFilename)
        let compiler = try TestUtils.newCompiler(importers: [.loadPath(tmpDirRed)])
        let results = try compiler.compile(sourceText: usingSass, sourceSyntax: .sass,
                                           outputStyle: .compressed,
                                           importers: [.loadPath(tmpDirBlue)])
        XCTAssertEqual(secondaryCssRed, results.css)
    }

    // nonsense in loadpath doesn't affect anyone (not even a warning!)
    func testNonsenseLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let nonsenseDir = URL(fileURLWithPath: "/not/a/directory")
        let compiler = try TestUtils.newCompiler(importers: [.loadPath(nonsenseDir), .loadPath(tmpDir)])
        let results = try compiler.compile(sourceText: importingSass, sourceSyntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // MARK: Custom Importers

    // A custom importer
    struct TestImporter: CustomImporter {
        let css: String

        init(css: String) {
            self.css = css
        }

        /// State next request 'cannot be canonicalized'
        var failNextCanon: String? = nil
        struct Error: Swift.Error {
            let message: String
        }

        /// Claim next request
        var claimRequest: Bool = true

        func canonicalize(filespec: String) throws -> URL? {
            if let failNextCanon = failNextCanon {
                throw Error(message: failNextCanon)
            }
            return claimRequest ? URL(string: "test://\(filespec)") : nil
        }

        /// Fail the next import
        var failNextImport: String? = nil

        func `import`(canonicalURL: URL) throws -> ImportResults {
            if let failNextImport = failNextImport {
                throw Error(message: failNextImport)
            }
            return ImportResults(css, syntax: .css)
        }
    }

    // Goodpath.
    func testCustomImporter() throws {
        let importer = TestImporter(css: secondaryCssRed)
        let compiler = try TestUtils.newCompiler(importers: [.custom(importer)])
        let results = try compiler.compile(sourceText: importingSass, sourceSyntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssRed, results.css)
    }

    // canon says nil
    // canon throws
    // import fails
}
