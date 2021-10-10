//
//  TestCalculation.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import Sass

/// Calculations
class TestCalculation: XCTestCase {

    // Not actually a lot here!

    func testCreation() {
        let calc = SassCalculation(calc: .number(22, unit: "px"))
        XCTAssertEqual(calc.kind, .calc)
        XCTAssertEqual(1, calc.arguments.count)
        XCTAssertEqual("calc(22px)", calc.sassDescription)
        XCTAssertEqual("Calculation(calc(22px))", calc.description)
    }

    func testPrecedence() {
        let lhs: SassCalculation.Value = .operation(.number(2), .times, .number(3))
        let rhs: SassCalculation.Value = .operation(.number(4), .plus, .number(5))
        let calc = SassCalculation(calc: .operation(lhs, .dividedBy, rhs))
        XCTAssertEqual("calc(2 * 3 / (4 + 5))", calc.sassDescription)
    }

    func testUnusualTerms() {
        let calc = SassCalculation(calc: .calculation(SassCalculation(calc: .operation(.string("$fred"), .minus, .interpolation("$barney")))))
        XCTAssertEqual("calc(calc($fred - #{$barney}))", calc.sassDescription)
    }

    func testIdentity() throws {
        let calc1 = SassCalculation(kind: .max, arguments: [.string("$fred"), .string("$barney")])
        let calc2 = SassCalculation(kind: .min, arguments: [.string("$fred"), .string("$barney")])

        XCTAssertNotEqual(calc1, calc2)
        let value: SassValue = calc1
        XCTAssertNoThrow(try value.asCalculation())
        let str = SassString("Not a calculation")
        XCTAssertThrowsError(try str.asCalculation())

        let calc3 = SassCalculation(kind: .min, arguments: [.string("$fred"), .string("$barney")])
        XCTAssertEqual(calc2, calc3)

        let dict = [calc2 : true]
        XCTAssertTrue(try XCTUnwrap(dict[calc3]))
        XCTAssertNil(dict[calc1])
    }
}
