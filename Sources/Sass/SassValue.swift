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
public protocol SassValue {
    /// Call the corresponding method of `visitor` against this object.
    func accept<V, R>(visitor: V) throws -> R where V: SassValueVisitor, R == V.ReturnType
}

// MARK: Visitor

/// A protocol for implementing polymorphic operations over `SassValue` objects.
public protocol SassValueVisitor {
    /// The return type of the operation.
    associatedtype ReturnType
    /// The operation for `SassString`s.
    func visit(string: SassString) throws -> ReturnType
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
