//
//  SassValue.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// Common behavior between SassScript values passed to or returned from custom functions.
///
/// The Sass compiler lets you define custom functions written Swift that are available to
/// stylesheets as they are compiled.  `SassValue` is used to transmit function parameters
/// and return values.  Usually the first job of your custom function is to downcast each parameter
/// to the expected type using methods like `SassValue.asString(...)`.
///
/// All Sass values can be treated as lists: singleton values like strings behave like
/// 1-element lists and maps behave like lists of pairs. [XXX wait, what is a 'pair'???]
open class SassValue: Hashable, Sequence, CustomStringConvertible {
    /// The list separator used by this value when viewed as a list.
    public var separator: SassList.Separator { .undecided }

    /// Whether this value, viewed as a list, is surrounded by brackets.
    public var hasBrackets: Bool { false }

    /// Not public, used to optimize `arrayIndexFrom(sassIndex:)`.
    var listCount: Int { 1 }

    /// Interpret a Sass list index.
    /// - parameter index: A Sass value intended to be used as an index into this value viewed as a list.
    ///   This must be an integer between 1 and the number of elements in this value viewed as a list.
    /// - throws: `SassValueError` if `index` is not an integer or out of range.
    /// - returns: An integer suitable for subscripting the array created from this value.
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

    /// Call the corresponding method of `visitor` against this object.
    public func accept<V, R>(visitor: V) throws -> R where V: SassValueVisitor, R == V.ReturnType {
        preconditionFailure()
    }

    public static func == (lhs: SassValue, rhs: SassValue) -> Bool {
        switch (lhs, rhs) {
        case let (lstr, rstr) as (SassString, SassString):
            return lstr == rstr
        case let (llist, rlist) as (SassList, SassList):
            return llist == rlist
        default:
            return false
        }
    }

    /// :nodoc:
    public func hash(into hasher: inout Hasher) {
        preconditionFailure()
    }

    /// :nodoc:
    public var description: String {
        preconditionFailure()
    }
}

// MARK: Visitor

/// A protocol for implementing polymorphic operations over `SassValue` objects.
public protocol SassValueVisitor {
    /// The return type of the operation.
    associatedtype ReturnType
    /// The operation for `SassString`s.
    func visit(string: SassString) throws -> ReturnType
    /// The operation for `SassList`s.
    func visit(list: SassList) throws -> ReturnType
}

// MARK: Errors

/// Errors thrown for common `SassValue` scenarios.
///
/// Generally you will throw these out of your custom function and the compilation will
/// fail with the details of this error as the reason.
public enum SassValueError: Error, CustomStringConvertible {
    /// A Sass value was not the expected type.
    case wrongType(expected: String, actual: SassValue)
    /// A Sass value used as a list or string index was not an integer.
    case subscriptType(SassValue)
    /// A Sass value used as a list or string index was out of range.
    case subscriptIndex(max: Int, actual: Int)

    /// A human-readable description of the error.
    public var description: String {
        switch self {
        case let .wrongType(expected: expected, actual: actual):
            return "Value has wrong type, expected \(expected) but got \(actual)."
        case let .subscriptType(actual):
            return "Non-integer value used as index: \(actual)."
        case let .subscriptIndex(max: max, actual: actual):
            return "Index \(actual) out of range: valid range is 1...\(max)."
        }
    }
}

// MARK: Functions

/// The Swift type of a SassScript function.
/// Any parameters with default values are instantiated before the function is called.
public typealias SassFunction = ([SassValue]) throws -> SassValue

/// A set of `SassFunction`s and their signatures.
///
/// The string in each pair must be a valid Sass function signature that could appear after
/// `@function` in a Sass stylesheet, such as `mix($color1, $color2, $weight: 50%)`.
public typealias SassFunctionMap = [String : SassFunction]

extension String {
    /// Get the Sass function name (everything before the paren) from a signature. :nodoc:
    public var sassFunctionName: String {
        String(prefix(while: { $0 != "("}))
    }
}

extension Dictionary where Key == String {
    /// Remap a Sass function signature dictionary to be keyed by Sass function name with
    /// elements the (signature, callback) tuple.  :nodoc:
    public var asSassFunctionNameElementMap: [String: Self.Element] {
        Dictionary<String, Self.Element>(uniqueKeysWithValues: map { ($0.key.sassFunctionName, $0) })
    }
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
