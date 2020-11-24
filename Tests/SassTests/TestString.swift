//
//  TestString.swift
//  SassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import Sass

/// Tests for `SassString`
///
class TestString: XCTestCase {
    func testProperties() {
        let str1 = SassString("One")
        XCTAssertEqual("One", str1.text)
        XCTAssertEqual(#"String("One")"#, "\(str1)")

        let str2 = SassString("Two", isQuoted: false)
        XCTAssertEqual("Two", str2.text)
        XCTAssertEqual("String(Two)", "\(str2)")
    }

    func testIndex() {
        let strBasic = SassString("Fred")
        XCTAssertEqual(strBasic.sassLength, 4)
        let strEmoji = SassString("😄")
        XCTAssertEqual(strEmoji.sassLength, 1)
        let flagEmoji = SassString("🇦🇶")
        XCTAssertEqual(flagEmoji.sassLength, 2)

        // TODO: indexes when we can understand numbers...
    }

    func testEqualityAndHashing() {
        let str1 = SassString("One")
        let str2 = SassString("One")
        XCTAssertEqual(str1, str2)
        let str3 = SassString("One", isQuoted: false)
        XCTAssertEqual(str1, str3)

        var map = [SassString:String]()
        map[str1] = "Fish"
        XCTAssertEqual("Fish", map[str3])
    }

    func testDowncast() throws {
        let str = SassString("String")
        let str2 = try str.asString()
        XCTAssertTrue(str === str2)

        // TODO: failure when we can have things other than strings...
    }
}
