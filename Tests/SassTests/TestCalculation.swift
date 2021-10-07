//
//  TestCalculation.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import Sass

/// Calculations
class TestCalculation: XCTestCase {
    func testPlaceholder() {
        let c1 = SassCalculation(kind: .calc, arguments: [])
        let c2 = SassCalculation(kind: .clamp, arguments: [])
        XCTAssertNotEqual(c1, c2)
    }
}
