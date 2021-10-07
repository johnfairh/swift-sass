//
//  Calculation.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

/// A Sass calculation expression value.
///
public final class SassCalculation: SassValue {
    public enum Kind: String {
        case calc
        case min
        case max
        case clamp
    }

    public enum Operator {
        case plus, minus, times, dividedBy
    }

    public struct Operation {
        public let left: Value
        public let `operator`: Operator
        public let right: Value
    }

    public indirect enum Value {
        case number(SassNumber)
        case string(String) // not SassString
        case interpolation(String) // also not SassString
        case operation(Operation)
        case calculation(SassCalculation)
    }

    // MARK: Initializers
    public init(kind: Kind = .calc, arguments: [Value]) {
    }

    // MARK: Properties

    // MARK: Methods

    // MARK: Misc

    /// Two `SassCalculation`s are equal if ...
    public static func == (lhs: SassCalculation, rhs: SassCalculation) -> Bool {
        false
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(calculation: self)
    }

    public override var description: String {
        return "Calculation()"
    }

    /// Hash the calculation
    public override func hash(into hasher: inout Hasher) {
        //
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
