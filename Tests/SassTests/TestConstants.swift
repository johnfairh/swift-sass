//
//  TestConstants.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Testing
import Sass

/// Tests for `SassConstants`
///
class TestConstants {
    @Test
    func testBool() throws {
        let trueVal = SassConstants.true
        #expect(trueVal.isTruthy)
        #expect(!trueVal.isNull)
        #expect(try true == trueVal.asBool().value)
        #expect(trueVal == trueVal)
        #expect("Bool(true)" == trueVal.description)

        let falseVal = SassConstants.false
        #expect(!falseVal.isTruthy)
        #expect(!falseVal.isNull)
        #expect(try false == falseVal.asBool().value)
        #expect(falseVal == falseVal)
        #expect("Bool(false)" == falseVal.description)

        #expect(trueVal != falseVal)

        var dict: [SassValue : Bool] = [:]
        dict[trueVal] = true
        dict[falseVal] = false
        #expect(dict[SassConstants.true]!)
        #expect(!dict[SassConstants.false]!)

        #expect(throws: SassFunctionError.self) {
           try SassString("str").asBool()
        }
    }

    @Test
    func testNull() throws {
        let nullVal = SassConstants.null
        #expect(!nullVal.isTruthy)
        #expect(nullVal.isNull)
        #expect(nullVal == nullVal)
        #expect("Null" == nullVal.description)

        var dict: [SassValue: String] = [:]
        dict[nullVal] = "null"
        dict[SassConstants.true] = "true"
        dict[SassString("str")] = "str"
        #expect("null" == dict[SassConstants.null])
    }

    @Test
    func testSingletonListiness() throws {
        let nullVal = SassConstants.null
        let goodIndex1 = SassNumber(1)
        let goodIndex2 = SassNumber(-1)
        let badIndex1 = SassNumber(0)
        let badIndex2 = SassNumber(-5)

        #expect(try 0 == nullVal.arrayIndexFrom(sassIndex: goodIndex1))
        #expect(try 0 == nullVal.arrayIndexFrom(sassIndex: goodIndex2))
        #expect(try nullVal == nullVal.valueAt(sassIndex: goodIndex1))

        #expect(throws: SassFunctionError.self) {
            try nullVal.arrayIndexFrom(sassIndex: badIndex1)
        }

        do {
            _ = try nullVal.arrayIndexFrom(sassIndex: badIndex2)
            Issue.record("Mad bad index")
        } catch {
            print(error)
        }
    }
}
