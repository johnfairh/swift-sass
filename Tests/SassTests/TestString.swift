//
//  TestString.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Testing
import Sass

struct TestString {
    @Test
    func properties() {
        let str1 = SassString("One")
        #expect(str1.string == "One")
        #expect("\(str1)" == #"String("One")"#)

        let str2 = SassString("Two", isQuoted: false)
        #expect(str2.string == "Two")
        #expect("\(str2)" == "String(Two)")

        #expect(str1.isTruthy)
        #expect(!str1.isNull)
    }

    @Test
    func index() throws {
        let strBasic = SassString("Fred")
        #expect(strBasic.sassLength == 4)
        let strEmoji = SassString("😄")
        #expect(strEmoji.sassLength == 1)
        let flagEmoji = SassString("🇦🇶")
        #expect(flagEmoji.sassLength == 2)

        let eIndex = try strBasic.scalarIndexFrom(sassIndex: SassNumber(3))
        let letter = strBasic.string.unicodeScalars[eIndex]
        #expect("e" == letter)
        do {
            let v = try strEmoji.scalarIndexFrom(sassIndex: SassNumber(0))
            Issue.record("Bad index OK: \(v)")
        } catch {
            // expected error; nothing to record
        }

        let ALindex = try flagEmoji.scalarIndexFrom(sassIndex: SassNumber(-2))
        let symbol = flagEmoji.string.unicodeScalars[ALindex]
        #expect("🇦" == symbol)
    }

    @Test
    func equalityAndHashing() {
        let str1 = SassString("One")
        let str2 = SassString("One")
        #expect(str1 == str2)
        let str3 = SassString("One", isQuoted: false)
        #expect(str1 == str3)

        var map = [SassString:String]()
        map[str1] = "Fish"
        #expect(map[str3] == "Fish")

        #expect(str1 != SassList([str1]))
    }

    @Test
    func downcast() throws {
        let str = SassString("String")
        let str2 = try str.asString()
        #expect(str === str2)

        let list = SassList([])
        do {
            let str3 = try list.asString()
            Issue.record("Made string out of list: \(str3)")
        } catch let error as SassFunctionError {
            // expected error; nothing to record
            _ = error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func listView() {
        let str = SassString("AString")
        #expect(str.separator == .undecided)
        #expect(str.hasBrackets == false)

        let listView = Array(str)
        #expect(str.listCount == 1)
        #expect(listView.count == 1)
        #expect(str == listView[0])
        #expect(str === listView[0])
    }
}
