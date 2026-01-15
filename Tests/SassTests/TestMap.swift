//
//  TestMap.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Testing
import Sass

/// Tests for `SassMap`
///
class TestMap {
    /// Dictionary wrapping
    @Test
    func testDictionary() {
        let kv = [(SassString("Key1"), SassString("Value1")),
                  (SassString("Key2"), SassString("Value2"))]
        let map1 = SassMap(Dictionary(uniqueKeysWithValues: kv))
        let map2 = SassMap(uniqueKeysWithValues: kv)

        #expect(.comma == map1.separator)
        #expect(!map1.hasBrackets)
        #expect(SassString("Value1") == map1[SassString("Key1")])

        #expect(map1 == map2)
        let dict = [map1 : true]
        #expect(true == dict[map2])

        let strView = map1.description
        #expect(strView.hasPrefix("Map([List"))
        #expect(strView.hasSuffix(")])])"))
        #expect(strView.contains(#"List([String("Key2") String("Value2")])"#))
        #expect(strView.contains(#"List([String("Key1") String("Value1")])"#))
    }

    /// Empty
    @Test
    func testEmpty() {
        let emptyMap = SassMap([:])
        #expect(.undecided == emptyMap.separator)
        #expect(0 == Array(emptyMap).count)
    }

    /// List view
    @Test
    func testListView() throws {
        let map = SassMap([SassString("KeyA") : SassConstants.true,
                           SassString("KeyB") : SassConstants.false,
                           SassString("KeyC") : SassConstants.true])

        var count = 0
        try map.forEach { kvList in
            count += 1
            let kvArray = Array(kvList)
            #expect(2 == kvArray.count)
            let key = try kvArray[0].asString()
            let val = try kvArray[1].asBool()
            #expect(val.isTruthy || key.string == "KeyB")
        }
        #expect(3 == count)

        let somePair = try map.valueAt(sassIndex: SassNumber(2))
        #expect(2 == Array(somePair).count)
    }

    /// Empty list-map equivalence
    @Test
    func testListMapEquivalance() throws {
        let emptyList = SassList([])
        let emptyMap = SassMap([:])

        let nonEmptyList = SassList([SassConstants.null])
        let nonEmptyMap = SassMap([SassString("key") : SassConstants.false])

        #expect(emptyList == emptyMap)
        #expect(emptyMap == emptyList)
        #expect(emptyList != nonEmptyMap)
        #expect(nonEmptyMap != emptyList)
        #expect(nonEmptyList != emptyMap)
        #expect(emptyMap != nonEmptyList)

        var dict = [SassValue : Int]()
        dict[emptyMap] = 23
        #expect(23 == dict[emptyList])
        #expect(23 == dict[emptyMap])
    }

    /// Downcast
    @Test
    func testDowncasts() throws {
        let val1: SassValue = SassMap([SassConstants.true : SassConstants.null])

        #expect(throws: Never.self) {
            _ = try val1.asMap()

            let val2: SassValue = SassList([])
            _ = try val2.asMap()
        }

        #expect(throws: SassFunctionError.self) {
            let val3: SassValue = SassList([SassString("string")])
            _ = try val3.asMap()
        }
    }
}
