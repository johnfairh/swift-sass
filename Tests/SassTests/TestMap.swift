//
//  TestMap.swift
//  SassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import Sass

/// Tests for `SassMap`
///
class TestMap: XCTestCase {
    /// Dictionary wrapping
    func testDictionary() {
        let kv = [(SassString("Key1"), SassString("Value1")),
                  (SassString("Key2"), SassString("Value2"))]
        let map1 = SassMap(Dictionary(uniqueKeysWithValues: kv))
        let map2 = SassMap(uniqueKeysWithValues: kv)

        XCTAssertEqual(.comma, map1.separator)
        XCTAssertFalse(map1.hasBrackets)
        XCTAssertEqual(SassString("Value1"), map1[SassString("Key1")])

        XCTAssertEqual(map1, map2)
        let dict = [map1 : true]
        XCTAssertEqual(true, dict[map2])

        let strView = map1.description
        XCTAssertTrue(strView.hasPrefix("Map([List"))
        XCTAssertTrue(strView.hasSuffix(")])])"))
        XCTAssertTrue(strView.contains(#"List([String("Key2") String("Value2")])"#))
        XCTAssertTrue(strView.contains(#"List([String("Key1") String("Value1")])"#))
    }

    /// Empty
    func testEmpty() {
        let emptyMap = SassMap([:])
        XCTAssertEqual(.undecided, emptyMap.separator)
        XCTAssertEqual(0, Array(emptyMap).count)
    }

    /// List view
    func testListView() throws {
        let map = SassMap([SassString("KeyA") : SassConstants.true,
                           SassString("KeyB") : SassConstants.false,
                           SassString("KeyC") : SassConstants.true])

        var count = 0
        try map.forEach { kvList in
            count += 1
            let kvArray = Array(kvList)
            XCTAssertEqual(2, kvArray.count)
            let key = try kvArray[0].asString()
            let val = try kvArray[1].asBool()
            XCTAssertTrue(val.isTruthy || key.string == "KeyB")
        }
        XCTAssertEqual(3, count)

        let somePair = try map.valueAt(sassIndex: SassNumber(2))
        XCTAssertEqual(2, Array(somePair).count)
    }

    /// Empty list-map equivalence
    func testListMapEquivalance() throws {
        let emptyList = SassList([])
        let emptyMap = SassMap([:])

        let nonEmptyList = SassList([SassConstants.null])
        let nonEmptyMap = SassMap([SassString("key") : SassConstants.false])

        XCTAssertEqual(emptyList, emptyMap)
        XCTAssertEqual(emptyMap, emptyList)
        XCTAssertNotEqual(emptyList, nonEmptyMap)
        XCTAssertNotEqual(nonEmptyMap, emptyList)
        XCTAssertNotEqual(nonEmptyList, emptyMap)
        XCTAssertNotEqual(emptyMap, nonEmptyList)

        var dict = [SassValue : Int]()
        dict[emptyMap] = 23
        XCTAssertEqual(23, dict[emptyList])
        XCTAssertEqual(23, dict[emptyMap])
    }

    /// Downcast
    func testDowncasts() throws {
        let val1: SassValue = SassMap([SassConstants.true : SassConstants.null])
        XCTAssertNotNil(try val1.asMap())

        let val2: SassValue = SassList([])
        XCTAssertNotNil(try val2.asMap())

        let val3: SassValue = SassList([SassString("string")])
        XCTAssertThrowsError(try val3.asMap())
    }
}
