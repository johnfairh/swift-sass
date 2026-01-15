//
//  TestNumber.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Testing
@testable import Sass // number implementation gorp

func assertAlmostEqual(_ d1: Double?, _ d2: Double?) {
    if let d1a = d1, let d2a = d2, SassDouble.areEqual(d1a, d2a) {
        return
    }
    Issue.record("Not equal: \(String(describing: d1)), \(String(describing: d2)).")
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

extension Sass.Ratio : Swift.Equatable {
    public static func == (lhs: Ratio, rhs: Ratio) -> Bool {
        SassDouble.areEqual(lhs.apply(1), rhs.apply(1))
    }
}

extension SassDouble {
    static let lastPlace = 1e-10
}

struct TestNumber {

    // MARK: SassDouble

    @Test
    func testDoubleEquals() {
        let samples = [Double]([0, 1, -1, 12.4, 8000, -1000, -8000])
        samples.forEach { s in
            let d1 = Double(s)
            let d2 = Double(d1 + SassDouble.lastPlace)
            #expect(d1 != d2)
            #expect(SassDouble(d1) != SassDouble(d2))
            #expect(SassDouble(d1) < SassDouble(d2))
            let d3 = (d2 - SassDouble.lastPlace/2).nextDown.nextDown
            #expect(SassDouble(d1) == SassDouble(d3))
            #expect(!(SassDouble(d1) < SassDouble(d3)))
        }
    }

    @Test
    func testHashing() {
        let d1 = SassDouble(12.4)
        let d2 = SassDouble(13)
        #expect(d1 != d2)
        #expect(d1.hashEquivalent != d2.hashEquivalent)
        let dict = [d1: true]
        #expect(dict[d1] != nil)
        #expect(dict[SassDouble(d1.double.nextUp)] != nil)
        #expect(dict[SassDouble((d1.double + SassDouble.lastPlace/2).nextDown)] != nil)
        #expect(dict[SassDouble(d1.double + SassDouble.lastPlace/2)] == nil)
    }

    @Test
    func testClosedRange() {
        let r = 1.0 ... 10.1
        #expect(5 == SassDouble(5).clampTo(range: r))
        #expect(r.lowerBound == SassDouble(1).clampTo(range: r))
        #expect(r.upperBound == SassDouble(10.1).clampTo(range: r))
        #expect(r.upperBound == SassDouble(r.upperBound.nextUp).clampTo(range: r))
        #expect(r.lowerBound == SassDouble(r.lowerBound.nextDown).clampTo(range: r))
        #expect(SassDouble(r.upperBound + SassDouble.lastPlace*2/3).clampTo(range: r) == nil)
        #expect(SassDouble((r.lowerBound - SassDouble.lastPlace/2).nextDown).clampTo(range: r) == nil)
    }

    @Test
    func testHalfOpenRange() {
        let r = 1.0 ..< 6.8
        #expect(5 == SassDouble(5).clampTo(range: r))
        #expect(r.lowerBound == SassDouble(1).clampTo(range: r))
        #expect(SassDouble(6.8).clampTo(range: r) == nil)
        #expect(SassDouble(r.upperBound.nextUp).clampTo(range: r) == nil)
        let clamped = SassDouble(r.upperBound - SassDouble.lastPlace*2).clampTo(range: r)
        let unwrapped = try! #require(clamped)
        #expect(r.upperBound > unwrapped)
        #expect(r.lowerBound == SassDouble(r.lowerBound.nextDown).clampTo(range: r))
        #expect(SassDouble(r.lowerBound - SassDouble.lastPlace).clampTo(range: r) == nil)
    }

    @Test
    func testIntConversion() {
        #expect(5 == Int(SassDouble(5.0)))
        #expect(5 == Int(SassDouble(5.0.nextUp)))
        #expect(5 == Int(SassDouble(5.0.nextDown)))
        #expect(5 == Int(SassDouble((5.0 + SassDouble.lastPlace/2).nextDown)))
        #expect(5 == Int(SassDouble((5.0 - SassDouble.lastPlace/2))))
        #expect(Int(SassDouble(5.0 + SassDouble.lastPlace/2)) == nil)
        #expect(Int(SassDouble((5.0 - SassDouble.lastPlace/2).nextDown)) == nil)
    }

    // MARK: SassNumber numerics

    // Basics and stuff that just wraps SassDouble
    @Test
    func testProperties() {
        let n = SassNumber(12)
        let m = SassNumber(12.0.nextUp)
        #expect(n == m)
        #expect(n.double != m.double)
        #expect("Number(12)" == n.description)
        #expect("12" == n.sassDescription)

        let dict = [n: true]
        #expect(dict[m] == true)

        let v: SassValue = n
        do {
            let num = try v.asNumber()
            #expect(num == n)
        } catch {
            Issue.record("asNumber threw unexpectedly: \(error)")
        }
        let str = SassString("str")
        #expect(throws: Error.self) {
            _ = try str.asNumber()
        }

        let o = SassNumber(13.4)
        do {
            let iv = try n.asInt()
            #expect(iv == 12)
        } catch { Issue.record("asInt threw: \(error)") }
        do {
            let iv = try m.asInt()
            #expect(iv == 12)
        } catch { Issue.record("asInt threw: \(error)") }
        #expect(throws: Error.self) {
            _ = try o.asInt()
        }
    }

    @Test
    func testRange() {
        do {
            let v1 = try SassNumber(12).asIn(range: 10...20)
            #expect(v1 == 12.0)
            let v2 = try SassNumber(20).asIn(range: 10...20)
            #expect(v2 == 20.0)
        } catch { Issue.record("asIn threw: \(error)") }

        #expect(throws: Error.self) {
            _ = try SassNumber(8).asIn(range: 10...20)
        }

        do {
            let v3 = try SassNumber(12).asIn(range: 10..<20)
            #expect(v3 == 12.0)
        } catch { Issue.record("asIn threw: \(error)") }
        #expect(throws: Error.self) {
            _ = try SassNumber(20).asIn(range: 10..<20)
        }
        do {
            let v4 = try SassNumber(10).asIn(range: 10..<20)
            #expect(v4 == 10)
        } catch { Issue.record("asIn threw: \(error)") }
    }

    // MARK: Units

    // Check the conversion tables aren't wrong.
    @Test
    func testDimensionConversion() {
        // lengths
        let inch = Sass.Unit(name: "in")
        #expect(1 == inch.convert(1, to: "in"))
        #expect(2.54 == inch.convert(1, to: "cm"))
        assertAlmostEqual(25.4, inch.convert(1, to: "mm")) // floating point...
        assertAlmostEqual(25.4*4, inch.convert(1, to: "q")) // floating point...
        #expect(96 == inch.convert(1, to: "px"))
        #expect(6 == inch.convert(1, to: "pc"))
        #expect(72 == inch.convert(1, to: "pt"))

        // angles
        let rad = Sass.Unit(name: "rad")
        #expect(.pi == rad.convert(.pi, to: "rad"))
        #expect(180 == rad.convert(.pi, to: "deg"))
        #expect(200 == rad.convert(.pi, to: "grad"))
        #expect(0.5 == rad.convert(.pi, to: "turn"))

        // time
        let ms = Sass.Unit(name: "ms")
        #expect(2500 == ms.convert(2500, to: "ms"))
        #expect(2.5 == ms.convert(2500, to: "s"))

        // freq
        let khz = Sass.Unit(name: "kHz")
        #expect(1.5 == khz.convert(1.5, to: "khz"))
        #expect(1500 == khz.convert(1.5, to: "hz"))

        // res
        let dpi = Sass.Unit(name: "dpi")
        #expect(100.0/96.0 == dpi.convert(100, to: "dppx"))
        #expect(100.0/96.0 == dpi.convert(100, to: "x"))
        #expect(100/2.54 == dpi.convert(100, to: "dpcm"))
    }

    // Unit-level conversions
    @Test
    func testUnitConversion() {
        let funk = Sass.Unit(name: "funk")
        let cm = Sass.Unit(name: "cm")
        #expect(funk.isConvertibleTo(funk))
        #expect(!funk.isConvertibleTo(cm))
        #expect(.identity == funk.ratio(to: funk))

        let c1 = funk.canonicalUnitAndRatio
        #expect(funk == c1.0)
        #expect(.identity == c1.1)

        let c2 = cm.canonicalUnitAndRatio
        #expect(Sass.Unit(name: "px") == c2.0)
        #expect(Ratio(96, 2.54) == c2.1)
        #expect(Ratio(10, 1) == cm.ratio(to: Unit(name: "mm")))
    }

    // Unit-product conversions
    @Test
    func testUnitProduct() {
        let cmArea = UnitProduct(names: ["cm", "cm"])
        #expect("cm * cm" == cmArea.description)

        let canon = cmArea.canonicalUnitsAndRatio
        #expect(UnitProduct(names: ["px", "px"]) == canon.0)
        #expect(Ratio(96 * 96, 2.54 * 2.54) == canon.1)

        let frogSeconds = UnitProduct(names: ["s", "frog"])
        #expect("frog * s" == frogSeconds.description)
        // self conversion
        #expect(.identity == (try! frogSeconds.ratio(to: frogSeconds)))

        // valid conversion
        let frogMs = UnitProduct(names: ["ms", "frog"])
        #expect(Ratio(1000, 1) == (try! frogSeconds.ratio(to: frogMs)))

        // bad conversion, missing target
        let ms = UnitProduct(names: ["ms"])
        do {
            let r = try frogSeconds.ratio(to: ms)
            Issue.record("Managed to convert away frogs: \(r)")
        } catch {
            // expected
        }

        // bad conversion, missing source
        let frogOhmMs = UnitProduct(names: ["ms", "ohm", "frog"])
        do {
            let r = try frogSeconds.ratio(to: frogOhmMs)
            Issue.record("Managed to convert to ohms: \(r)")
        } catch {
            // expected
        }
    }

    // Unit-quotient
    @Test
    func testUnitQuotientBasics() {
        let emptyUQ = try! UnitQuotient(numerator: [], denominator: [])
        #expect(!emptyUQ.hasUnits)
        #expect("" == emptyUQ.description)

        let cm = try! UnitQuotient(numerator: ["cm"], denominator: [])
        #expect("cm" == cm.description)
        let mps = try! UnitQuotient(numerator: ["m"], denominator: ["s"])
        #expect("m / s" == mps.description)
        let ps = try! UnitQuotient(numerator: [], denominator: ["s"])
        #expect("(s)^-1" == ps.description)

        do {
            let uncancelledUQ = try UnitQuotient(numerator: ["px"], denominator: ["in", "s"])
            Issue.record("Managed to create px / in * s: \(uncancelledUQ)")
        } catch {
            // expected
        }
    }

    @Test
    func testUnitQuotientConversion() {
        let cmPerMs = try! UnitQuotient(numerator: ["cm"], denominator: ["ms"])
        let canon = cmPerMs.canonicalUnitsAndRatio
        #expect("px / s" == canon.0.description)
        #expect(Ratio(1000 * 96, 2.54) == canon.1)

        let cmPerS = try! UnitQuotient(numerator: ["cm"], denominator: ["s"])
        let ratio = try! cmPerMs.ratio(to: cmPerS)
        #expect(Ratio(1000, 1) == ratio)
    }

    // Numbers with units
    @Test
    func testNumberUnit() {
        let unitFree = SassNumber(.pi)
        do {
            try unitFree.checkNoUnits()
        } catch { Issue.record("checkNoUnits threw: \(error)") }
        #expect(!unitFree.hasUnit(name: "ms"))
        do {
            try unitFree.checkHasUnit(name: "ms")
            Issue.record("Found ms in \(unitFree)")
        } catch {
            // expected
        }

        let freq = SassNumber(123, unit: "khz")
        do { try freq.checkHasUnit(name: "khz") } catch { Issue.record("checkHasUnit threw: \(error)") }
        #expect(!freq.hasNoUnits)
        do {
            try freq.checkNoUnits()
            Issue.record("Didn't find any units in \(freq)")
        } catch {
            // expected
        }

        let frog = SassNumber(12, unit: "frog")
        let bark = SassNumber(12, unit: "bark")
        #expect(frog != bark)
        #expect(["frog"] == frog.numeratorUnits)
        #expect([] == frog.denominatorUnits)

        let noUnit = try! bark.asConvertedTo(numeratorUnits: [], denominatorUnits: [])
        #expect(noUnit != frog)
        #expect(noUnit != bark)
        let frogAgain = try! noUnit.asConvertedTo(numeratorUnits: frog.numeratorUnits, denominatorUnits: frog.denominatorUnits)
        #expect(frog == frogAgain)
    }

    @Test
    func testNumberUnitConversion() {
        let width = try! SassNumber(100, numeratorUnits: ["cm"]) 

        let widthInPixels = try! width.asConvertedTo(numeratorUnits: ["px"])
        assertAlmostEqual((100 * 96) / 2.54, widthInPixels.double)

        #expect(width == widthInPixels)

        var dict = [width: true]
        #expect(dict[widthInPixels] == true)

        let century = SassNumber(100, unit: "runs")
        dict[century] = false
        #expect(dict[widthInPixels] == true)
        #expect(dict[century] == false)
        #expect(width != century)
    }
}

