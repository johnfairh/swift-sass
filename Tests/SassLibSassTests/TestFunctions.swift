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
            SassList(list2)
        ])
    }

    func testMap() throws {
        try checkRoundTrip([
            SassMap([:]),
            SassMap([SassNumber(20) : SassString("fish"),
                     SassNumber(44) : SassString("bucket")])
        ])
    }
}

