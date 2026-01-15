//
//  TestList.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Testing
import Sass

/// Tests for `SassList` and `SassArgumentList`
///
class TestList {
    @Test
    func testBrackets() {
        let with = SassList([SassConstants.null])
        #expect("List([Null])" == with.description)
        let without = SassList([SassConstants.null], hasBrackets: false)
        #expect("List(Null)" == without.description)

        #expect(with != without)
    }

    @Test
    func testSeparator() {
        let str = SassString("str")
        let spaces = SassList([str, str], separator: .space)
        #expect(#"List([String("str") String("str")])"# == spaces.description)

        let undefEmpty = SassList([], separator: .undecided)
        #expect(.undecided == undefEmpty.separator)

        let undefSingle = SassList([str], separator: .undecided)
        #expect(.undecided == undefSingle.separator)

        let undefMulti = SassList([str, str], separator: .undecided)
        #expect(.undecided != undefMulti.separator)
    }

    @Test
    func testIteration() throws {
        let str1 = SassString("str1")
        let str2 = SassString("str2")
        let list = SassList([str1, str2])
        let array = Array(list)
        #expect(array.count == 2)
        #expect(array == [str1, str2])

        #expect(try str2 == list.valueAt(sassIndex: SassNumber(-1)))
    }

    /// List equality -- incorporating deviation from dart-sass for empty lists...
    @Test
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

        #expect(empty1 == empty2)
        #expect(empty2 == empty3)
        #expect(empty1 == empty3)

        #expect(nEmpty1 != nEmpty2)
        #expect(nEmpty1 != nEmpty3a)

        #expect(nEmpty3a == nEmpty3b)

        var dict = [SassValue:Int]()
        dict[empty1] = 1
        dict[empty2] = 2
        #expect(2 == dict[empty1])
        #expect(2 == dict[empty2])
        dict[nEmpty3a] = 3
        #expect(3 == dict[nEmpty3b])
    }

    /// Argument lists
    @Test
    func testArgumentList() throws {
        let baseList = SassArgumentList([SassString("str")])

        #expect(try baseList == baseList.asArgumentList())
        #expect(throws: SassFunctionError.self) { try SassConstants.true.asArgumentList() }

        #expect(try "str" == baseList.valueAt(sassIndex: SassNumber(1)).asString().string)
        let realList = SassList([SassString("str")], hasBrackets: false)
        #expect(baseList == realList)
        let baseListDesc = baseList.description
        #expect(baseListDesc.starts(with: "ArgList"))
        #expect(baseListDesc.contains("String(\"str\")"))
        #expect(baseListDesc.contains("kw()"))

        #expect(baseList.keywords.isEmpty)
    }

    @Test
    func testArgumentListKeywords() throws {
        var observerCallCount = 0
        let kwList = SassArgumentList([],
                                      keywords: ["one" : SassNumber(100)],
                                      keywordsObserver: { observerCallCount += 1 })
        #expect(0 == observerCallCount)
        let kwVal = try #require(kwList.keywords["one"])
        #expect(1 == observerCallCount)
        #expect(try 100 == kwVal.asNumber().double)

        #expect(nil == kwList.keywords["two"])
        #expect(2 == observerCallCount)

        let kwListDesc = kwList.description
        #expect(2 == observerCallCount)
        #expect(kwListDesc.contains("kw([one:Number"))

        /// Odd equality shenanigans
        let kwList2 = SassArgumentList([], keywords: ["two" : SassNumber(100)])
        #expect(kwList == kwList2)

        let dict = [kwList: true]
        let value = dict[kwList2] as Bool?
        #expect(value != nil)
        #expect(value!)
    }
}
