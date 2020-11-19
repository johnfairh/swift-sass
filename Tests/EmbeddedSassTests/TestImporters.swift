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
        let compiler = try TestUtils.newCompiler(loadPaths: [tmpDir])
        let results = try compiler.compile(sourceText: importingSass, sourceSyntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // job loadpath works
    func testJobLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let compiler = try TestUtils.newCompiler()
        let results = try compiler.compile(sourceText: usingSass, sourceSyntax: .sass,
                                           outputStyle: .compressed,
                                           loadPaths: [tmpDir])
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // job loadpath searched after compiler loadpath
    func testLoadPathOrder() throws {
        let tmpDirBlue = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let tmpDirRed = try createFileInNewDir(secondaryCssRed, filename: secondaryCssFilename)
        let compiler = try TestUtils.newCompiler(loadPaths: [tmpDirRed])
        let results = try compiler.compile(sourceText: usingSass, sourceSyntax: .sass,
                                           outputStyle: .compressed,
                                           loadPaths: [tmpDirBlue])
        XCTAssertEqual(secondaryCssRed, results.css)
    }
}
