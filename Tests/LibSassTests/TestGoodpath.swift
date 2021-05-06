//
//  TestGoodpath.swift
//  LibSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import XCTest
import TestHelpers
import LibSass
import SourceMapper

/// Basic in/out format style no errors or fanciness
///
/// libsass differences from dart sass:
/// - 2-space indent instead of 4-space indent
/// - 'compressed' format is too ambitious, no space after 'div'
/// - trailing newline on everything.
class TestGoodpath: XCTestCase {
    let scssIn = """
    div {
        a {
            color: blue;
        }
    }
    """
    let scssOutNested = """
    div a {
      color: blue; }

    """
    let scssOutCompressed = """
    diva{color:blue}

    """

    let sassIn = """
    $font-stack:    Helvetica, sans-serif
    $primary-color: #333

    body
        font: 100% $font-stack
        color: $primary-color
    """
    let sassOutNested = """
    body {
      font: 100% Helvetica, sans-serif;
      color: #333; }

    """
    let sassOutExpanded = """
    body {
      font: 100% Helvetica, sans-serif;
      color: #333;
    }

    """
    let sassOutCompressed = """
    body{font:100% Helvetica,sans-serif;color:#333}

    """
    let sassOutCompact = """
    body { font: 100% Helvetica, sans-serif; color: #333; }

    """


    /// Does it work, goodpath, no imports, scss/sass/css inline input
    func testCoreInline() throws {
        let compiler = Compiler()
        let results1 = try compiler.compile(string: scssIn)
        XCTAssertNil(results1.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertEqual(scssOutNested, results1.css)

        let results2 = try compiler.compile(string: sassIn, syntax: .sass)
        XCTAssertNil(results2.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertEqual(sassOutNested, results2.css)

        let results3 = try compiler.compile(string: sassOutNested, syntax: .css)
        XCTAssertNil(results3.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertEqual(sassOutNested, results3.css)
    }

    private func checkCompileFromFile(_ compiler: Compiler, extnsion: String, content: String, expected: String) throws {
        let url = try FileManager.default.createTempFile(filename: "file.\(extnsion)", contents: content)
        let results = try compiler.compile(fileURL: url)
        XCTAssertEqual(expected, results.css)
    }

    /// Does it work, from a file
    func testAbsoluteFile() throws {
        let compiler = Compiler()
        try checkCompileFromFile(compiler, extnsion: "scss", content: scssIn, expected: scssOutNested)
        try checkCompileFromFile(compiler, extnsion: "sass", content: sassIn, expected: sassOutNested)
    }

    /// Does it work, from a relative path
    ///
    /// (actually not a relative path because we don't trust libsass to handle the current directory properly
    /// and so always pass it an absolute path)
    func testRelativeFile() throws {
        let tmpDir = try FileManager.default.createTemporaryDirectory()
        let scssFile = tmpDir.appendingPathComponent("file.scss")
        try scssIn.write(to: scssFile)
        try tmpDir.withCurrentDirectory {
            let compiler = Compiler()
            let results = try compiler.compile(fileURL: URL(fileURLWithPath: "file.scss"))
            if scssOutNested != results.css {
                print(results.css)
            }
            XCTAssertEqual(scssOutNested, results.css)
        }
    }

    /// Is source map transmitted OK
    func testSourceMap() throws {
        let compiler = Compiler()

        let results = try compiler.compile(string: scssIn, fileURL: URL(fileURLWithPath: "custom/bar"), createSourceMap: true)
        XCTAssertEqual(scssOutNested, results.css)

        let json = try XCTUnwrap(results.sourceMap)

        let sourceMap = try SourceMap(string: json)
        XCTAssertEqual(SourceMap.VERSION, sourceMap.version)
        // oh boy libsass is doing sourcemaps all wrong
        XCTAssertTrue(sourceMap.mappings == "AACI;EACI,OAAO" || sourceMap.mappings == "AAAA,AACI;EACI,OAAO")
        print(try sourceMap.getSegmentsDescription())
        XCTAssertEqual(1, sourceMap.sources.count)
        XCTAssertEqual("custom/bar", sourceMap.sources[0].url)
        XCTAssertNil(sourceMap.sources[0].content)
        XCTAssertEqual("custom/bar.css", sourceMap.file)
    }

    /// Is outputstyle enum translated OK
    func testOutputStyle() throws {
        let compiler = Compiler()

        let styles: [CssStyle] = [.compressed, .nested, .compact, .expanded]
        let expected = [sassOutCompressed, sassOutNested, sassOutCompact, sassOutExpanded]
        try zip(styles, expected).forEach { tc in
            let results = try compiler.compile(string: sassIn, syntax: .sass, outputStyle: tc.0)
            XCTAssertEqual(tc.1, results.css, String(describing: tc.0))
        }
    }

    func testVersion() {
        let version = Compiler.libVersion
        XCTAssertTrue(version.hasPrefix("4.0.0"))
    }
}
