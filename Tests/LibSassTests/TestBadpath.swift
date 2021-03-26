//
//  TestBadpath.swift
//  LibSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import TestHelpers
import LibSass

/// Compiler errors and warnings
class TestBadpath: XCTestCase {
    let badSass = """
    @mixin reflexive-position($property, $value)
      @if $property != left and $property != right
        @error "Property #{$property} must be either left or right."

    .sidebar
      @include reflexive-position(top, 12px)
    """

    let badSassError = """
    Error: "Property top must be either left or right."
      ,
    3 |     @error "Property #{$property} must be either left or right."
      |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      '
      file.sass 3:5  reflexive-position()
      ,
    6 |   @include reflexive-position(top, 12px)
      |   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      '
      file.sass 6:3  root stylesheet


    """

    // this seems to come out a bit weirdly but is low priority to understand
    let badSassStackTrace = """
    CWD/file.sass 3:5
    CWD/file.sass 6:3 reflexive-position
    """

    func testCompilerError() throws {
        let compiler = Compiler()
        do {
            let results = try compiler.compile(string: badSass, syntax: .sass, fileURL: URL(fileURLWithPath: "file.sass"))
            XCTFail("Managed to compile, got: \(results.css)")
        } catch let error as CompilerError {
            XCTAssertTrue(error.message.isEmpty) // This is a libsass bug
            let span = try XCTUnwrap(error.span)
            XCTAssertEqual(3, span.start.line)
            XCTAssertEqual(5, span.start.column)
            XCTAssertNil(span.end)
            XCTAssertNil(span.context)
            XCTAssertNil(span.text)
            XCTAssertEqual(badSassError, error.description)
            let url = try XCTUnwrap(span.url)
            XCTAssertEqual("\(FileManager.default.currentDirectoryPath)/file.sass", url.path)
            let trace = try XCTUnwrap(error.stackTrace)
            let badTrace = badSassStackTrace.replacingOccurrences(of: "CWD", with: FileManager.default.currentDirectoryPath)
            XCTAssertEqual(badTrace, trace)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOsError() throws {
        let compiler = Compiler()
        do {
            let results = try compiler.compile(fileURL: URL(fileURLWithPath: "/tmp/does_not_exist.scss"))
            XCTFail("Managed to compile, got: \(results.css)")
        } catch let error as CompilerError {
            let span = try XCTUnwrap(error.span)
            XCTAssertNil(span.url)
            XCTAssertTrue(error.message.isEmpty) // Probably a bug
            XCTAssertEqual("Error: File to read not found or unreadable.\n", error.description)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    let badSassInlineColorError = """
    Error: "Property top must be either left or right."
    \u{001b}[34m  ╷\u{001b}[0m
    \u{001b}[34m6 │\u{001b}[0m   \u{001b}[31m@include reflexive-position(top, 12px)\u{001b}[0m
    """

    func testColorCompilerError() throws {
        let compiler = Compiler(messageStyle: .terminalColored)
        do {
            let results = try compiler.compile(string: badSass, syntax: .sass, fileURL: URL(fileURLWithPath: "file.sass"))
            XCTFail("Managed to compile, got: \(results.css)")
        } catch let error as CompilerError {
            XCTAssertEqual(badSassError, error.description) // This is a libsass bug
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

    let warningMessage = """
    WARNING: Unknown prefix wekbit.\(" ")
        file.sass 5:7   prefix()
        file.sass 12:3  root stylesheet

    """

    func testCompilerWarning() throws {
        let compiler = Compiler()
        let results = try compiler.compile(string: warnsomeSass, syntax: .sass, fileURL: URL(fileURLWithPath: "file.sass"))
        XCTAssertEqual(1, results.messages.count)
        XCTAssertTrue(results.messages[0].kind == .warning)
        XCTAssertTrue(results.messages[0].message.contains("Unknown prefix"))
        XCTAssertNil(results.messages[0].span)
        XCTAssertEqual(warningMessage, results.messages[0].description)
    }

    let multiWarningSass = """
    @warn "First warning"
    @warn "Second warning"
    @debug "Third debug"
    """

    // Multiple warnings
    func testCompilerWarningMultiple() throws {
        let compiler = Compiler()
        let results = try compiler.compile(string: multiWarningSass, syntax: .sass, fileURL: URL(fileURLWithPath: "file.sass"))
        XCTAssertEqual(3, results.messages.count)
        results.messages[0...1].forEach { w in
            XCTAssertEqual(.warning, w.kind)
            XCTAssertTrue(w.message.contains("warning"))
            XCTAssertNil(w.span)
        }
        XCTAssertEqual(.debug, results.messages[2].kind)
        XCTAssertTrue(results.messages[2].message.contains("debug"))
        XCTAssertNil(results.messages[2].span)
    }

    let deprecatedScss = """
    $my-list: () !default !global
    """

    // Deprecation warning
    func testDeprecationWarning() throws {
        let compiler = Compiler()
        let results = try compiler.compile(string: deprecatedScss, syntax: .scss)
        XCTAssertEqual("", results.css)
        XCTAssertEqual(1, results.messages.count)
        XCTAssertEqual(.deprecation, results.messages[0].kind)
    }

    let badWarningScss = """
    @warn "Warning";
    @error "Stop";
    """

    // Compiler error and a warning
    func testErrorAndWarning() throws {
        let compiler = Compiler()
        do {
            let results = try compiler.compile(string: badWarningScss, syntax: .scss)
            XCTFail("Managed to compile nonsense: \(results)")
        } catch let error as CompilerError {
            XCTAssertEqual(1, error.messages.count)
            XCTAssertEqual(.warning, error.messages[0].kind)
            XCTAssertTrue(error.description.contains("Stop"))
            XCTAssertEqual("", error.message) // libsass bug
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
