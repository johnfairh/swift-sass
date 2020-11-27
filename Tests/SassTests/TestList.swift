//
//  TestList.swift
//  SassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import Sass

/// Tests for `SassList`
///
class TestList: XCTestCase {
    func testBrackets() {
        let with = SassList([SassConstants.null])
        XCTAssertEqual("List([Null])", with.description)
        let without = SassList([SassConstants.null], hasBrackets: false)
        XCTAssertEqual("List(Null)", without.description)

        XCTAssertNotEqual(with, without)
    }

    func testSeparator() {
        let str = SassString("str")
        let spaces = SassList([str, str], separator: .space)
        XCTAssertEqual(#"List([String("str") String("str")])"#, spaces.description)

        let undefEmpty = SassList([], separator: .undecided)
        XCTAssertEqual(.undecided, undefEmpty.separator)

        let undefSingle = SassList([str], separator: .undecided)
        XCTAssertEqual(.undecided, undefSingle.separator)

        let undefMulti = SassList([str, str], separator: .undecided)
        XCTAssertNotEqual(.undecided, undefMulti.separator)
    }

    func testIteration() {
        let str1 = SassString("str1")
        let str2 = SassString("str2")
        let list = SassList([str1, str2])
        let array = Array(list)
        XCTAssertEqual(2, array.count)
        XCTAssertEqual([str1, str2], array)

        XCTAssertEqual(str2, try list.valueAt(sassIndex: SassNumber(-1)))
    }

    /// List equality -- incorporating deviation from dart-sass for empty lists...
    func testEquality() {
        let empty1 = SassList([])
        let empty2 = SassList([], hasBrackets: false)
        let empty3 = SassList([], separator: .undecided)
        let str1 = SassString("str1")
        let str2 = SassString("str2")
        let nEmpty1 = SassList([str1])
        let nEmpty2 = SassList([str2])
        let nEmpty3a = SassList([empty1, str1])
        let nEmpty3b = SassList([empty1, str1])

        XCTAssertEqual(empty1, empty2)
        XCTAssertEqual(empty2, empty3)
        XCTAssertEqual(empty1, empty3)

        XCTAssertNotEqual(nEmpty1, nEmpty2)
        XCTAssertNotEqual(nEmpty1, nEmpty3a)

        XCTAssertEqual(nEmpty3a, nEmpty3b)

        var dict = [SassValue:Int]()
        dict[empty1] = 1
        dict[empty2] = 2
        XCTAssertEqual(2, dict[empty1])
        XCTAssertEqual(2, dict[empty2])
        dict[nEmpty3a] = 3
        XCTAssertEqual(3, dict[nEmpty3b])
    }
}
