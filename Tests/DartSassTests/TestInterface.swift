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

    func newCompiler() throws -> Compiler {
        let c = try Compiler(embeddedCompilerURL: TestUtils.dartSassEmbeddedURL)
        c.debugHandler = { m in print(m) }
        return c
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

    private func checkCompileFromFile(_ compiler: Compiler, extnsion: String, content: String, expected: String) throws {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("file.\(extnsion)")
        try content.write(toFile: tmpFile.path, atomically: false, encoding: .utf8)
        let results = try compiler.compile(sourceFileURL: tmpFile)
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

        let results = try compiler.compile(sourceText: scssIn, createSourceMap: true)
        XCTAssertEqual(scssOutExpanded, results.css)

        let json = try XCTUnwrap(results.sourceMap)
        // Check we have a reasonable-looking source map, details don't matter
        let map = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String:Any]
        XCTAssertEqual(3, map["version"] as? Int)
        XCTAssertEqual("AACI;EACI", map["mappings"] as? String)
    }

    /// Is outputstyle enum translated OK
    func testOutputStyle() throws {
        let compiler = try newCompiler()

        // Current dart-sass-embedded maps everything !compressed down to nested
        // so this is a bit scuffed...
        let styles: [Sass.OutputStyle] = [.compact, .compressed, .nested]
        let expected = [scssOutExpanded, scssOutCompressed, scssOutExpanded]
        try zip(styles, expected).forEach { tc in
            let results = try compiler.compile(sourceText: scssIn, sourceSyntax: .scss, outputStyle: tc.0)
            XCTAssertEqual(tc.1, results.css, String(describing: tc.0))
        }
    }

    /// Can we search PATH properly
    func testCompilerSearch() throws {
        do {
            let compiler = try Compiler(embeddedCompilerName: "not-a-compiler")
            XCTFail("Created a weird compiler \(compiler)")
        } catch let error as ProtocolError {
            print(error.text)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // omg don't @ me
        let oldPATH = strdup(getenv("PATH"))
        let oldPATHString = String(cString: oldPATH!)
        defer { setenv("PATH", oldPATH!, 1) }
        let newPATH = "\(TestUtils.dartSassEmbeddedDirURL.path):\(oldPATHString)"
        setenv("PATH", strdup(newPATH), 1)
        let compiler = try Compiler(embeddedCompilerName: "dart-sass-embedded")
        let results = try compiler.compile(sourceText: "")
        XCTAssertEqual("", results.css)
    }
}
