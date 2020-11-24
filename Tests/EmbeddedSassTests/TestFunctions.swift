//
//  TestFunctions.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import EmbeddedSass

///
/// Tests for custom functions.
///  - SassTests covers the base `SassValue` hierarchy.
///  - We don't need to test the compiler's implementation of this flow, just our side.
class TestFunctions: XCTestCase {

    // (String) values go back and forth

    let quoteStringFunction: SassFunctionMap = [
        "myQuoteString($param)" : { args in
            let str = try args[0].asString()
            return SassString(str.text, isQuoted: true)
        }
    ]

    func testEcho() throws {
        let compiler = try TestUtils.newCompiler(functions: quoteStringFunction)

        try [#"fish"#, #""fish""#].forEach {
            let results = try compiler.compile(text: "a { a: myQuoteString(\($0)) }", outputStyle: .compressed)
            XCTAssertEqual(#"a{a:"fish"}"#, results.css)
        }
    }

    // Local func overrides global

    let globalOverrideFunction: SassFunctionMap = [
        "ofunc($param)" : { _ in
            return SassString("bucket")
        }
    ]

    let localOverrideFunction: SassFunctionMap = [
        "ofunc()" : { _ in
            return SassString("goat")
        }
    ]

    func testOverride() throws {
        let compiler = try TestUtils.newCompiler(functions: globalOverrideFunction)

        let results = try compiler.compile(text: "a { a: ofunc() }", outputStyle: .compressed, functions: localOverrideFunction)
        XCTAssertEqual(#"a{a:"goat"}"#, results.css)
    }
}
