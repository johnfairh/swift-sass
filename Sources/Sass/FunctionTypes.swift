//
//  FunctionTypes.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// The Swift type of a Sass function.
///
/// Use this to define Sass functions written in Swift that are available to stylesheets as they
/// are compiled.
///
/// `SassValue` is used to transmit function parameters and return values: any parameters with
/// default values are instantiated before the function is called.  If your function signature includes an
/// argument list such as `funcName($arg1, $others...)` then the args list is passed as a
/// list value, so in the example the function receives two arguments: one for `$arg1` and one for
/// whatever else is passed.
///
/// Usually the first job of a function is to downcast each parameter to the expected type using
/// throwing methods such as `SassValue.asString()`.
///
/// Any error thrown from the function ends up cancelling the compilation job and returning an
/// error message back to the user that contains the text of the error thrown.
///
/// All Sass functions return a value -- there is no `void` return type.  Create new `SassValue`
/// objects using a subclass initializer such as `SassString.init(_:isQuoted:)`.
public typealias SassFunction = @Sendable ([SassValue]) throws -> SassValue

/// A Sass function signature.
///
/// This is text that can appear after `@function` in a Sass stylesheet, such as
/// `mix($color1, $color2, $weight: 50%)`.
public typealias SassFunctionSignature = String

/// A set of `SassFunction`s and their signatures.
///
/// Do not include two function signatures that have the same function name, such as
/// `myFunc($a)` and `myFunc($b)`: the program will terminate.
public typealias SassFunctionMap = [SassFunctionSignature : SassFunction]

// Utilities for compilers to work with sets of functions

extension SassFunctionSignature {
    /// Get the Sass function name (everything before the paren) from a signature. :nodoc:
    fileprivate var sassFunctionName: String {
        String(prefix(while: { $0 != "("}))
    }
}

extension Dictionary where Key == SassFunctionSignature {
    /// Remap a Sass function signature dictionary to be keyed by Sass function name with
    /// elements the (signature, callback) tuple.  :nodoc:
    private var asSassFunctionNameElementMap: [String: Self.Element] {
        .init(uniqueKeysWithValues: map { ($0.key.sassFunctionName, $0) })
    }

    /// Merge two sets of functions, uniquing on function name, preferring the given set.
    @_spi(SassCompilerProvider)
    public func overridden(with locals: Self) -> [String: Self.Element] {
        asSassFunctionNameElementMap.merging(locals.asSassFunctionNameElementMap) { _, l in l }
    }
}

// MARK: Errors

/// Errors thrown for common `SassFunction` scenarios.
///
/// Generally these are thrown from your `SassFunction`s by `SassValue` family
/// methods in response to error scenarios, for example a user passes a number where
/// you expect a string, or a number in radians where you expected a length.  Then the
/// compilation fails, giving the description of the error as the failure reason.
public enum SassFunctionError: Error, CustomStringConvertible {
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
    /// A color channel value was not in the expected range.
    case channelNotInRange(String, Double, String)

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
            return "\(num) is not an integer."
        case let .notInRange(num, rangeDescription):
            return "\(num) is not in range \(rangeDescription)."
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
        case let .channelNotInRange(channel, number, rangeDescription):
            return "Value \(number) not in range \(rangeDescription) for color channel \(channel)."
        }
    }
}
