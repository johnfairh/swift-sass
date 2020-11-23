//
//  SassValue.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A SassScript value passed to or returned from a custom function.
///
/// The Sass compiler lets you define custom functions written Swift that are available to
/// stylesheets as they are compiled.  `SassValue` is used to transmit function parameters
/// and return values.  Usually the first job of your custom function is to downcast each parameter
/// to the expected type using methods like `SassValue.asString(...)`.
public class SassValue {
    /// The CSS spelling of the value.
    public var css: String { "" }
}

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
            return "Non-integer value used an index: \(type(of: actual)) \(actual)."
        case let .subscriptIndex(max: max, actual: actual):
            return "Index out of range: \(actual), valid 1-\(max)."
        }
    }
}
