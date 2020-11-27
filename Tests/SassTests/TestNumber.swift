//
//  TestNumber.swift
//  SassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import Sass // number implementation gorp

class TestNumber: XCTestCase {

    // MARK: SassDouble

    /// Things that are wrong with the Sass number equality & hashing spec.
    /// This test passes if `SassDouble.areEqual(...)` uses the sass_spec algorithm
    func testSassNumericWeirdness() throws {
        try XCTSkipIf(true)
        // 1. == is not an equivalence relation
        let dx = SassDouble(0)
        let dy = SassDouble(dx.double + SassDouble.tolerance)
        let dz = SassDouble(dy.double.nextDown)

        XCTAssertNotEqual(dx, dy) // Values for dx for which this doesn't even work due to fp precision: 12, ...
        XCTAssertEqual(dx, dz)
        XCTAssertEqual(dz, dy) // <- not equivalence relation

        // 2. == doesn't match hashvalue [bcoz hashvalue does rounding...]
        let d1 = SassDouble(1000)
        let d2 = SassDouble((d1.double + SassDouble.tolerance).nextDown)
        XCTAssertEqual(d1, d2)
        let h1 = d1.hashEquivalent
        let h2 = d2.hashEquivalent
        XCTAssertNotEqual(h1, h2) // <- bad: different hash values for == values
    }

    func testDoubleEquals() {
        // Carefully chosen values to avoid floating point gremlins!
        // If you close your eyes, they can't see you.
        let samples = [Double]([0, 8000, -1000, -8000])
        samples.forEach { s in
            let d1 = Double(s)
            let d2 = Double(d1 + SassDouble.tolerance)
            XCTAssertNotEqual(d1, d2)
            XCTAssertNotEqual(SassDouble(d1), SassDouble(d2))
            XCTAssertLessThan(SassDouble(d1), SassDouble(d2))
            let d3 = d2 - (SassDouble.tolerance * 2) / 3
            XCTAssertEqual(SassDouble(d1), SassDouble(d3))
            XCTAssertFalse(SassDouble(d1) < SassDouble(d3))
        }
    }

    func testHashing() {
        let d1 = SassDouble(12.4)
        let d2 = SassDouble(13)
        XCTAssertNotEqual(d1, d2)
        XCTAssertNotEqual(d1.hashEquivalent, d2.hashEquivalent)
        let dict = [d1: true]
        XCTAssertNotNil(dict[d1])
        XCTAssertNotNil(dict[SassDouble(d1.double.nextUp)])
    }

    func testClosedRange() throws {
        let r = 1.0 ... 10.1
        XCTAssertEqual(5, SassDouble(5).clampTo(range: r))
        XCTAssertEqual(r.lowerBound, SassDouble(1).clampTo(range: r))
        XCTAssertEqual(r.upperBound, SassDouble(10.1).clampTo(range: r))
        XCTAssertEqual(r.upperBound, SassDouble(r.upperBound.nextUp).clampTo(range: r))
        XCTAssertEqual(r.lowerBound, SassDouble(r.lowerBound.nextDown).clampTo(range: r))
        XCTAssertNil(SassDouble(r.upperBound + SassDouble.tolerance*2).clampTo(range: r))
        XCTAssertNil(SassDouble(r.lowerBound - SassDouble.tolerance).clampTo(range: r))
    }

    func testHalfOpenRange() throws {
        let r = 1.0 ..< 6.8
        XCTAssertEqual(5, SassDouble(5).clampTo(range: r))
        XCTAssertEqual(r.lowerBound, SassDouble(1).clampTo(range: r))
        XCTAssertNil(SassDouble(6.8).clampTo(range: r))
        XCTAssertNil(SassDouble(r.upperBound.nextUp).clampTo(range: r))
        XCTAssertGreaterThan(r.upperBound, SassDouble(r.upperBound - SassDouble.tolerance*2).clampTo(range: r)!)
        XCTAssertEqual(r.lowerBound, SassDouble(r.lowerBound.nextDown).clampTo(range: r))
        XCTAssertNil(SassDouble(r.lowerBound - SassDouble.tolerance).clampTo(range: r))
    }

    func testIntConversion() {
        XCTAssertEqual(5, Int(SassDouble(5.0)))
        XCTAssertEqual(5, Int(SassDouble(5.0.nextUp)))
        XCTAssertEqual(5, Int(SassDouble(5.0.nextDown)))
        XCTAssertNil(Int(SassDouble(5.0 + SassDouble.tolerance)))
        XCTAssertNil(Int(SassDouble(5.0 - SassDouble.tolerance)))
    }

    // MARK: SassNumber numerics

    // Basics and stuff that just wraps SassDouble
    func testProperties() throws {
        let n = SassNumber(12)
        let m = SassNumber(12.0.nextUp)
        XCTAssertEqual(n, m)
        XCTAssertNotEqual(n.double, m.double)
        XCTAssertEqual("Number(12.0)", n.description)

        let dict = [n: true]
        XCTAssertTrue(dict[m]!)

        let v: SassValue = n
        XCTAssertEqual(n, try v.asNumber())
        let str = SassString("str")
        XCTAssertThrowsError(try str.asNumber())

        let o = SassNumber(13.4)
        XCTAssertGreaterThanOrEqual(o, n)

        XCTAssertEqual(12, try n.asInt())
        XCTAssertEqual(12, try m.asInt())
        XCTAssertThrowsError(try o.asInt())
    }

    func testRange() throws {
        XCTAssertEqual(12.0, try SassNumber(12).asIn(range: 10...20))
        XCTAssertEqual(20.0, try SassNumber(20).asIn(range: 10...20))
        XCTAssertThrowsError(try SassNumber(8).asIn(range: 10...20))

        XCTAssertEqual(12.0, try SassNumber(12).asIn(range: 10..<20))
        XCTAssertThrowsError(try SassNumber(20).asIn(range: 10..<20))
        XCTAssertEqual(10, try SassNumber(10).asIn(range: 10..<20))
    }
}
