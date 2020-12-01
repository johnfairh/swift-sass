//
//  ValueConvertible.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// TODO later on - a marker and conversion protocol to be adopted by all the Swift
// common-currency types.  The benefit of doing this for the Sass use-case is, I
// think, wholely around writing collection literals -- it means you don't need to
// manually wrap everything up in SassValue types, but instead can do
// SassList([1, 2, someString, myDouble, ["another", "nested", "list"]) - which
// seems valuable.

//protocol SassValueConvertible {a
//    init(_ value: SassValue) throws
//    var sassValue: SassValue { get }
//}
//
//extension SassNumber {
//    init<I: BinaryInteger>() throws {
//    }
//    func asBinaryInteger<I: BinaryInteger>() throws -> I {
//        let weirdDoubleValue: Double = dblVal
//        guard let myInt = I(exactly: intValue) else {
//            throw "Int dont fit"
//        }
//        return myInt
//    }
//}
//
//extension BinaryInteger {
//    init(_ value: SassValue) throws {
//        guard let numValue = value as SassNumber else {
//            throw SassValueError.wrongType(expected: "SassNumber", actual: value)
//        }
//        self = try numValue.toInt()
//    }
//
//    var sassValue: SassValue {
//        SassNumber(self)
//    }
//}
//
//extension UInt32: SassValueConvertible {}
