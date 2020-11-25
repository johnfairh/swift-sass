//
//  SassConstants.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A SassScript boolean.
///
/// You cannot create instances of this type: use `SassConstants.true` and `SassConstants.false`
/// instead.
public class SassBool: SassValue {
    /// The value of the boolean.
    public let value: Bool

    public override var isTruthy: Bool { value }

    /// Initialize a new bool.  Not public.
    fileprivate init(_ value: Bool) {
        self.value = value
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(bool: self)
    }

    /// A short description of the boolean.
    public override var description: String {
        return "Bool(\(value))"
    }

    /// Boolean equality.
    public static func == (lhs: SassBool, rhs: SassBool) -> Bool {
        lhs.value == rhs.value
    }

    /// Hash the boolean value.
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

extension SassValue {
    /// Reinterpret the value as a boolean.  But see `isTruthy`: you almost always don't
    /// want to be using this.
    /// - throws: `SassTypeError` if it isn't a boolean.
    public func asBool() throws -> SassBool {
        guard let selfBool = self as? SassBool else {
            throw SassValueError.wrongType(expected: "SassBool", actual: self)
        }
        return selfBool
    }
}

/// The SassScript `null` value.
///
/// Use `SassConstants.null` to reference the null constant.
public class SassNull: SassValue {
    public override var isTruthy: Bool { false }
    public override var isNull: Bool { true }

    fileprivate override init() {}

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(null: self)
    }

    /// A short description of the string.
    public override var description: String {
        "Null"
    }

    /// All instances of null are equal.
    public static func == (lhs: SassNull, rhs: SassNull) -> Bool {
        true
    }
}

/// SassScript constants
public enum SassConstants {
    /// Sass `null`
    public static let null: SassValue = SassNull()
    /// Sass `true`
    public static let `true`: SassValue = SassBool(true)
    /// Sass `false`
    public static let `false`: SassValue = SassBool(false)
}
