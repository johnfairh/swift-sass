//
//  TestFunctions.swift
//  SassLibSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import TestHelpers
@testable import SassLibSass

/// Custom functions, libsass-style.
/// Most of this is validating the round-tripping between our types and libsass.
class TestFunctions: XCTestCase {

    let echoFunction: SassFunctionMap = [
        "myEcho($param)" : { args in
            return args[0]
        }
    ]

    func testEcho() throws {
        let compiler = Compiler()
        let results = try compiler.compile(string: "a { b: myEcho(frederick) }",
                                           outputStyle: .compressed,
                                           functions: echoFunction)
        XCTAssertEqual("a{b:frederick}\n", results.css)
    }

    private func checkRoundTrip(_ vals: [SassValue]) throws {
        try vals.forEach {
            let libSassVal = try $0.asLibSassValue()
            let backVal = try libSassVal.asSassValue()
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
}

