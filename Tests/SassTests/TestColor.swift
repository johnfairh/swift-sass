//
//  TestColor.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import Sass // color implementation bits

func XCTAssertHslIntEqual(_ lhs: HslColor, _ rhs: HslColor) {
    XCTAssertEqual(Int(lhs.hue.rounded()), Int(rhs.hue.rounded()))
    XCTAssertEqual(Int(lhs.saturation.rounded()), Int(rhs.saturation.rounded()))
    XCTAssertEqual(Int(lhs.lightness.rounded()), Int(rhs.lightness.rounded()))
}

func XCTAssertHwbIntEqual(_ lhs: HwbColor, _ rhs: HwbColor) {
    XCTAssertEqual(Int(lhs.hue.rounded()), Int(rhs.hue.rounded()))
    XCTAssertEqual(Int(lhs.whiteness.rounded()), Int(rhs.whiteness.rounded()))
    XCTAssertEqual(Int(lhs.blackness.rounded()), Int(rhs.blackness.rounded()))
}

func XCTAssertWithinOne(_ lhs: Int, _ rhs: Int) {
    XCTAssert((lhs - rhs).magnitude <= 2, "Expected \(lhs) got \(rhs)")
}

func XCTAssertWithinOne(_ lhs: RgbColor, _ rhs: RgbColor) {
    XCTAssertWithinOne(lhs.red, rhs.red)
    XCTAssertWithinOne(lhs.green, rhs.green)
    XCTAssertWithinOne(lhs.blue, rhs.blue)
}

func XCTAssertWithinOne(_ lhs: HslColor, _ rhs: HslColor) {
    XCTAssertWithinOne(Int(lhs.hue.rounded()), Int(rhs.hue.rounded()))
    XCTAssertWithinOne(Int(lhs.saturation.rounded()), Int(rhs.saturation.rounded()))
    XCTAssertWithinOne(Int(lhs.lightness.rounded()), Int(rhs.lightness.rounded()))
}

func XCTAssertWithinOne(_ lhs: HwbColor, _ rhs: HwbColor) {
    XCTAssertWithinOne(Int(lhs.hue.rounded()), Int(rhs.hue.rounded()))
    XCTAssertWithinOne(Int(lhs.whiteness.rounded()), Int(rhs.whiteness.rounded()))
    XCTAssertWithinOne(Int(lhs.blackness.rounded()), Int(rhs.blackness.rounded()))
}


class TestColor: XCTestCase {
    let rgbBlack = try! RgbColor(red: 0, green: 0, blue: 0)
    let hslBlack = try! HslColor(hue: 0, saturation: 0, lightness: 0)
    let hwbBlack = try! HwbColor(hue: 0, whiteness: 0, blackness: 100)

    let rgbWhite = try! RgbColor(red: 255, green: 255, blue: 255)
    let hslWhite = try! HslColor(hue: 0, saturation: 0, lightness: 100)
    let hwbWhite = try! HwbColor(hue: 0, whiteness: 100, blackness: 0)

    let rgbRed = try! RgbColor(red: 255, green: 0, blue: 0)
    let hslRed = try! HslColor(hue: 0, saturation: 100, lightness: 50)
    let hwbRed = try! HwbColor(hue: 0, whiteness: 0, blackness: 0)

    let rgbGreen = try! RgbColor(red: 0, green: 255, blue: 0)
    let hslGreen = try! HslColor(hue: 120, saturation: 100, lightness: 50)
    let hwbGreen = try! HwbColor(hue: 120, whiteness: 0, blackness: 0)

    let rgbBlue = try! RgbColor(red: 0, green: 0, blue: 255)
    let hslBlue = try! HslColor(hue: 240, saturation: 100, lightness: 50)
    let hwbBlue = try! HwbColor(hue: 240, whiteness: 0, blackness: 0)

    // Finding non-trivial colours that convert reversibly all three ways is beyond
    // me - we get close but allow one nit of slop per axis

    let rgbPink = try! RgbColor(red: 246, green: 142, blue: 227)
    let hslPink = try! HslColor(hue: 311, saturation: 85, lightness: 76)
    let hwbPink = try! HwbColor(hue: 311, whiteness: 56, blackness: 4)

    let rgbDeepGreen = try! RgbColor(red: 56, green: 85, blue: 70)
    let hslDeepGreen = try! HslColor(hue: 150, saturation: 20, lightness: 27)
    let hwbDeepGreen = try! HwbColor(hue: 150, whiteness: 22, blackness: 67)

    private func checkConversion(_ rgb: RgbColor, _ hsl: HslColor) {
        XCTAssertHslIntEqual(hsl, HslColor(rgb))
        XCTAssertEqual(rgb, RgbColor(hsl))
    }

    private func checkConversion(_ rgb: RgbColor, _ hsl: HslColor, _ hwb: HwbColor, sloppy: Bool = false) {
        if sloppy {
            XCTAssertWithinOne(hsl, HslColor(rgb))
            XCTAssertWithinOne(rgb, RgbColor(hsl))
            XCTAssertWithinOne(hwb, HwbColor(rgb))
            XCTAssertWithinOne(hsl, HslColor(hwb))
            XCTAssertWithinOne(rgb, RgbColor(hwb))
            XCTAssertWithinOne(hwb, HwbColor(hsl))
        } else {
            XCTAssertHslIntEqual(hsl, HslColor(rgb))
            XCTAssertEqual(rgb, RgbColor(hsl))
            XCTAssertHwbIntEqual(hwb, HwbColor(rgb))
            XCTAssertHslIntEqual(hsl, HslColor(hwb))
            XCTAssertEqual(rgb, RgbColor(hwb))
            XCTAssertHwbIntEqual(hwb, HwbColor(hsl))
        }
    }

    func testRgbHslHwbConversion() throws {
        checkConversion(rgbBlack, hslBlack, hwbBlack)
        checkConversion(rgbWhite, hslWhite, hwbWhite)
        checkConversion(rgbRed, hslRed, hwbRed)
        checkConversion(rgbGreen, hslGreen, hwbGreen)
        checkConversion(rgbBlue, hslBlue, hwbBlue)
        checkConversion(rgbPink, hslPink, hwbPink, sloppy: true)
        checkConversion(rgbDeepGreen, hslDeepGreen, hwbDeepGreen, sloppy: true)
    }

    func testRangeChecking() throws {
        func check(_ maker: @autoclosure () throws -> SassColor) {
            do {
                let col = try maker()
                XCTFail("Bad color \(col)")
            } catch {
                print(error)
            }
        }

        check(try SassColor(red: -1, green: 0, blue: 0))
        check(try SassColor(red: 0, green: 0, blue: 0, alpha: 100))
        check(try SassColor(hue: 100, saturation: 200, lightness: 0.8))
        check(try SassColor(hue: -20, saturation: 20, lightness: 0.8))
        check(try SassColor(hue: 100, whiteness: 200, blackness: 20))
        check(try SassColor(hue: -20, whiteness: 80, blackness: 20))
        check(try SassColor(hue: 0, whiteness: 80, blackness: 1110))
    }

    private func check(rgb colRgb: SassColor, _ r: Int, _ g: Int, _ b: Int, _ a: Double) {
        XCTAssertEqual(r, colRgb.red)
        XCTAssertEqual(g, colRgb.green)
        XCTAssertEqual(b, colRgb.blue)
        XCTAssertEqual(a, colRgb.alpha)
    }

    private func check(hsl colHsl: SassColor, _ h: Double, _ s: Double, _ l: Double, _ a: Double) {
        XCTAssertEqual(h, colHsl.hue)
        XCTAssertEqual(s, colHsl.saturation)
        XCTAssertEqual(l, colHsl.lightness)
        XCTAssertEqual(a, colHsl.alpha)
    }

    private func check(hwb colHwb: SassColor, _ h: Double, _ w: Double, _ b: Double, _ a: Double) {
        XCTAssertEqual(h, colHwb.hue)
        XCTAssertEqual(w, colHwb.whiteness)
        XCTAssertEqual(b, colHwb.blackness)
        XCTAssertEqual(a, colHwb.alpha)
    }

    func testValueBehaviours() throws {
        let colRgb = try SassColor(red: 12, green: 20, blue: 100, alpha: 0.5)
        check(rgb: colRgb, 12, 20, 100, 0.5)
        XCTAssertEqual("Color(RGB(12, 20, 100) alpha 0.5)", colRgb.description)

        let colHsl = try SassColor(hue: 190, saturation: 20, lightness: 95, alpha: 0.9)
        check(hsl: colHsl, 190, 20, 95, 0.9)
        XCTAssertEqual("Color(HSL(190.0°, 20.0%, 95.0%) alpha 0.9)", colHsl.description)

        let colHwb = try SassColor(hue: 95, whiteness: 18, blackness: 45, alpha: 0.3)
        check(hwb: colHwb, 95, 18, 45, 0.3)
        XCTAssertEqual("Color(HWB(95.0°, 18.0%, 45.0%) alpha 0.3)", colHwb.description)

        let val: SassValue = colRgb
        XCTAssertNoThrow(try val.asColor())
        XCTAssertThrowsError(try SassConstants.true.asColor())

        XCTAssertEqual(colRgb, colRgb)
        let colHsl2 = try SassColor(hue: colRgb.hue,
                                    saturation: colRgb.saturation,
                                    lightness: colRgb.lightness,
                                    alpha: colRgb.alpha)
        XCTAssertEqual(colRgb, colHsl2)

        let dict = [colRgb: true]
        XCTAssertTrue(dict[colHsl2]!)
    }

    func testModificationRgb() throws {
        let col1 = try SassColor(red: 1, green: 2, blue: 3, alpha: 0.1)
        check(rgb: col1, 1, 2, 3, 0.1)
        let col2 = try col1.change(alpha: 0.9)
        check(rgb: col2, 1, 2, 3, 0.9)
        let col3 = try col2.change(red: 5)
        check(rgb: col3, 5, 2, 3, 0.9)
        let col4 = try col3.change(green: 12)
        check(rgb: col4, 5, 12, 3, 0.9)
        let col5 = try col4.change(blue: 15)
        check(rgb: col5, 5, 12, 15, 0.9)
        let col6 = try col5.change(red: 1, green: 2, blue: 3, alpha: 0.1)
        XCTAssertEqual(col1, col6)
    }

    func testModificationHsl() throws {
        let col1 = try SassColor(hue: 20, saturation: 30, lightness: 40, alpha: 0.7)
        check(hsl: col1, 20, 30, 40, 0.7)
        let col2 = try col1.change(alpha: 0.01)
        check(hsl: col2, 20, 30, 40, 0.01)
        let col3 = try col2.change(hue: 44)
        check(hsl: col3, 44, 30, 40, 0.01)
        let col4 = try col3.change(saturation: 32)
        check(hsl: col4, 44, 32, 40, 0.01)
        let col5 = try col4.change(lightness: 60)
        check(hsl: col5, 44, 32, 60, 0.01)
        let col6 = try col5.change(hue: 20, saturation: 30, lightness: 40, alpha: 0.7)
        XCTAssertEqual(col1, col6)
    }

    func testModificationHwb() throws {
        let col1 = try SassColor(hue: 20, whiteness: 30, blackness: 40, alpha: 0.7)
        check(hwb: col1, 20, 30, 40, 0.7)
        let col2 = try col1.change(alpha: 0.01)
        check(hwb: col2, 20, 30, 40, 0.01)
        let col3 = try col2.change(hue: 44)
        check(hwb: col3, 44, 30, 40, 0.01)
        let col4 = try col3.change(whiteness: 32)
        check(hwb: col4, 44, 32, 40, 0.01)
        let col5 = try col4.change(blackness: 60)
        check(hwb: col5, 44, 32, 60, 0.01)
        let col6 = try col5.change(hue: 20, whiteness: 30, blackness: 40, alpha: 0.7)
        XCTAssertEqual(col1, col6)
    }

    // Coerce of color formats
    func testForeignModifications() throws {
        let hwbCol = try SassColor(red: 70, green: 80, blue: 90).change(whiteness: 22)
        check(rgb: hwbCol, 56, 73, 90, 1)

        let hwbCol2 = try SassColor(hue: 200, saturation: 50, lightness: 50).change(blackness: 20)
        check(hwb: hwbCol2, 200, 25, 20, 1)

        let hwbCol3 = try SassColor(hue: 200, whiteness: 25, blackness: 25).change(lightness: 80)
        check(hsl: hwbCol3, 200, 50, 80, 1)
    }

    // odd corner where we generate the lazy color-rep then do an alpha-only change!
    func testCornerModification() throws {
        let col = try SassColor(red: 1, green: 2, blue: 3, alpha: 0.4)
        XCTAssertEqual(210, col.hue)
        let col2 = try col.change(alpha: 0.0)
        check(rgb: col2, 1, 2, 3, 0.0)
    }
}
