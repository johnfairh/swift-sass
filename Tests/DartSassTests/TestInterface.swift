//
//  TestCompiler.swift
//  DartSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

import XCTest
import DartSass

///
/// Tests to check the normal operation of the sass compiler -- not testing the compiler itself,
/// just that we can talk to it honestly and translate enums etc. properly.
///
class TestCompiler: XCTestCase {

    var newCompiler: Compiler {
        try! Compiler(embeddedDartSass: TestUtils.dartSassEmbeddedURL)
    }

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
        let compiler = newCompiler

        let results1 = try compiler.compile(sourceText: scssIn)
        XCTAssertNil(results1.sourceMap)
        XCTAssertEqual(scssOutExpanded, results1.css)

        let results2 = try compiler.compile(sourceText: sassIn, sourceSyntax: .sass)
        XCTAssertNil(results2.sourceMap)
        XCTAssertEqual(sassOutExpanded, results2.css)

        let results3 = try compiler.compile(sourceText: sassOutExpanded, sourceSyntax: .css)
        XCTAssertNil(results3.sourceMap)
        XCTAssertEqual(sassOutExpanded, results3.css)
    }

    func testSourceMap() throws {
        let compiler = newCompiler
        let results = try compiler.compile(sourceText: scssIn, createSourceMap: true)
        XCTAssertEqual(scssOutExpanded, results.css)
        let json = try XCTUnwrap(results.sourceMap)
        // Check we have a reasonable-looking source map, details don't matter
        let map = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String:Any]
        XCTAssertEqual(3, map["version"] as? Int)
        XCTAssertEqual("AACI;EACI", map["mappings"] as? String)
    }
}
