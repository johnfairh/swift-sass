//
//  Value.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Base class for Sass value behaviour.  Some uncomfortable bits in Swift
// but using protocols right now runs into the whole 'existentials-aren't-
// really-types' mess.
//
// Give the concrete type names a `Sass` prefix to avoid tedious collisions
// with stdlib types.

/// Common behavior between values passed to or returned from Sass functions.
///
/// All Sass values can be treated as lists: singleton values like strings behave like
/// 1-element lists and maps behave like lists of two-element (key, value) lists.
public class SassValue: Hashable, Sequence, CustomStringConvertible {
    /// Sass considers all values except `null` and `false` to be "truthy", meaning
    /// your host function should almost always be checking this property instead of trying
    /// to downcast to `SassBool`.
    public var isTruthy: Bool { true }

    /// Does this value represent Sass's `null` value?
    public var isNull: Bool { false }

    // MARK: Listiness

    /// The list separator used by this value when viewed as a list.
    public var separator: SassList.Separator { .undecided }

    /// Is this value, viewed as a list, surrounded by brackets?
    public var hasBrackets: Bool { false }

    /// Not public, used to optimize `arrayIndexFrom(sassIndex:)`.
    var listCount: Int { 1 }

    /// Convert a Sass list index.
    /// - parameter index: A Sass value intended to be used as an index into this value viewed as a list.
    ///   This must be an integer between 1 and the number of elements in this value viewed as a list.
    /// - throws: `SassValueError` if `index` is not an integer or out of range.
    /// - returns: An integer suitable for subscripting the array created from this value, guaranteed
    ///   to be a valid subscript.
    public func arrayIndexFrom(sassIndex: SassValue) throws -> Int {
        /// let indexValue = try Int(sassIndex.asNumber())
        /// guard indexValue >= 1 && indexValue <= listCount else {
        ///     throw SassValueError.subscriptType(sassIndex)
        /// }
        /// return indexValue - 1
        throw SassValueError.subscriptType(sassIndex)
    }

    /// Subscript the value using a Sass list index.
    ///
    /// (Swift can't throw exceptions from `subscript`).
    /// - parameter sassIndex: A Sass value intended to be used as an index into this value viewed as a list.
    ///   This must be an integer between 1 and `asArray.count` inclusive.
    /// - throws: `SassValueError` if `index` is not an integer or out of range.
    /// - returns: The value at the Sass Index.
    public func valueAt(sassIndex: SassValue) throws -> SassValue {
        _ = try arrayIndexFrom(sassIndex: sassIndex)
        return self
    }

    /// An iterator for the values in the list.
    public func makeIterator() -> AnyIterator<SassValue> {
        AnyIterator(CollectionOfOne(self).makeIterator())
    }

    // MARK: Visitor

    /// Call the corresponding method of `visitor` against this object.
    public func accept<V, R>(visitor: V) throws -> R where V: SassValueVisitor, R == V.ReturnType {
        preconditionFailure()
    }

    // MARK: Hashable

    /// Two `SassValue`s are generally equal if they have the same dynamic type and
    /// compare equally as that type.
    public static func == (lhs: SassValue, rhs: SassValue) -> Bool {
        switch (lhs, rhs) {
        case let (lstr, rstr) as (SassString, SassString):
            return lstr == rstr
        case let (llist, rlist) as (SassList, SassList):
            return llist == rlist
        case let (lmap, rmap) as (SassMap, SassMap):
            return lmap == rmap
        case let (map, list) as (SassMap, SassList),
             let (list, map) as (SassList, SassMap):
            return list.listCount == 0 && map.listCount == 0
        case let (lbool, rbool) as (SassBool, SassBool):
            return lbool == rbool
        case let (lnull, rnull) as (SassNull, SassNull):
            return lnull == rnull // ...
        default:
            return false
        }
    }

    /// `SassValue` can be used as a dictionary key.
    public func hash(into hasher: inout Hasher) {
    }

    // MARK: CustomStringConvertible

    /// A short description of the value.
    public var description: String {
        preconditionFailure()
    }
}

// MARK: Visitor

/// A protocol for implementing polymorphic operations over `SassValue` objects.
public protocol SassValueVisitor {
    /// The return type of the operation.
    associatedtype ReturnType
    /// The operation for `SassString`
    func visit(string: SassString) throws -> ReturnType
    /// The operation for `SassList`
    func visit(list: SassList) throws -> ReturnType
    /// The operation for `SassMap`
    func visit(map: SassMap) throws -> ReturnType
    /// The operation for `SassBool`
    func visit(bool: SassBool) throws -> ReturnType
    /// The operation for `SassNull`
    func visit(null: SassNull) throws -> ReturnType
}

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
