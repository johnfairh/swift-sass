//
//  TestConstants.swift
//  SassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import Sass

/// Tests for `SassConstants`
///
class TestConstants: XCTestCase {
    func testBool() throws {
        let trueVal = SassConstants.true
        XCTAssertTrue(trueVal.isTruthy)
        XCTAssertFalse(trueVal.isNull)
        XCTAssertEqual(true, try trueVal.asBool().value)
        XCTAssertEqual(trueVal, trueVal)
        XCTAssertEqual("Bool(true)", trueVal.description)

        let falseVal = SassConstants.false
        XCTAssertFalse(falseVal.isTruthy)
        XCTAssertFalse(falseVal.isNull)
        XCTAssertEqual(false, try falseVal.asBool().value)
        XCTAssertEqual(falseVal, falseVal)
        XCTAssertEqual("Bool(false)", falseVal.description)

        XCTAssertNotEqual(trueVal, falseVal)

        var dict: [SassValue : Bool] = [:]
        dict[trueVal] = true
        dict[falseVal] = false
        XCTAssertTrue(dict[SassConstants.true]!)
        XCTAssertFalse(dict[SassConstants.false]!)

        XCTAssertThrowsError(try SassString("str").asBool())
    }

    func testNull() throws {
        let nullVal = SassConstants.null
        XCTAssertFalse(nullVal.isTruthy)
        XCTAssertTrue(nullVal.isNull)
        XCTAssertEqual(nullVal, nullVal)
        XCTAssertEqual("Null", nullVal.description)

        var dict: [SassValue: String] = [:]
        dict[nullVal] = "null"
        dict[SassConstants.true] = "true"
        dict[SassString("str")] = "str"
        XCTAssertEqual("null", dict[SassConstants.null])
    }
}
