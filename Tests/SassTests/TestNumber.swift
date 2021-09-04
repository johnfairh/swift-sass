//
//  TestNumber.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import Sass // number implementation gorp

func XCTAssertAlmostEqual(_ d1: Double?, _ d2: Double?) {
    guard let d1a = d1, let d2a = d2, SassDouble.areEqual(d1a, d2a) else {
        XCTFail("Not equal: \(String(describing: d1)), \(String(describing: d2)).")
        return
    }
}

extension Sass.Unit {
    func convert(_ value: Double, to otherUnit: Name) -> Double? {
        guard let dim = dimension else {
            return nil
        }
        let ratio = dim.ratio(from: name, to: otherUnit)
        return ratio.apply(value)
    }
}

extension Ratio : Equatable {
    public static func == (lhs: Ratio, rhs: Ratio) -> Bool {
        SassDouble.areEqual(lhs.apply(1), rhs.apply(1))
    }
}

extension SassDouble {
    static let lastPlace = 1e-10
}

class TestNumber: XCTestCase {

    // MARK: SassDouble

    func testDoubleEquals() {
        let samples = [Double]([0, 1, -1, 12.4, 8000, -1000, -8000])
        samples.forEach { s in
            let d1 = Double(s)
            let d2 = Double(d1 + SassDouble.lastPlace)
            XCTAssertNotEqual(d1, d2)
            XCTAssertNotEqual(SassDouble(d1), SassDouble(d2))
            XCTAssertLessThan(SassDouble(d1), SassDouble(d2))
            let d3 = (d2 - SassDouble.lastPlace/2).nextDown.nextDown
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
        XCTAssertNotNil(dict[SassDouble((d1.double + SassDouble.lastPlace/2).nextDown)])
        XCTAssertNil(dict[SassDouble(d1.double + SassDouble.lastPlace/2)])
    }

    func testClosedRange() throws {
        let r = 1.0 ... 10.1
        XCTAssertEqual(5, SassDouble(5).clampTo(range: r))
        XCTAssertEqual(r.lowerBound, SassDouble(1).clampTo(range: r))
        XCTAssertEqual(r.upperBound, SassDouble(10.1).clampTo(range: r))
        XCTAssertEqual(r.upperBound, SassDouble(r.upperBound.nextUp).clampTo(range: r))
        XCTAssertEqual(r.lowerBound, SassDouble(r.lowerBound.nextDown).clampTo(range: r))
        XCTAssertNil(SassDouble(r.upperBound + SassDouble.lastPlace*2/3).clampTo(range: r))
        XCTAssertNil(SassDouble((r.lowerBound - SassDouble.lastPlace/2).nextDown).clampTo(range: r))
    }

    func testHalfOpenRange() throws {
        let r = 1.0 ..< 6.8
        XCTAssertEqual(5, SassDouble(5).clampTo(range: r))
        XCTAssertEqual(r.lowerBound, SassDouble(1).clampTo(range: r))
        XCTAssertNil(SassDouble(6.8).clampTo(range: r))
        XCTAssertNil(SassDouble(r.upperBound.nextUp).clampTo(range: r))
        XCTAssertGreaterThan(r.upperBound, SassDouble(r.upperBound - SassDouble.lastPlace*2).clampTo(range: r)!)
        XCTAssertEqual(r.lowerBound, SassDouble(r.lowerBound.nextDown).clampTo(range: r))
        XCTAssertNil(SassDouble(r.lowerBound - SassDouble.lastPlace).clampTo(range: r))
    }

    func testIntConversion() {
        XCTAssertEqual(5, Int(SassDouble(5.0)))
        XCTAssertEqual(5, Int(SassDouble(5.0.nextUp)))
        XCTAssertEqual(5, Int(SassDouble(5.0.nextDown)))
        XCTAssertEqual(5, Int(SassDouble((5.0 + SassDouble.lastPlace/2).nextDown)))
        XCTAssertEqual(5, Int(SassDouble((5.0 - SassDouble.lastPlace/2))))
        XCTAssertNil(Int(SassDouble(5.0 + SassDouble.lastPlace/2)))
        XCTAssertNil(Int(SassDouble((5.0 - SassDouble.lastPlace/2).nextDown)))
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

    // MARK: Units

    // Check the conversion tables aren't wrong.
    func testDimensionConversion() {
        // lengths
        let inch = Sass.Unit(name: "in")
        XCTAssertEqual(1, inch.convert(1, to: "in"))
        XCTAssertEqual(2.54, inch.convert(1, to: "cm"))
        XCTAssertAlmostEqual(25.4, inch.convert(1, to: "mm")) // floating point...
        XCTAssertAlmostEqual(25.4*4, inch.convert(1, to: "q")) // floating point...
        XCTAssertEqual(96, inch.convert(1, to: "px"))
        XCTAssertEqual(6, inch.convert(1, to: "pc"))
        XCTAssertEqual(72, inch.convert(1, to: "pt"))

        // angles
        let rad = Sass.Unit(name: "rad")
        XCTAssertEqual(.pi, rad.convert(.pi, to: "rad"))
        XCTAssertEqual(180, rad.convert(.pi, to: "deg"))
        XCTAssertEqual(200, rad.convert(.pi, to: "grad"))
        XCTAssertEqual(0.5, rad.convert(.pi, to: "turn"))

        // time
        let ms = Sass.Unit(name: "ms")
        XCTAssertEqual(2500, ms.convert(2500, to: "ms"))
        XCTAssertEqual(2.5, ms.convert(2500, to: "s"))

        // freq
        let khz = Sass.Unit(name: "kHz")
        XCTAssertEqual(1.5, khz.convert(1.5, to: "khz"))
        XCTAssertEqual(1500, khz.convert(1.5, to: "hz"))

        // res
        let dpi = Sass.Unit(name: "dpi")
        XCTAssertEqual(100/96, dpi.convert(100, to: "dppx"))
        XCTAssertEqual(100/96, dpi.convert(100, to: "x"))
        XCTAssertEqual(100/2.54, dpi.convert(100, to: "dpcm"))
    }

    // Unit-level conversions
    func testUnitConversion() throws {
        let funk = Sass.Unit(name: "funk")
        let cm = Sass.Unit(name: "cm")
        XCTAssertTrue(funk.isConvertibleTo(funk))
        XCTAssertFalse(funk.isConvertibleTo(cm))
        XCTAssertEqual(.identity, funk.ratio(to: funk))

        let c1 = funk.canonicalUnitAndRatio
        XCTAssertEqual(funk, c1.0)
        XCTAssertEqual(.identity, c1.1)

        let c2 = cm.canonicalUnitAndRatio
        XCTAssertEqual(Sass.Unit(name: "px"), c2.0)
        XCTAssertEqual(Ratio(96, 2.54), c2.1)
        XCTAssertEqual(Ratio(10, 1), cm.ratio(to: Unit(name: "mm")))
    }

    // Unit-product conversions
    func testUnitProduct() throws {
        let cmArea = UnitProduct(names: ["cm", "cm"])
        XCTAssertEqual("cm * cm", cmArea.description)

        let canon = cmArea.canonicalUnitsAndRatio
        XCTAssertEqual(UnitProduct(names: ["px", "px"]), canon.0)
        XCTAssertEqual(Ratio(96 * 96, 2.54 * 2.54), canon.1)

        let frogSeconds = UnitProduct(names: ["s", "frog"])
        XCTAssertEqual("frog * s", frogSeconds.description)
        // self conversion
        XCTAssertEqual(.identity, try frogSeconds.ratio(to: frogSeconds))

        // valid conversion
        let frogMs = UnitProduct(names: ["ms", "frog"])
        XCTAssertEqual(Ratio(1000, 1), try frogSeconds.ratio(to: frogMs))

        // bad conversion, missing target
        let ms = UnitProduct(names: ["ms"])
        do {
            let r = try frogSeconds.ratio(to: ms)
            XCTFail("Managed to convert away frogs: \(r)")
        } catch {
            print(error)
        }

        // bad conversion, missing source
        let frogOhmMs = UnitProduct(names: ["ms", "ohm", "frog"])
        do {
            let r = try frogSeconds.ratio(to: frogOhmMs)
            XCTFail("Managed to convert to ohms: \(r)")
        } catch {
            print(error)
        }
    }

    // Unit-quotient
    func testUnitQuotientBasics() throws {
        let emptyUQ = try UnitQuotient(numerator: [], denominator: [])
        XCTAssertFalse(emptyUQ.hasUnits)
        XCTAssertEqual("", emptyUQ.description)

        let cm = try UnitQuotient(numerator: ["cm"], denominator: [])
        XCTAssertEqual("cm", cm.description)
        let mps = try UnitQuotient(numerator: ["m"], denominator: ["s"])
        XCTAssertEqual("m / s", mps.description)
        let ps = try UnitQuotient(numerator: [], denominator: ["s"])
        XCTAssertEqual("(s)^-1", ps.description)

        do {
            let uncancelledUQ = try UnitQuotient(numerator: ["px"], denominator: ["in", "s"])
            XCTFail("Managed to create px / in * s: \(uncancelledUQ)")
        } catch {
            print(error)
        }
    }

    func testUnitQuotientConversion() throws {
        let cmPerMs = try UnitQuotient(numerator: ["cm"], denominator: ["ms"])
        let canon = cmPerMs.canonicalUnitsAndRatio
        XCTAssertEqual("px / s", canon.0.description)
        XCTAssertEqual(Ratio(1000 * 96, 2.54), canon.1)

        let cmPerS = try UnitQuotient(numerator: ["cm"], denominator: ["s"])
        let ratio = try cmPerMs.ratio(to: cmPerS)
        XCTAssertEqual(Ratio(1000, 1), ratio)
    }

    // Numbers with units
    func testNumberUnit() throws {
        let unitFree = SassNumber(.pi)
        try unitFree.checkNoUnits()
        XCTAssertFalse(unitFree.hasUnit(name: "ms"))
        do {
            try unitFree.checkHasUnit(name: "ms")
            XCTFail("Found ms in \(unitFree)")
        } catch {
            print(error)
        }

        let freq = SassNumber(123, unit: "khz")
        try freq.checkHasUnit(name: "khz")
        XCTAssertFalse(freq.hasNoUnits)
        do {
            try freq.checkNoUnits()
            XCTFail("Didn't find any units in \(freq)")
        } catch {
            print(error)
        }

        let frog = SassNumber(12, unit: "frog")
        let bark = SassNumber(12, unit: "bark")
        XCTAssertNotEqual(frog, bark)
        XCTAssertEqual(["frog"], frog.numeratorUnits)
        XCTAssertEqual([], frog.denominatorUnits)

        let noUnit = try bark.asConvertedTo(numeratorUnits: [], denominatorUnits: [])
        XCTAssertNotEqual(noUnit, frog)
        XCTAssertNotEqual(noUnit, bark)
        let frogAgain = try noUnit.asConvertedTo(numeratorUnits: frog.numeratorUnits, denominatorUnits: frog.denominatorUnits)
        XCTAssertEqual(frog, frogAgain)
    }

    func testNumberUnitConversion() throws {
        let width = try SassNumber(100, numeratorUnits: ["cm"])

        let widthInPixels = try width.asConvertedTo(numeratorUnits: ["px"])
        XCTAssertAlmostEqual((100 * 96) / 2.54, widthInPixels.double)

        XCTAssertEqual(width, widthInPixels)

        var dict = [width: true]
        XCTAssertTrue(dict[widthInPixels]!)

        let century = SassNumber(100, unit: "runs")
        dict[century] = false
        XCTAssertTrue(dict[widthInPixels]!)
        XCTAssertFalse(dict[century]!)
        XCTAssertNotEqual(width, century)
    }
}
