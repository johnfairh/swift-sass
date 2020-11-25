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

    // Corner error cases in Value conversion

    func testBadValueConversion() {
        let badValue1 = Sass_EmbeddedProtocol_Value()
        XCTAssertThrowsError(try badValue1.asSassValue())
    }

    /// SassList conversion
    func testSassListConversion() throws {
        // Round-trip
        let list = SassList([SassString("one")], separator: .slash)
        let value = Sass_EmbeddedProtocol_Value(list)
        let listBack = try value.asSassValue()
        XCTAssertEqual(list, listBack)

        // Tedious enum matching
        let separators: [(Sass_EmbeddedProtocol_Value.List.Separator,
                          SassList.Separator)] = [
                            (.comma, .comma),
                            (.slash, .slash),
                            (.space, .space),
                            (.undecided, .undecided)]
        try separators.forEach { pb, sw in
            XCTAssertEqual(pb, .init(sw))
            XCTAssertEqual(sw, try .init(pb))
        }

        // And the reason we have our own enum
        XCTAssertThrowsError(try SassList.Separator(.UNRECOGNIZED(1)))
    }

    /// SassConstant conversion
    func testSassConstantConversion() throws {
        try [SassConstants.true,
             SassConstants.false,
             SassConstants.null].forEach { sassVal in
            let pbVal = Sass_EmbeddedProtocol_Value(sassVal)
            let backVal = try pbVal.asSassValue()
            XCTAssertEqual(sassVal, backVal)
        }

        // Bad singleton value
        var value = Sass_EmbeddedProtocol_Value()
        value.singleton = .UNRECOGNIZED(2)
        XCTAssertThrowsError(try value.asSassValue())
    }
}
