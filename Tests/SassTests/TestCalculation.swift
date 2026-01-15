//
//  TestCalculation.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Testing
@testable import Sass

/// Calculations
struct TestCalculation {

    // Not actually a lot here!

    @Test
    func testCreation() {
        let calc = SassCalculation(calc: .number(22, unit: "px"))
        #expect(calc.kind == .calc)
        #expect(1 == calc.arguments.count)
        #expect("calc(22px)" == calc.sassDescription)
        #expect("Calculation(calc(22px))" == calc.description)
    }

    @Test
    func testPrecedence() {
        let lhs: SassCalculation.Value = .operation(.number(2), .times, .number(3))
        let rhs: SassCalculation.Value = .operation(.number(4), .plus, .number(5))
        let calc = SassCalculation(calc: .operation(lhs, .dividedBy, rhs))
        #expect("calc(2 * 3 / (4 + 5))" == calc.sassDescription)
    }

    @Test
    func testUnusualTerms() {
        let calc = SassCalculation(calc: .calculation(SassCalculation(calc: .operation(.string("$fred"), .minus, .interpolation("$barney")))))
        #expect("calc(calc($fred - #{$barney}))" == calc.sassDescription)
    }

    @Test
    func testIdentity() throws {
        let calc1 = SassCalculation(kind: .max, arguments: [.string("$fred"), .string("$barney")])
        let calc2 = SassCalculation(kind: .min, arguments: [.string("$fred"), .string("$barney")])

        #expect(calc1 != calc2)
        let value: SassValue = calc1
        do { _ = try value.asCalculation() } catch { Issue.record("asCalculation threw unexpectedly: \(error)") }
        let str = SassString("Not a calculation")
        #expect(throws: Error.self) { _ = try str.asCalculation() }

        let calc3 = SassCalculation(kind: .min, arguments: [.string("$fred"), .string("$barney")])
        #expect(calc2 == calc3)

        let dict = [calc2 : true]
        let unwrapped = try #require(dict[calc3] as Bool?)
        #expect(unwrapped)
        #expect(dict[calc1] == nil)
    }
}
