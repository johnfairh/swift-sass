//
//  TestErrors.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
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
            let results = try compiler.compile(sourceText: badSass, sourceSyntax: .sass)
            XCTFail("Managed to compile, got: \(results.css)")
        } catch let error as Sass.CompilerError {
            XCTAssertEqual(badSassInlineError, error.description)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCompilerErrorFile() throws {
        let compiler = try TestUtils.newCompiler()
        let url = try TestUtils.tempFile(filename: "badfile.sass", contents: badSass)
        do {
            let results = try compiler.compile(sourceFileURL: url)
            XCTFail("Managed to compile, got: \(results.css)")
        } catch let error as Sass.CompilerError {
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

    // Deal with missing child & SIGPIPE-avoidance measures
    func testChildTermination() throws {
        let compiler = try TestUtils.newCompiler()
        kill(compiler.compilerProcessIdentifier, SIGTERM)
        do {
            let results = try compiler.compile(sourceText: "")
            XCTFail("Managed to compile with dead compiler: \(results)")
        } catch let error as ProtocolError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // check recovered
        let results = try compiler.compile(sourceText: "")
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
        do {
            let results = try compiler.compile(sourceText: "")
            XCTFail("Managed to compile with weird message: \(results)")
        } catch let error as ProtocolError {
            print(error)
            XCTAssertTrue(error.description.contains("108"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // check compiler is now working OK
        let results = try compiler.compile(sourceText: "")
        XCTAssertEqual("", results.css)
    }

    // If this were a real/critical product I'd write a badly-behaved Sass
    // compiler to explore all the protocol errors, timeouts, etc.
}
