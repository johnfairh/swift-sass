//
//  Function.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// The Swift type of a Sass function.
///
/// Use this to define Sass functions written in Swift that are available to stylesheets as they
/// are compiled.
///
/// `SassValue` is used to transmit function parameters and return values: any parameters with
/// default values are instantiated before the function is called.  All `SassValue`s are immutable.
///
/// Usually the first job of a function is to downcast each parameter to the expected type.  You can
/// convert directly to Swift native types using initializers like `String(_:)`,  but this loses any
/// additional metadata such as units and list punctuation that is tracked by the Sass type: if you need
/// this metadata then downcast to the specific Sass type using methods like `SassValue.asString(...)`.
///
/// Any error thrown from the function ends up cancelling the compilation job and returning an
/// error message back to the user that contains the text of the error thrown.
///
/// All Sass functions return a value -- there is no `void` return type.  Create new `SassValue`
/// objects using a subclass initializer such as `SassString(_:isQuoted:)`.
///
public typealias SassFunction = ([SassValue]) throws -> SassValue

/// A set of `SassFunction`s and their signatures.
///
/// The string in each pair must be a valid Sass function signature that could appear after
/// `@function` in a Sass stylesheet, such as `mix($color1, $color2, $weight: 50%)`.
public typealias SassFunctionMap = [String : SassFunction]

extension String {
    /// Get the Sass function name (everything before the paren) from a signature. :nodoc:
    public var _sassFunctionName: String {
        String(prefix(while: { $0 != "("}))
    }
}

extension Dictionary where Key == String {
    /// Remap a Sass function signature dictionary to be keyed by Sass function name with
    /// elements the (signature, callback) tuple.  :nodoc:
    public var _asSassFunctionNameElementMap: [String: Self.Element] {
        .init(uniqueKeysWithValues: map { ($0.key._sassFunctionName, $0) })
    }
}

// MARK: Errors

/// Errors thrown for common `SassValue` scenarios.
///
/// Generally you throw these from your `SassFunction`.  Then the compilation
/// fails, giving the description of the error as the failure reason.  Generally you don't
/// need to construct them manually, rather they are thrown for you from various
/// `SassValue` family methods.
public enum SassValueError: Error, CustomStringConvertible {
    /// A Sass value was not the expected type.
    case wrongType(expected: String, actual: SassValue)
    /// A Sass value used as a list index was out of range.
    case badListIndex(max: Int, actual: Int)
    /// A Sass value used as a string index was out of range.
    case badStringIndex(max: Int, actual: Int)
    /// A `SassNumber` used as an integer wasn't.
    case notInteger(SassNumber)
    /// A `SassNumber` was not in the expected range.
    case notInRange(SassNumber, String)
    /// A `SassNumber` couldn't be converted to some requested units.
    case unconvertibleUnit1(from: String, to: String, specifically: String)
    /// A `SassNumber` couldn't be converted to requested units.
    case unconvertibleUnit2(from: String, to: String, leftovers: String)
    /// A `SassNumber` couldn't be formed because of uncancelled units.
    case uncancelledUnits(numerator: String, denominator: String)
    /// A `SassNumber` had units that weren't expected.
    case unexpectedUnits(SassNumber)
    /// A `SassNumber` didn't have a specific single unit.
    case missingUnit(SassNumber, String)

    /// A human-readable description of the error.
    public var description: String {
        switch self {
        case let .wrongType(expected: expected, actual: actual):
            return "Value has wrong type, expected \(expected) but got \(actual)."
        case let .badListIndex(max: max, actual: actual):
            return "List index \(actual) out of range: valid range is 1...\(max)."
        case let .badStringIndex(max: max, actual: actual):
            return "String index \(actual) out of range: valid range is 1...\(max)."
        case let .notInteger(num):
            return "Number \(num) is not an integer."
        case let .notInRange(num, rangeDescription):
            return "Number \(num) is not in range: \(rangeDescription)."
        case let .unconvertibleUnit1(from: from, to: to, specifically: specifically):
            return "Units '\(from)' couldn't be converted to '\(to)', specifically from '\(specifically)'."
        case let .unconvertibleUnit2(from: from, to: to, leftovers: leftovers):
            return "Units '\(from)' couldn't be converted to '\(to)', leftovers '\(leftovers)'."
        case let .uncancelledUnits(numerator: numerator, denominator: denominator):
            return "Units have redundant dimension: numerator '\(numerator)', denominator '\(denominator)'"
        case let .unexpectedUnits(number):
            return "\(number) has units but expected none."
        case let .missingUnit(number, unit):
            return "\(number) did not have single expected unit '\(unit)'."
        }
    }
}
