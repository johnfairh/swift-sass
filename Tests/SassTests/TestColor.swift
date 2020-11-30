//
//  TestColor.swift
//  SassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import Sass // color implementation bits

func XCTAssertHslIntEqual(_ lhs: HslColor, _ rhs: HslColor) {
    XCTAssertEqual(Int(lhs.hue.rounded()), Int(rhs.hue.rounded()))
    XCTAssertEqual(Int(lhs.saturation.rounded()), Int(rhs.saturation.rounded()))
    XCTAssertEqual(Int(lhs.lightness.rounded()), Int(rhs.lightness.rounded()))
}

class TestColor: XCTestCase {
    let rgbBlack = try! RgbColor(red: 0, green: 0, blue: 0)
    let hslBlack = try! HslColor(hue: 0, saturation: 0, lightness: 0)

    let rgbRed = try! RgbColor(red: 255, green: 0, blue: 0)
    let hslRed = try! HslColor(hue: 0, saturation: 100, lightness: 50)

    let rgbGreen = try! RgbColor(red: 0, green: 255, blue: 0)
    let hslGreen = try! HslColor(hue: 120, saturation: 100, lightness: 50)

    let rgbBlue = try! RgbColor(red: 0, green: 0, blue: 255)
    let hslBlue = try! HslColor(hue: 240, saturation: 100, lightness: 50)

    let rgbPink = try! RgbColor(red: 246, green: 142, blue: 227)
    let hslPink = try! HslColor(hue: 311, saturation: 85, lightness: 76)

    // carefully pick colors that don't suffer los along the trip :(

    private func checkConversion(_ rgb: RgbColor, _ hsl: HslColor) {
        XCTAssertHslIntEqual(hsl, HslColor(rgb))
        XCTAssertEqual(rgb, RgbColor(hsl))
    }

    func testRgbHslConversion() throws {
        checkConversion(rgbBlack, hslBlack)
        checkConversion(rgbRed, hslRed)
        checkConversion(rgbGreen, hslGreen)
        checkConversion(rgbBlue, hslBlue)
        checkConversion(rgbPink, hslPink)
    }

    func testRangeChecking() throws {
        do {
            let col = try SassColor(red: -1, green: 0, blue: 0)
            XCTFail("Bad color \(col)")
        } catch {
            print(error)
        }
        do {
            let col = try SassColor(red: 0, green: 0, blue: 0, alpha: 100)
            XCTFail("Bad color \(col)")
        } catch {
            print(error)
        }
        do {
            let col = try SassColor(hue: 100, saturation: 200, lightness: 0.8)
            XCTFail("Bad color \(col)")
        } catch {
            print(error)
        }

    }

    // Construction, tostring, asColor
    // Equality, hashing
    // Channel modification & get
    // (fns -> roundtrips)
}
