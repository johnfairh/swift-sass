//
//  Calculation.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

/// A Sass calculation value.
///
/// These correspond to Sass `calc()`, `min()`, `max()`, or `clamp()` expressions.
/// See [the Sass docs](https://sass-lang.com/documentation/values/calculations).
///
/// The Sass compiler simplfiies these before sending them to custom functions: this means that if you
/// do receive a `SassCalculation`  argument then it cannot be further simplified at compile time,
/// for example `calc(20px + 30%)`.
///
/// The API here allows you to construct `SassCalculation`s representing `calc()`-type expressions
/// including invalid ones such as `calc(20px, 30px)` as though you were writing a stylesheet.  The
/// validity is checked -- and the overall expression simplified -- by the compiler when it receives the value.
public final class SassCalculation: SassValue {
    /// The kind of the `SassCalculation` expression
    public enum Kind: String {
        /// Sass [`calc()`](https://sass-lang.com/documentation/values/calculations)
        case calc
        /// Sass [`min()`](https://sass-lang.com/documentation/modules/math#min)
        case min
        /// Sass [`max()`](https://sass-lang.com/documentation/modules/math#max)
        case max
        /// Sass [`clamp()`](https://sass-lang.com/documentation/modules/math#clamp)
        case clamp
    }

    /// Arithmetic operators valid within `SassCalculation.Operation`s`
    public enum Operator: Character {
        /// The regular arithmetic operators with normal precedence.
        case plus = "+", minus = "-", times = "*", dividedBy = "/"

        var isHighPrecedence: Bool {
            self == .times || self == .dividedBy
        }

        var isLowPrecedence: Bool {
            !isHighPrecedence
        }
    }

    /// A subexpression of a `SassCalculation`.
    public indirect enum Value: Hashable, Equatable, CustomStringConvertible {
        /// A number with optional associated units.  See `number(_:unit:)` helper function.
        case number(SassNumber)
        /// A string - expected to be a Sass variable for later evaluation, for example the `$width` part of `calc($width / 2)`.
        case string(String)
        /// A string - expected to be a Sass variable, but this form means the stylesheet wrote `#{$width}` instead of `$width`.
        /// Use `string(_:)` instead when building your own `SassCalculation`s.
        case interpolation(String)
        /// A binary arithmetic expression.
        case operation(Value, Operator, Value)
        /// A sub-calculation.
        case calculation(SassCalculation)

        /// A helper to construct `number(_:)`s.
        public static func number(_ double: Double, unit: String? = nil) -> Value {
            .number(SassNumber(double, unit: unit))
        }

        var isLowPrecedenceOperation: Bool {
            if case let .operation(_, op, _) = self {
                return op.isLowPrecedence
            }
            return false
        }

        /// A human-readable description of the value.
        public var description: String {
            switch self {
            case let .number(n): return n.sassDescription
            case let .string(s): return s.description
            case let .interpolation(s): return "#{\(s)}"
            case let .calculation(c): return c.sassDescription
            case let .operation(left, op, right):
                func valueDescription(_ value: Value) -> String {
                    let parens = op.isHighPrecedence && value.isLowPrecedenceOperation
                    let valueDesc = value.description
                    return parens ? "(\(valueDesc))" : valueDesc
                }
                return "\(valueDescription(left)) \(op.rawValue) \(valueDescription(right))"
            }
        }
    }

    // MARK: Initializers

    /// Create a Sass `calc()` expression.
    public convenience init(calc value: Value) {
        self.init(kind: .calc, arguments: [value])
    }

    /// Create an arbitrary `SassCalculation`.
    public init(kind: Kind, arguments: [Value]) {
        self.kind = kind
        self.arguments = arguments
    }

    // MARK: Properties

    /// The `SassCalculation`'s `Kind`.
    public let kind: Kind

    /// The `SassCalcuation`'s arguments.  The Sass specification says how many
    /// are actually valid for each `Kind` but this API does not check this.
    public let arguments: [Value]

    // MARK: Methods

    // Uh I don't think there are any useful methods to offer here.
    // Any kind of content-munging or inspection is done via normal
    // collection stuff on `arguments`.
    //
    // Could take a stab at simplification but not sure it's useful
    // on the 'host' side.

    // MARK: Misc

    /// Two `SassCalculation`s are equal if they have the same kind and arguments.
    ///
    /// There's no attempt at simplification here -- so `calc(10px)` and `calc(5px + 5px)`
    /// compare as different.
    public static func == (lhs: SassCalculation, rhs: SassCalculation) -> Bool {
        lhs.kind == rhs.kind && lhs.arguments == rhs.arguments
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(calculation: self)
    }

    var sassDescription: String {
        let args = arguments.map(\.description).joined(separator: ", ")
        return "\(kind.rawValue)(\(args))"
    }

    public override var description: String {
        "Calculation(\(sassDescription))"
    }

    /// Hash the calculation.
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(arguments)
    }
}

extension SassValue {
    /// Reinterpret the value as a calculation.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't a string.
    public func asCalculation() throws -> SassCalculation {
        guard let selfCalculation = self as? SassCalculation else {
            throw SassFunctionError.wrongType(expected: "SassCalculation", actual: self)
        }
        return selfCalculation
    }
}
