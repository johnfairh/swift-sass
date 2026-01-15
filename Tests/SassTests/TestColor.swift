//
//  TestColor.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Testing
@_spi(SassCompilerProvider) import Sass

// Drastically cut down for Color 4 while we can't convert between spaces

struct TestColor {
    @Test
    func testRangeChecking() {
        func check(_ maker: @autoclosure () throws -> SassColor) {
            do {
                let col = try maker()
                Issue.record("Bad color \(col)")
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
        #expect(colRgb.space == .rgb)
        #expect(r == Int(colRgb.channel1!))
        #expect(g == Int(colRgb.channel2!))
        #expect(b == Int(colRgb.channel3!))
        #expect(a == colRgb.alpha!)
    }

    private func check(hsl colHsl: SassColor, _ h: Double, _ s: Double, _ l: Double, _ a: Double) {
        #expect(colHsl.space == .hsl)
        #expect(h == colHsl.channel1!)
        #expect(s == colHsl.channel2!)
        #expect(l == colHsl.channel3!)
        #expect(a == colHsl.alpha!)
    }

    private func check(hwb colHwb: SassColor, _ h: Double, _ w: Double, _ b: Double, _ a: Double) {
        #expect(colHwb.space == .hwb)
        #expect(h == colHwb.channel1!)
        #expect(w == colHwb.channel2!)
        #expect(b == colHwb.channel3!)
        #expect(a == colHwb.alpha!)
    }

    @Test
    func testValueBehaviours() {
        let colRgb = try! SassColor(red: 12, green: 20, blue: 100, alpha: 0.5)
        check(rgb: colRgb, 12, 20, 100, 0.5)
        #expect("Color(rgb [12.0, 20.0, 100.0] a=0.5)" == colRgb.description)

        let colHsl = try! SassColor(hue: 190, saturation: 20, lightness: 95, alpha: 0.9)
        check(hsl: colHsl, 190, 20, 95, 0.9)
        #expect("Color(hsl [190.0, 20.0, 95.0] a=0.9)" == colHsl.description)

        let colHwb = try! SassColor(hue: 95, whiteness: 18, blackness: 45, alpha: 0.3)
        check(hwb: colHwb, 95, 18, 45, 0.3)
        #expect("Color(hwb [95.0, 18.0, 45.0] a=0.3)" == colHwb.description)

        let val: SassValue = colRgb
        do {
            _ = try val.asColor()
        } catch {
            Issue.record("asColor threw unexpectedly: \(error)")
        }
        #expect(throws: Error.self) {
            _ = try SassConstants.true.asColor()
        }

        #expect(colRgb == colRgb)
//        let colHsl2 = try SassColor(hue: colRgb.hue,
//                                    saturation: colRgb.saturation,
//                                    lightness: colRgb.lightness,
//                                    alpha: colRgb.alpha)
//        #expect(colRgb == colHsl2)

        let dict = [colRgb: true]
        #expect(dict[try! val.asColor() /*colHsl2*/] == true)
    }

    @Test
    func testMissingChannels() {
        let color = SassColor(space: .displayP3, nil, nil, nil, alpha: nil)
        #expect("Color(displayP3 [missing, missing, missing] a=missing)" == color.description)

        let color2 = color
        #expect(color2 == color)

        let color3 = SassColor(space: .displayP3, 1.0, nil, nil, alpha: nil)
        #expect(color3 != color)

        var map = [SassColor:Bool]()
        map[color] = true
        #expect(map[color2] == true)
        #expect(map[color3] == nil)
    }
}
