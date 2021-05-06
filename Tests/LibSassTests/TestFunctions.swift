//
//  TestFunctions.swift
//  LibSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import TestHelpers
@testable import LibSass
import CLibSass4

/// Custom functions, libsass-style.
/// Most of this is validating the round-tripping between our types and libsass.
class TestFunctions: XCTestCase {
    override func tearDown() { LibSass4.dumpMemLeaks() }

    let functions: SassFunctionMap = [
        "myEcho($param)" : { args in
            return args[0]
        },
        "myAdd($a, $b)" : { args in
            return SassNumber(try args[0].asNumber().double + args[1].asNumber().double)
        }
    ]

    func testEcho() throws {
        let compiler = Compiler()
        let results = try compiler.compile(string: "a { b: myEcho((frederick, 22)) }",
                                           outputStyle: .compressed,
                                           functions: functions)
        XCTAssertEqual("a{b:frederick,22}\n", results.css)

        let results2 = try compiler.compile(string: "a { b: myAdd(100, 25) }",
                                            outputStyle: .compressed,
                                            functions: functions)
        XCTAssertEqual("a{b:125}\n", results2.css)
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
        let compiler = Compiler(functions: globalOverrideFunction)

        let results = try compiler.compile(string: "a { a: ofunc() }", outputStyle: .compressed, functions: localOverrideFunction)
        XCTAssertEqual("a{a:\"goat\"}\n", results.css)
    }

    // error reporting
    func testErrorReporting() throws {
        struct Error: Swift.Error {}
        let compiler = Compiler(functions: ["badFunction()" : { _ in throw Error() }])
        do {
            let results = try compiler.compile(string: "a { a: badFunction() }")
            XCTFail("Compiled: \(results)")
        } catch let error as CompilerError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // conversions

    private func checkRoundTrip(_ vals: [SassValue]) throws {
        try vals.forEach {
            let libSassVal = try $0.toLibSassValue()
            let backVal = try libSassVal.toSassValue()
            XCTAssertEqual($0, backVal)
        }
    }

    func testConstants() throws {
        try checkRoundTrip([SassConstants.true, SassConstants.false, SassConstants.null])
    }

    func testString() throws {
        try checkRoundTrip([
            SassString("aString"),
            SassString("unquoted", isQuoted: false),
            SassString("quoted", isQuoted: true)
        ])
    }

    func testNumbers() throws {
        try checkRoundTrip([
            SassNumber(42),
            SassNumber(-102.88),
            SassNumber(100, numeratorUnits: ["px"]),
            SassNumber(100, denominatorUnits: ["px"]),
            SassNumber(100, numeratorUnits: ["px", "ms"], denominatorUnits: ["deg", "fish"])
        ])
    }

    func testColors() throws {
        try checkRoundTrip([
            SassColor(red: 1, green: 2, blue: 3, alpha: 0.26),
            SassColor(red: 220, green: 80, blue: 150),
            SassColor(hue: 25, saturation: 30, lightness: 80)
        ])
    }

    func testList() throws {
        let list1: [SassValue] = [
            SassNumber(100),
            SassString("bucket"),
            SassConstants.true
        ]
        let list2: [SassValue] = [
            try SassColor(red: 100, green: 150, blue: 200, alpha: 0.8),
            SassList(list1),
            SassConstants.null
        ]
        try checkRoundTrip([
            SassList([]),
            SassList(list1),
            SassList(list1, separator: .comma, hasBrackets: false),
            SassList([SassConstants.false], separator: .undecided, hasBrackets: true),
            SassList(list2)
        ])

        try XCTAssertThrowsError(SassList.Separator.slash.toLibSass())
        try XCTAssertThrowsError(SassSeparator(108).toSeparator())
    }

    func testMap() throws {
        try checkRoundTrip([
            SassMap([:]),
            SassMap([SassNumber(20) : SassString("fish"),
                     SassNumber(44) : SassString("bucket")])
        ])
    }

    // compiler functions
    func testSassCompilerFunction() throws {
        let echoFunc: SassFunction = { args in
            XCTAssertEqual(1, args.count)
            let funcVal = try args[0].asCompilerFunction()
            return funcVal
        }

        let scss = """
        @use "sass:meta";

        @function something() {
          @return "something";
        }

        @function something_else() {
          $s_fn: meta.get-function("something");
          $h_fn: hostEcho($s_fn);
          @return meta.call($h_fn);
        }

        a {
          b: something_else();
        }
        """

        let compiler = Compiler(functions: [
            "hostEcho($param)" : echoFunc
        ])
        let results = try compiler.compile(string: scss, outputStyle: .compressed)
        XCTAssertEqual("a{b:\"something\"}\n", results.css)
    }

    // misc corners
    func testMiscErrors() throws {
        try XCTAssertThrowsError(LibSass4.Value(error: "An error").toSassValue())
        try XCTAssertThrowsError(SassDynamicFunction(signature: "echo()", function: { _ in SassConstants.null}).toLibSassValue())
    }
}

