//
//  TestCompilerErrors.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

//import XCTest
//import NIO
//@testable import DartSass
//
/////
///// Tests for compiler error decoding and transmission.
///// Plus warnings etc.
/////
//class TestCompilerErrors: DartSassTestCase {
//    let badSass = """
//    @mixin reflexive-position($property, $value)
//      @if $property != left and $property != right
//        @error "Property #{$property} must be either left or right."
//
//    .sidebar
//      @include reflexive-position(top, 12px)
//    """
//
//    let badSassInlineError = """
//    Error: "Property top must be either left or right."
//      ╷
//    6 │   @include reflexive-position(top, 12px)
//      │   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//      ╵
//      - 6:3  root stylesheet
//    """
//
//    let badSassFileErrorPrefix = """
//    Error: "Property top must be either left or right."
//      ╷
//    6 │   @include reflexive-position(top, 12px)
//      │   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//      ╵
//    """
//    let badSassFileErrorSuffix = """
//    badfile.sass 6:3  root stylesheet
//    """
//
//    func testCompilerErrorInline() throws {
//        let compiler = try newCompiler()
//        do {
//            let results = try compiler.compile(string: badSass, syntax: .sass)
//            XCTFail("Managed to compile, got: \(results.css)")
//        } catch let error as CompilerError {
//            XCTAssertEqual(badSassInlineError, error.description)
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//
//    func testCompilerErrorFile() throws {
//        let compiler = try newCompiler()
//        let url = try FileManager.default.createTempFile(filename: "badfile.sass", contents: badSass)
//        do {
//            let results = try compiler.compile(fileURL: url)
//            XCTFail("Managed to compile, got: \(results.css)")
//        } catch let error as CompilerError {
//            let d = error.description
//            // The sass stack trace includes the full path of the temp file
//            // so we can't test for it exactly
//            XCTAssertTrue(d.hasPrefix(badSassFileErrorPrefix))
//            XCTAssertTrue(d.hasSuffix(badSassFileErrorSuffix))
//            XCTAssertTrue(d.contains(url.path))
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//
//    let badSassInlineColorError = """
//    Error: "Property top must be either left or right."
//    \u{001b}[34m  ╷\u{001b}[0m
//    \u{001b}[34m6 │\u{001b}[0m   \u{001b}[31m@include reflexive-position(top, 12px)\u{001b}[0m
//    """
//
//    func testColorCompilerError() throws {
//        let compiler = try Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
//                                    messageStyle: .terminalColored)
//        compilersToShutdown.append(compiler)
//        do {
//            let results = try compiler.compile(string: badSass, syntax: .sass)
//            XCTFail("Managed to compile, got: \(results.css)")
//        } catch let error as CompilerError {
//            XCTAssertTrue(error.description.hasPrefix(badSassInlineColorError))
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//
//    // Compiler error without rich description, missing file
//    func testMissingFile() throws {
//        let compiler = try newCompiler()
//
//        do {
//            let results = try compiler.compile(fileURL: URL(fileURLWithPath: "/tmp/no"))
//            XCTFail("Managed to compile non-existant file: \(results)")
//        } catch let error as CompilerError {
//            XCTAssertEqual("Cannot open file: /tmp/no", String(describing: error))
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//
//    // Compiler warnings - no span
//
//    let warnsomeSass = """
//    $known-prefixes: webkit, moz, ms, o
//    @mixin prefix($property, $value, $prefixes)
//      @each $prefix in $prefixes
//        @if not index($known-prefixes, $prefix)
//          @warn "Unknown prefix #{$prefix}."
//
//        -#{$prefix}-#{$property}: $value
//
//      #{$property}: $value
//
//    .tilt
//      @include prefix(transform, rotate(15deg), wekbit ms)
//    """
//
//    let warningMessage = """
//    WARNING: Unknown prefix wekbit.
//        - 5:7   prefix()
//        - 12:3  root stylesheet
//
//    """
//
//    func testCompilerWarning() throws {
//        let compiler = try newCompiler()
//        let results = try compiler.compile(string: warnsomeSass, syntax: .sass)
//        XCTAssertEqual(1, results.messages.count)
//        XCTAssertTrue(results.messages[0].kind == .warning)
//        XCTAssertTrue(results.messages[0].message.contains("Unknown prefix"))
//        XCTAssertNil(results.messages[0].span)
//        XCTAssertEqual(warningMessage, results.messages[0].description)
//    }
//
//    let multiWarningSass = """
//    @warn "First warning"
//    @warn "Second warning"
//    @debug "Third debug"
//    """
//
//    // Multiple warnings
//    func testCompilerWarningMultiple() throws {
//        let compiler = try newCompiler()
//        let results = try compiler.compile(string: multiWarningSass, syntax: .sass)
//        XCTAssertEqual(3, results.messages.count)
//        print(results.messages)
//        results.messages[0...1].forEach { w in
//            XCTAssertEqual(.warning, w.kind)
//            XCTAssertTrue(w.message.contains("warning"))
//            XCTAssertNil(w.span)
//        }
//        XCTAssertEqual(.debug, results.messages[2].kind)
//        XCTAssertTrue(results.messages[2].message.contains("debug"))
//        XCTAssertNotNil(results.messages[2].span) // randomly...
//    }
//
//    let deprecatedScss = """
//    $my-list: () !default !global
//    """
//
//    // Deprecation warning
//    func testDeprecationWarning() throws {
//        let compiler = try newCompiler()
//        let results = try compiler.compile(string: deprecatedScss, syntax: .scss)
//        XCTAssertEqual("", results.css)
//        XCTAssertEqual(1, results.messages.count)
//        XCTAssertEqual(.deprecation, results.messages[0].kind)
//    }
//
//    let warningScssWithLocation = """
//    .label {
//      --#{blue}: 24;
//    }
//    """
//
//    // Warning with a span
//    func testWarningSpan() throws {
//        let compiler = try newCompiler()
//        let results = try compiler.compile(string: warningScssWithLocation, syntax: .scss)
//        XCTAssertEqual(1, results.messages.count)
//        XCTAssertEqual(.warning, results.messages[0].kind)
//        XCTAssertNotNil(results.messages[0].span)
//    }
//
//    let badWarningScss = """
//    .label {
//      --#{blue}: 24;
//    }
//    @error "Stop";
//    """
//
//    // Compiler error and a warning
//    func testErrorAndWarning() throws {
//        let compiler = try newCompiler()
//        do {
//            let results = try compiler.compile(string: badWarningScss, syntax: .scss)
//            XCTFail("Managed to compile nonsense: \(results)")
//        } catch let error as CompilerError {
//            print(error)
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//
//    // Dependency warning control
//    func testDependencyWarning() throws {
//        // warnings normally reported
//        let importer = StaticImporter(scss: "$_: 1/2")
//        let loudCompiler = try newCompiler(importers: [.importer(importer)])
//        let results1 = try loudCompiler.compile(string: "@import 'foo';")
//        XCTAssertEqual(1, results1.messages.count)
//
//        // warnings can be suppressed - from a file
//        let quietCompiler = try Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
//                                         suppressDependencyWarnings: true)
//        compilersToShutdown.append(quietCompiler)
//
//        let rootFile = try FileManager.default.createTempFile(filename: "root.scss", contents: "@import 'foo';")
//
//        let results2 = try quietCompiler.compile(fileURL: rootFile,
//                                                 importers: [.importer(importer)])
//        XCTAssertEqual(0, results2.messages.count)
//
//        // warnings can be suppressed - from a string
//        let results3 = try quietCompiler.compile(string: "@import 'imported';",
//                                                 url: URL(string: "custom://main.scss")!,
//                                                 importers: [.importer(importer)])
//        XCTAssertEqual(0, results3.messages.count)
//    }
//
//    // Deprecation warnings normally throttled
//    func testVerboseDeprecationWarnings() throws {
//        let importer = StaticImporter(scss: """
//                                            $_: 1/2;
//                                            $_: 1/3;
//                                            $_: 1/4;
//                                            $_: 1/5;
//                                            $_: 1/6;
//                                            $_: 1/7;
//                                            $_: 1/8;
//                                            """)
//        let normalCompiler = try newCompiler(importers: [.importer(importer)])
//        let results1 = try normalCompiler.compile(string: "@import 'foo';")
//        XCTAssertEqual(6, results1.messages.count)
//
//        let verboseCompiler = try Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
//                                           verboseDeprecations: true,
//                                           importers: [.importer(importer)])
//        compilersToShutdown.append(verboseCompiler)
//
//        let results2 = try verboseCompiler.compile(string: "@import 'foo';")
//        XCTAssertEqual(7, results2.messages.count)
//    }
//}
//
//final class StaticImporter: Importer {
//    private let scss: String
//
//    init(scss: String) {
//        self.scss = scss
//    }
//
//    func canonicalize(ruleURL: String, fromImport: Bool) async throws -> URL? {
//        URL(string: "static://\(ruleURL)")
//    }
//
//    func load(canonicalURL: URL) async throws -> ImporterResults? {
//        ImporterResults(scss)
//    }
//}
