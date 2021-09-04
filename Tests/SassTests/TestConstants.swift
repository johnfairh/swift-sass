//
//  TestConstants.swift
//  SassTests
//
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

    func testSingletonListiness() {
        let nullVal = SassConstants.null
        let goodIndex1 = SassNumber(1)
        let goodIndex2 = SassNumber(-1)
        let badIndex1 = SassNumber(0)
        let badIndex2 = SassNumber(-5)

        XCTAssertEqual(0, try nullVal.arrayIndexFrom(sassIndex: goodIndex1))
        XCTAssertEqual(0, try nullVal.arrayIndexFrom(sassIndex: goodIndex2))
        XCTAssertEqual(nullVal, try nullVal.valueAt(sassIndex: goodIndex1))
        XCTAssertThrowsError(try nullVal.arrayIndexFrom(sassIndex: badIndex1))
        do {
            _ = try nullVal.arrayIndexFrom(sassIndex: badIndex2)
            XCTFail("Mad bad index")
        } catch {
            print(error)
        }
    }
}
