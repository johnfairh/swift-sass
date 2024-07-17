//
//  TestInterface.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import XCTest
import DartSass
import SourceMapper

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

    /// Dumb test that we can create and shut down, typically does an early version-cancel
    func testNil() async throws {
        let _ = try newCompiler()
    }

    /// Does it work, goodpath, no imports, scss/sass/css inline input
    func testCoreInline() async throws {
        let compiler = try newCompiler()
        let results1 = try await compiler.compile(string: scssIn, sourceMapStyle: .none)
        XCTAssertNil(results1.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertTrue(results1.loadedURLs.isEmpty)
        XCTAssertEqual(scssOutExpanded, results1.css)

        let results2 = try await compiler.compile(string: sassIn, syntax: .sass, sourceMapStyle: .none)
        XCTAssertNil(results2.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertTrue(results1.loadedURLs.isEmpty)
        XCTAssertEqual(sassOutExpanded, results2.css)

        let results3 = try await compiler.compile(string: sassOutExpanded, syntax: .css, sourceMapStyle: .none)
        XCTAssertNil(results3.sourceMap)
        XCTAssertTrue(results1.messages.isEmpty)
        XCTAssertTrue(results1.loadedURLs.isEmpty)
        XCTAssertEqual(sassOutExpanded, results3.css)
    }

    private func checkCompileFromFile(_ compiler: Compiler, extnsion: String, content: String, expected: String) async throws {
        let url = try FileManager.default.createTempFile(filename: "file.\(extnsion)", contents: content)
        let results = try await compiler.compile(fileURL: url)
        XCTAssertEqual(expected, results.css)
        XCTAssertEqual(1, results.loadedURLs.count)
        XCTAssertEqual(url, results.loadedURLs[0])
    }

    /// Does it work, from a file
    func testCoreFile() async throws {
        let compiler = try newCompiler()
        try await checkCompileFromFile(compiler, extnsion: "scss", content: scssIn, expected: scssOutExpanded)
        try await checkCompileFromFile(compiler, extnsion: "sass", content: sassIn, expected: sassOutExpanded)
    }

    /// Is source map transmitted OK
    func testSourceMap() async throws {
        let compiler = try newCompiler()

        for style in [SourceMapStyle.separateSources, SourceMapStyle.embeddedSources] {
            let results = try await compiler.compile(string: scssIn, url: URL(string: "custom://bar"), sourceMapStyle: style)
            XCTAssertEqual(scssOutExpanded, results.css)
            XCTAssertEqual(1, results.loadedURLs.count)
            XCTAssertEqual("custom://bar", results.loadedURLs.first?.absoluteString)

            let srcmap = try SourceMap(XCTUnwrap(results.sourceMap))
            XCTAssertEqual(SourceMap.VERSION, srcmap.version)
            XCTAssertEqual("AACI;EACI", srcmap.mappings)
            XCTAssertEqual(1, srcmap.sources.count)
            XCTAssertEqual("custom://bar", srcmap.sources[0].url)

            switch style {
            case .separateSources:
                XCTAssertNil(srcmap.sources[0].content)
            case .embeddedSources:
                XCTAssertEqual(scssIn, try XCTUnwrap(srcmap.sources[0].content))
            case .none:
                XCTFail("swift is dumb")
            }
        }
    }

    /// Is outputstyle enum translated OK
    func testOutputStyle() async throws {
        let compiler = try newCompiler()

        // Current dart-sass-embedded maps everything !compressed down to expanded
        // so this is a bit scuffed...
        let styles: [CssStyle] = [.compressed, .compact, .nested]
        let expected = [scssOutCompressed, scssOutExpanded, scssOutExpanded]
        for tc in zip(styles, expected) {
            let results = try await compiler.compile(string: scssIn, syntax: .scss, outputStyle: tc.0)
            XCTAssertEqual(tc.1, results.css, String(describing: tc.0))
        }
    }

    // Check it can actually do stuff if we throw it parallel work
    func testParallel() async throws {
        let compiler = try newCompiler()

        let results = try await withThrowingTaskGroup(of: CompilerResults.self) { group in
            let scssIn = self.scssIn
            for _ in 1...8 {
                group.addTask { try await compiler.compile(string: scssIn) }
            }

            var collected = [CompilerResults]()
            for try await value in group {
                collected.append(value)
            }

            return collected
        }
        XCTAssertEqual(8, results.count)
    }

    /// Bad explicitly given compiler
    func testNotACompiler() async throws {
        let notACompiler = URL(fileURLWithPath: "/tmp/fred")
        let compiler = Compiler(embeddedCompilerFileURL: notACompiler)
        compilersToShutdown.append(compiler)
        do {
            let results = try await compiler.compile(string: "")
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
            let compiler = try Compiler()
            XCTFail("Created compiler without dart: \(compiler)")
        } catch let error as LifecycleError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Charset flag
    func testCharset() async throws {
        let compiler = try newCompiler()

        let ascii = try await compiler.compile(string: #"a { color: "red"} "#, includeCharset: true)
        XCTAssertFalse(ascii.css.starts(with: #"@charset "UTF-8""#))

        let utf8 = try await compiler.compile(string: #"a { color: "😀"} "#, includeCharset: true)
        XCTAssertTrue(utf8.css.starts(with: #"@charset "UTF-8""#))
    }

    /// Deprecation control
    func testDeprecationControl() async throws {
        let deprecatedScss = """
        @function mangle($num) {
          @return $num / 1;
        }

        .a {
          height: mangle(100);
        }
        """

        // Deprecation
        let compiler1 = try newCompiler()
        let results1 = try await compiler1.compile(string: deprecatedScss)
        XCTAssertEqual(1, results1.messages.count)
        let msg = try XCTUnwrap(results1.messages.first)

        XCTAssertEqual(msg.kind, CompilerMessage.Kind.deprecation)
        let msgID = try XCTUnwrap(msg.messageID)
        XCTAssertEqual(msgID, Deprecation.ID.slashDiv.rawValue)
        XCTAssertEqual(Deprecation(msgID), .id(.slashDiv))

        // Silence
        let compiler2 = try newCompiler(deprecationControl: DeprecationControl(silenced: [.id(.slashDiv)]))
        let results2 = try await compiler2.compile(string: deprecatedScss)
        XCTAssertEqual(0, results2.messages.count)

        // Fatal
        do {
            let compiler3 = try newCompiler(deprecationControl: DeprecationControl(fatal: [.id(.slashDiv)]))
            let results3 = try await compiler3.compile(string: deprecatedScss)
            XCTFail("Unexpected success: \(results3)")
        } catch let error as CompilerError {
            XCTAssertEqual(0, error.messages.count)
            XCTAssertTrue(error.message.contains("Using / for division"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // XXX add a test for by-version when the build works again...
    }

    /// Deprecation control - type round-trip
    func testDeprecationStringRoundTrip() {
        func check(_ string: String, _ deprecation: Deprecation) {
            let dep = Deprecation(string)
            XCTAssertEqual(deprecation, dep)
            let str = dep.description
            XCTAssertEqual(string, str)
        }

        check("moz-document", .id(.mozDocument))
        check("weird", .custom("weird"))
        check("1.2.3", .version("1.2.3"))
    }
}
