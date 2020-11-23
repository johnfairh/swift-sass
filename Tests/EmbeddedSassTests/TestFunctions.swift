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

    var functionList: SassFunctionMap = [
        "myQuoteString($param)" : { args in
            let str = try args[0].asString()
            return SassString(str.text, isQuoted: true)
        }
    ]

    func testEcho() throws {
        let compiler = try TestUtils.newCompiler(functions: functionList)

        try [#"fish"#, #""fish""#].forEach {
            let results = try compiler.compile(text: "a { a: myQuoteString(\($0)) }", outputStyle: .compressed)
            XCTAssertEqual(results.css, #"a{a:"fish"}"#)
        }
    }
}
