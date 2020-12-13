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
        XCTAssertEqual("One", str1.string)
        XCTAssertEqual(#"String("One")"#, "\(str1)")

        let str2 = SassString("Two", isQuoted: false)
        XCTAssertEqual("Two", str2.string)
        XCTAssertEqual("String(Two)", "\(str2)")

        XCTAssertTrue(str1.isTruthy)
        XCTAssertFalse(str1.isNull)
    }

    func testIndex() throws {
        let strBasic = SassString("Fred")
        XCTAssertEqual(strBasic.sassLength, 4)
        let strEmoji = SassString("😄")
        XCTAssertEqual(strEmoji.sassLength, 1)
        let flagEmoji = SassString("🇦🇶")
        XCTAssertEqual(flagEmoji.sassLength, 2)

        let eIndex = try strBasic.scalarIndexFrom(sassIndex: SassNumber(3))
        let letter = strBasic.string.unicodeScalars[eIndex]
        XCTAssertEqual("e", letter)
        do {
            let v = try strEmoji.scalarIndexFrom(sassIndex: SassNumber(0))
            XCTFail("Bad index OK: \(v)")
        } catch {
            print(error)
        }

        let ALindex = try flagEmoji.scalarIndexFrom(sassIndex: SassNumber(-2))
        let symbol = flagEmoji.string.unicodeScalars[ALindex]
        XCTAssertEqual("🇦", symbol)
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

        XCTAssertNotEqual(str1, SassList([str1]))
    }

    func testDowncast() throws {
        let str = SassString("String")
        let str2 = try str.asString()
        XCTAssertTrue(str === str2)

        let list = SassList([])
        do {
            let str3 = try list.asString()
            XCTFail("Made string out of list: \(str3)")
        } catch let error as SassFunctionError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Really a SassValue test - all the singleton not-list lists.
    func testListView() throws {
        let str = SassString("AString")
        XCTAssertEqual(.undecided, str.separator)
        XCTAssertEqual(false, str.hasBrackets)

        let listView = Array(str)
        XCTAssertEqual(1, listView.count)
        XCTAssertEqual(str, listView[0])
        XCTAssertTrue(str === listView[0])
    }
}
