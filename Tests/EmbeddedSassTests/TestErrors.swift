//
//  TestErrors.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import XCTest
@testable import EmbeddedSass

///
/// Tests for compiler error decoding and transmission.
/// Plus warnings; plus protocol errors
///
class TestErrors: XCTestCase {
    let badSass = """
    @mixin reflexive-position($property, $value)
      @if $property != left and $property != right
        @error "Property #{$property} must be either left or right."

    .sidebar
      @include reflexive-position(top, 12px)
    """

    let badSassInlineError = """
    [input] 6:3-6:41: error: "Property top must be either left or right."
        - 6:3  root stylesheet
    """

    let badSassFileErrorPrefix = """
    badfile.sass 6:3-6:41: error: "Property top must be either left or right."
    """
    let badSassFileErrorSuffix = """
    badfile.sass 6:3  root stylesheet
    """

    func testCompilerErrorInline() throws {
        let compiler = try TestUtils.newCompiler()
        do {
            let results = try compiler.compile(text: badSass, syntax: .sass)
            XCTFail("Managed to compile, got: \(results.css)")
        } catch let error as CompilerError {
            XCTAssertEqual(badSassInlineError, error.description)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCompilerErrorFile() throws {
        let compiler = try TestUtils.newCompiler()
        let url = try FileManager.default.createTempFile(filename: "badfile.sass", contents: badSass)
        do {
            let results = try compiler.compile(fileURL: url)
            XCTFail("Managed to compile, got: \(results.css)")
        } catch let error as CompilerError {
            let d = error.description
            // The sass stack trace includes the full path of the temp file
            // so we can't test for it exactly
            XCTAssertTrue(d.hasPrefix(badSassFileErrorPrefix))
            XCTAssertTrue(d.hasSuffix(badSassFileErrorSuffix))
            XCTAssertTrue(d.contains(url.path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    let warnsomeSass = """
    $known-prefixes: webkit, moz, ms, o
    @mixin prefix($property, $value, $prefixes)
      @each $prefix in $prefixes
        @if not index($known-prefixes, $prefix)
          @warn "Unknown prefix #{$prefix}."

        -#{$prefix}-#{$property}: $value

      #{$property}: $value

    .tilt
      @include prefix(transform, rotate(15deg), wekbit ms)
    """

    // Compiler warnings - no span
    func testCompilerWarning() throws {
        let compiler = try TestUtils.newCompiler()
        let results = try compiler.compile(text: warnsomeSass, syntax: .sass)
        XCTAssertEqual(1, results.warnings.count)
        XCTAssertTrue(results.warnings[0].kind == .warning)
        XCTAssertTrue(results.warnings[0].message.contains("Unknown prefix"))
        XCTAssertNil(results.warnings[0].span)
    }

    let multiWarningSass = """
    @warn "First warning"
    @warn "Second warning"
    """

    // Multiple warnings
    func testCompilerWarningMultiple() throws {
        let compiler = try TestUtils.newCompiler()
        let results = try compiler.compile(text: multiWarningSass, syntax: .sass)
        XCTAssertEqual(2, results.warnings.count)
        print(results.warnings)
        results.warnings.forEach { w in
            XCTAssertEqual(.warning, w.kind)
            XCTAssertTrue(w.message.contains("warning"))
            XCTAssertNil(w.span)
        }
    }

    let deprecatedScss = """
    $my-list: () !default !global
    """

    // Deprecation warning
    func testDeprecationWarning() throws {
        let compiler = try TestUtils.newCompiler()
        let results = try compiler.compile(text: deprecatedScss, syntax: .scss)
        XCTAssertEqual("", results.css)
        XCTAssertEqual(1, results.warnings.count)
        XCTAssertEqual(.deprecation, results.warnings[0].kind)
    }

    let warningScssWithLocation = """
    .label {
      --#{blue}: 24;
    }
    """

    // Warning with a span
    func testWarningSpan() throws {
        let compiler = try TestUtils.newCompiler()
        let results = try compiler.compile(text: warningScssWithLocation, syntax: .scss)
        XCTAssertEqual(1, results.warnings.count)
        XCTAssertEqual(.warning, results.warnings[0].kind)
        XCTAssertNotNil(results.warnings[0].span)
    }

    let badWarningScss = """
    .label {
      --#{blue}: 24;
    }
    @error "Stop";
    """

    // Compiler error and a warning
    func testErrorAndWarning() throws {
        let compiler = try TestUtils.newCompiler()
        do {
            let results = try compiler.compile(text: badWarningScss, syntax: .scss)
            XCTFail("Managed to compile nonsense: \(results)")
        } catch let error as CompilerError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Helper to trigger & test a protocol error
    func checkProtocolError(_ compiler: Compiler, _ text: String? = nil) {
        do {
            let results = try compiler.compile(text: "")
            XCTFail("Managed to compile with compiler that should have failed: \(results)")
        } catch let error as ProtocolError {
            print(error)
            if let text = text {
                XCTAssertTrue(error.description.contains(text))
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Deal with missing child & SIGPIPE-avoidance measures
    func testChildTermination() throws {
        let compiler = try TestUtils.newCompiler()
        kill(compiler.compilerProcessIdentifier, SIGTERM)
        checkProtocolError(compiler)

        // check recovered
        let results = try compiler.compile(text: "")
        XCTAssertEqual("", results.css)
    }

    // Deal with in-band reported protocol error
    func testProtocolError() throws {
        let compiler = try TestUtils.newCompiler()
        let msg = Sass_EmbeddedProtocol_InboundMessage.with { msg in
            msg.importResponse = .with { rsp in
                rsp.id = 108
            }
        }
        try compiler.child.send(message: msg)
        checkProtocolError(compiler, "108")

        // check compiler is now working OK
        let results = try compiler.compile(text: "")
        XCTAssertEqual("", results.css)
    }

    // If this were a real/critical product I'd write a badly-behaved Sass
    // compiler to explore all the protocol errors, timeouts, etc.
    //
    // Instead, dumb timeout tests exercising the overall timeout path,
    // using tail(1) as a poor Sass compiler.

    // Check we detect stuck requests
    func testTimeout() throws {
        let badCompiler = try Compiler(embeddedCompilerURL: URL(fileURLWithPath: "/usr/bin/tail"),
                                       overallTimeoutSeconds: 1)
        badCompiler.debugHandler = { m in print("debug: \(m)") }

        checkProtocolError(badCompiler, "Timeout")
    }

    // Test disabling the timeout works
    func testTimeoutDisabled() throws {
        let badCompiler = try Compiler(embeddedCompilerURL: URL(fileURLWithPath: "/usr/bin/tail"),
                                       overallTimeoutSeconds: -1)
        badCompiler.debugHandler = { m in print("debug: \(m)") }

        // TODO-NIO: make this less disgusting and more likely to pass TSAN

        Thread.detachNewThread {
            sleep(1)
            badCompiler.child.process.terminate()
        }
        checkProtocolError(badCompiler, "underran")
    }

    // Test the 'compiler will not restart' corner
    func testUnrestartableCompiler() throws {
        let tmpDir = try FileManager.default.createTemporaryDirectory()
        let realHeadURL = URL(fileURLWithPath: "/usr/bin/tail")
        let tmpHeadURL = tmpDir.appendingPathComponent("tail")
        try FileManager.default.copyItem(at: realHeadURL, to: tmpHeadURL)

        let badCompiler = try Compiler(embeddedCompilerURL: tmpHeadURL, overallTimeoutSeconds: 1)
        badCompiler.debugHandler = { m in print("debug: \(m)") }

        // it's now running using the copied program
        try FileManager.default.removeItem(at: tmpHeadURL)

        // Use the instance we have up, will timeout & be killed
        // ho hum, on GitHub Actions sometimes we get a pipe error instead
        // either is fine, as long as it fails somehow.
        checkProtocolError(badCompiler)

        // Should be in idle_broken, restart not possible
        checkProtocolError(badCompiler, "failed to restart")

        // Try to recover - no dice
        do {
            try badCompiler.reinit()
            XCTFail("Managed to reinit somehow")
        } catch let error as NSError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
