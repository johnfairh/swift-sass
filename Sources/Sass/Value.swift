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
//
// Declared open so that DynamicFunction can be open which enables NIO-compatible
// specializations (for example) in compiler adapters.

/// Common behavior between values passed to or returned from Sass functions.
///
/// All Sass values can be treated as lists: singleton values like strings behave like
/// 1-element lists and maps behave like lists of two-element (key, value) lists.  Use the
/// `Sequence` conformance to access the list contents.
///
/// `SassValue` is abstract, you cannot create instances. Instead create instances of subtypes
/// like `SassColor`.
///
/// All the `SassValue` types are immutable.
open class SassValue: Hashable, Sequence, CustomStringConvertible {
    /// stop anyone else actually subclassing this
    init() {}

    /// Sass considers all values except `null` and `false` to be "truthy", meaning
    /// your function should almost always be checking this property instead of trying
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
    ///   This must be an integer between 1 and the number of elements inclusive, or negative in the same
    ///   range to index from the end.
    /// - throws: `SassFunctionError` if `sassIndex` is not an integer or out of range.
    /// - returns: An integer suitable for subscripting the array created from this value, guaranteed
    ///   to be a valid subscript in the range [0..<count]
    public func arrayIndexFrom(sassIndex: SassValue) throws -> Int {
        let indexValue = try sassIndex.asNumber().asInt()
        guard indexValue.magnitude >= 1 && indexValue.magnitude <= listCount else {
            throw SassFunctionError.badListIndex(max: listCount, actual: indexValue)
        }
        return indexValue > 0 ? (indexValue - 1) : (listCount + indexValue)
    }

    /// Subscript the value using a Sass list index.
    ///
    /// (Swift can't throw exceptions from `subscript`).
    /// - parameter sassIndex: A Sass value intended to be used as an index into this value viewed
    ///   as a list.  This must be an integer between 1 and the number of elements inclusive, or a negative
    ///   number with similar magnitude to index back from the end.
    /// - throws: `SassValueError` if `index` is not an integer or out of range.
    /// - returns: The value at the Sass Index.
    public func valueAt(sassIndex: SassValue) throws -> SassValue {
        _ = try arrayIndexFrom(sassIndex: sassIndex)
        return self
    }

    /// An iterator for the values in the list, for `Sequence` conformance.
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
    /// compare equally as that type.  In addition, empty lists and maps compare as equal.
    public static func == (lhs: SassValue, rhs: SassValue) -> Bool {
        switch (lhs, rhs) {
        case let (lstr, rstr) as (SassString, SassString):
            return lstr == rstr
        case let (lnum, rnum) as (SassNumber, SassNumber):
            return lnum == rnum
        case let (lcol, rcol) as (SassColor, SassColor):
            return lcol == rcol
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
            return lnull == rnull
        case let (lcfunc, rcfunc) as (SassCompilerFunction, SassCompilerFunction):
            return lcfunc == rcfunc
        case let (ldfunc, rdfunc) as (SassDynamicFunction, SassDynamicFunction):
            return ldfunc == rdfunc
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
    /// The operation for `SassString`.
    func visit(string: SassString) throws -> ReturnType
    /// The operation for `SassNumber`.
    func visit(number: SassNumber) throws -> ReturnType
    /// The operation for `SassColor`.
    func visit(color: SassColor) throws -> ReturnType
    /// The operation for `SassList`.
    func visit(list: SassList) throws -> ReturnType
    /// The operation for `SassMap`.
    func visit(map: SassMap) throws -> ReturnType
    /// The operation for `SassBool`.
    func visit(bool: SassBool) throws -> ReturnType
    /// The operation for `SassNull`.
    func visit(null: SassNull) throws -> ReturnType
    /// The operation for `SassCompilerFunction`.
    func visit(compilerFunction: SassCompilerFunction) throws -> ReturnType
    /// The operation for `SassDynamicFunction` (or `SassAsyncDynamicFunction`).
    func visit(dynamicFunction: SassDynamicFunction) throws -> ReturnType
}
