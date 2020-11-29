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
            return SassString(str.string, isQuoted: true)
        }
    ]

    func testEcho() throws {
        let compiler = try TestUtils.newCompiler(functions: quoteStringFunction)

        try [#"fish"#, #""fish""#].forEach {
            let results = try compiler.compile(text: "a { a: myQuoteString(\($0)) }", outputStyle: .compressed)
            XCTAssertEqual(#"a{a:"fish"}"#, results.css)
        }
    }

    // Errors reported

    let errorFunction: SassFunctionMap = [
        "badFunction($param)" : { args in
            let bool = try args[0].asBool()
            XCTFail("Managed to get a bool")
            return SassConstants.null
        }
    ]

    func testError() throws {
        let compiler = try TestUtils.newCompiler(functions: errorFunction)

        do {
            let results = try compiler.compile(text: "$data: badFunction('22');")
            XCTFail("Managed to compile nonsense: \(results)")
        } catch let error as CompilerError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
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

    /// SassMap conversion
    func testSassMapConversion() throws {
        let map = SassMap(uniqueKeysWithValues: [
            (SassConstants.true, SassString("str1")),
            (SassConstants.false, SassString("str2"))
        ])
        let pbVal = Sass_EmbeddedProtocol_Value(map)
        let backMap = try pbVal.asSassValue()
        XCTAssertEqual(map, backMap)

        // Dodgy map from the compiler
        var badPbVal = Sass_EmbeddedProtocol_Value()
        badPbVal.map = .with {
            $0.entries = [
                .with { ent in
                    ent.key = .init(SassConstants.true)
                    ent.value = .init(SassConstants.null)
                },
                .with { ent in
                    ent.key = .init(SassConstants.true)
                    ent.value = .init(SassConstants.null)
                }
            ]
        }
        XCTAssertThrowsError(try badPbVal.asSassValue())
    }

    /// SassNumber conversion
    func testSassNumberConversion() throws {
        let num = SassNumber(Double.pi)
        let pbVal = Sass_EmbeddedProtocol_Value(num)
        let backNum = try pbVal.asSassValue()
        XCTAssertEqual(num, backNum)

        let num2 = try SassNumber(76, numeratorUnits: ["trombone"], denominatorUnits: ["s"])
        let pbVal2 = Sass_EmbeddedProtocol_Value(num2)
        let backNum2 = try pbVal2.asSassValue()
        XCTAssertEqual(num2, backNum2)
    }
}
