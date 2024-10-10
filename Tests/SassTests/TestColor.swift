//
//  TestColor.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@_spi(SassCompilerProvider) import Sass

// Drastically cut down for Color 4 while we can't convert between spaces

class TestColor: XCTestCase {
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
        check(try SassColor(space: "Bad Space", 0, 0, 0, alpha: 0))
    }

    private func check(rgb colRgb: SassColor, _ r: Int, _ g: Int, _ b: Int, _ a: Double) {
        XCTAssertEqual(colRgb.space, .rgb)
        XCTAssertEqual(r, Int(colRgb.channel1!))
        XCTAssertEqual(g, Int(colRgb.channel2!))
        XCTAssertEqual(b, Int(colRgb.channel3!))
        XCTAssertEqual(a, colRgb.alpha!)
    }

    private func check(hsl colHsl: SassColor, _ h: Double, _ s: Double, _ l: Double, _ a: Double) {
        XCTAssertEqual(colHsl.space, .hsl)
        XCTAssertEqual(h, colHsl.channel1!)
        XCTAssertEqual(s, colHsl.channel2!)
        XCTAssertEqual(l, colHsl.channel3!)
        XCTAssertEqual(a, colHsl.alpha!)
    }

    private func check(hwb colHwb: SassColor, _ h: Double, _ w: Double, _ b: Double, _ a: Double) {
        XCTAssertEqual(colHwb.space, .hwb)
        XCTAssertEqual(h, colHwb.channel1!)
        XCTAssertEqual(w, colHwb.channel2!)
        XCTAssertEqual(b, colHwb.channel3!)
        XCTAssertEqual(a, colHwb.alpha!)
    }

    func testValueBehaviours() throws {
        let colRgb = try SassColor(red: 12, green: 20, blue: 100, alpha: 0.5)
        check(rgb: colRgb, 12, 20, 100, 0.5)
        XCTAssertEqual("Color(rgb [12.0, 20.0, 100.0] a=0.5)", colRgb.description)

        let colHsl = try SassColor(hue: 190, saturation: 20, lightness: 95, alpha: 0.9)
        check(hsl: colHsl, 190, 20, 95, 0.9)
        XCTAssertEqual("Color(hsl [190.0, 20.0, 95.0] a=0.9)", colHsl.description)

        let colHwb = try SassColor(hue: 95, whiteness: 18, blackness: 45, alpha: 0.3)
        check(hwb: colHwb, 95, 18, 45, 0.3)
        XCTAssertEqual("Color(hwb [95.0, 18.0, 45.0] a=0.3)", colHwb.description)

        let val: SassValue = colRgb
        XCTAssertNoThrow(try val.asColor())
        XCTAssertThrowsError(try SassConstants.true.asColor())

        XCTAssertEqual(colRgb, colRgb)
//        let colHsl2 = try SassColor(hue: colRgb.hue,
//                                    saturation: colRgb.saturation,
//                                    lightness: colRgb.lightness,
//                                    alpha: colRgb.alpha)
//        XCTAssertEqual(colRgb, colHsl2)

        let dict = [colRgb: true]
        XCTAssertTrue(dict[try! val.asColor() /*colHsl2*/]!)
    }

    func testMissingChannels() throws {
        let color = SassColor(space: .displayP3, nil, nil, nil, alpha: nil)
        XCTAssertEqual("Color(displayP3 [missing, missing, missing] a=missing)", color.description)

        let color2 = color
        XCTAssertEqual(color2, color)

        let color3 = SassColor(space: .displayP3, 1.0, nil, nil, alpha: nil)
        XCTAssertNotEqual(color3, color)

        var map = [SassColor:Bool]()
        map[color] = true
        XCTAssertTrue(map[color2]!)
        XCTAssertNil(map[color3])
    }
}
