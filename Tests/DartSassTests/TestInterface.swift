//
//  TestInterface.swift
//  DartSassTests
//
//  Copyright 2020-2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import XCTest
import DartSass

///
/// Tests to check the normal operation of the sass compiler -- not testing the compiler itself,
/// just that we can talk to it honestly and translate enums etc. properly.
///
class TestInterface: DartSassTestCase {
    let scssIn = """
    div {
        a {
            color: blue;
        }
    }
    """
    let scssOutExpanded = """
    div a {
      color: blue;
    }
    """
    let scssOutCompressed = """
    div a{color:blue}
    """

    let sassIn = """
    $font-stack:    Helvetica, sans-serif
    $primary-color: #333

    body
      font: 100% $font-stack
      color: $primary-color
    """
    let sassOutExpanded = """
    body {
      font: 100% Helvetica, sans-serif;
      color: #333;
    }
    """

    /// Does it work, goodpath, no imports, scss/sass/css inline input
    func testCoreInline() throws {
        let compiler = try newCompiler()
        let results1 = try compiler.compile(string: scssIn, sourceMapStyle: .none)
        XCTAssertNil(results1.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertEqual(scssOutExpanded, results1.css)

        let results2 = try compiler.compile(string: sassIn, syntax: .sass, sourceMapStyle: .none)
        XCTAssertNil(results2.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertEqual(sassOutExpanded, results2.css)

        let results3 = try compiler.compile(string: sassOutExpanded, syntax: .css, sourceMapStyle: .none)
        XCTAssertNil(results3.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertEqual(sassOutExpanded, results3.css)
    }

    private func checkCompileFromFile(_ compiler: Compiler, extnsion: String, content: String, expected: String) throws {
        let url = try FileManager.default.createTempFile(filename: "file.\(extnsion)", contents: content)
        let results = try compiler.compile(fileURL: url)
        XCTAssertEqual(expected, results.css)
    }

    /// Does it work, from a file
    func testCoreFile() throws {
        let compiler = try newCompiler()
        try checkCompileFromFile(compiler, extnsion: "scss", content: scssIn, expected: scssOutExpanded)
        try checkCompileFromFile(compiler, extnsion: "sass", content: sassIn, expected: sassOutExpanded)
    }

    /// Is source map transmitted OK
    func testSourceMap() throws {
        let compiler = try newCompiler()

        // dart sass can't embed source map sources yet
        try [SourceMapStyle.separateSources, SourceMapStyle.embeddedSources].forEach { style in
            let results = try compiler.compile(string: scssIn, url: URL(string: "custom://bar"), sourceMapStyle: style)
            XCTAssertEqual(scssOutExpanded, results.css)

            let json = try XCTUnwrap(results.sourceMap)
            // Check we have a reasonable-looking source map, details don't matter
            let map = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String:Any]
            XCTAssertEqual(3, map["version"] as? Int)
            XCTAssertEqual("AACI;EACI", map["mappings"] as? String)
            let sources = try XCTUnwrap(map["sources"] as? Array<String>)
            XCTAssertEqual("custom://bar", sources[0])
        }
    }

    /// Is outputstyle enum translated OK
    func testOutputStyle() throws {
        let compiler = try newCompiler()

        // Current dart-sass-embedded maps everything !compressed down to expanded
        // so this is a bit scuffed...
        let styles: [CssStyle] = [.compressed, .compact, .nested]
        let expected = [scssOutCompressed, scssOutExpanded, scssOutExpanded]
        try zip(styles, expected).forEach { tc in
            let results = try compiler.compile(string: scssIn, syntax: .scss, outputStyle: tc.0)
            XCTAssertEqual(tc.1, results.css, String(describing: tc.0))
        }
    }

    /// Bad explicitly given compiler
    func testNotACompiler() throws {
        do {
            let notACompiler = URL(fileURLWithPath: "/tmp/fred")
            let compiler = Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
                                    embeddedCompilerFileURL: notACompiler)
            defer { try! compiler.syncShutdownGracefully() }
            let results = try compiler.compile(string: "")
            XCTFail("Got results: \(results)")
        } catch let error as LifecycleError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Missing from bundle/not a bundled platform
    func testBundleMissing() throws {
        putenv(strdup("DART_SASS_EMBEDDED_NAME=unreal")) /* leak it */
        defer { unsetenv("DART_SASS_EMBEDDED_NAME") }

        do {
            let compiler = try Compiler(eventLoopGroupProvider: .createNew)
            XCTFail("Created compiler without dart: \(compiler)")
        } catch let error as LifecycleError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
