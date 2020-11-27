//
//  Number.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Sass numbers.  A surprising amount of stuff here due to units and
// floating point accommodation.

// MARK: SassDouble

/// The numeric part of a Sass number is expressed as a 64-bit floating point value.
/// Integer / equality rounding is defined to be done with a tolerance of 1e-11.  This isn't exactly representable
/// which makes me unnecessarily anxious.  This only makes a difference to iee754 up to around 8000, which
/// is the area CSS is interested in really!
///
/// Infinities and NaNs are left vague but they probably don't crop up very often in the domain --
/// will do divide-by-zero test and see what happens.
///
/// The `SassDouble` type wraps up these concerns.  It's private.
struct SassDouble: Hashable, Comparable {
    static let tolerance = Double(1e-11)

    static func areEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        let r = (lhs - rhs).magnitude < tolerance
        return r
    }

    static func isStrictlyLessThan(_ lhs: Double, _ rhs: Double) -> Bool {
        guard !areEqual(lhs, rhs) else {
            return false
        }
        return lhs < rhs
    }

    /// The value
    let double: Double

    /// Wrap a new value
    init(_ double: Double) {
        self.double = double
    }

    // MARK: Range

    /// Helper for ranges - protocol not quite got what I want in it!
    private func clampLowerRange<R>(lowerBound: Double, range: R) -> Double? where R: RangeExpression, R.Bound == Double {
        if SassDouble.areEqual(double, lowerBound) {
            return lowerBound
        }
        if range.contains(double) {
            return double
        }
        return nil

    }

    /// Clamp for half-open ranges, sass-equal to UB means not in.
    func clampTo(range: Range<Double>) -> Double? {
        if SassDouble.areEqual(double, range.upperBound) {
            return nil
        }
        return clampLowerRange(lowerBound: range.lowerBound, range: range)
    }

    /// Clamp for closed ranges, sass-equal to UB means =UB.
    func clampTo(range: ClosedRange<Double>) -> Double? {
        if SassDouble.areEqual(double, range.upperBound) {
            return range.upperBound
        }
        return clampLowerRange(lowerBound: range.lowerBound, range: range)
    }

    // MARK: Hashable Comparable

    static let hashInverseTolerance = Double(1e11)

    var hashEquivalent: Int {
        Int((double * SassDouble.hashInverseTolerance).rounded())
    }

    /// A hash value compatible with the definitely of equality.
    ///
    /// From the sass protocol spec: "A hash code with the same equality semantics can be generated
    /// for a number x by [schoolbook] rounding x * 1e11 to the nearest integer and taking the hash
    /// code of the result."  This isn't true but implement it anyway...
    func hash(into hasher: inout Hasher) {
        hasher.combine(hashEquivalent)
    }

    /// Are two `SassDouble`s equivalent.
    static func == (lhs: SassDouble, rhs: SassDouble) -> Bool {
        areEqual(lhs.double, rhs.double)
    }

    /// Are two `SassDouble`s ordered.
    static func < (lhs: SassDouble, rhs: SassDouble) -> Bool {
        isStrictlyLessThan(lhs.double, rhs.double)
    }
}

// MARK: SassDouble -> Int exactly

extension Int {
    /// Get an `Int` from a `SassDouble` if its value is close enough to integral.
    init?(_ sassDouble: SassDouble) {
        let nearestInt = sassDouble.double.rounded()
        guard SassDouble.areEqual(nearestInt, sassDouble.double) else {
            return nil
        }
        self.init(nearestInt)
    }
}

// MARK: Units

// MARK: SassNumber

/// A Sass numeric value.
///
/// Numbers are fundamentally `Double`s but with special rules about comparison and converting to
/// integers.  Numbers also have units omg.
///
public final class SassNumber: SassValue, Comparable {
    private let sassDouble: SassDouble

    /// The underlying value of the number.
    /// XXX warning
    /// Sass and Swift use different tolerances on float -> int conversion.  Use `asInt()` to
    /// get the Sass-approved integer value for a `SassNumber` instead of `Int(exactly:)`.
    public var double: Double {
        sassDouble.double
    }

    /// Initialize a new number from a floating point value.
    public init(_ double: Double) {
        self.sassDouble = SassDouble(double)
    }

    /// Initialize a new number from an integer value.
    public convenience init(_ int: Int) {
        self.init(Double(int))
    }

    /// The integer value of this number.
    ///
    /// This has the same role as `Int(exactly:)` but maps more floating point values to
    /// the same integer according to the Sass specification.
    /// - returns: The integer that this `SassNumber` exactly represents.
    /// - throws: `SassValueError.notInteger()` if the number is not an integer
    ///   according to Sass's rounding rules.
    public func asInt() throws -> Int {
        guard let intVal = Int(sassDouble) else {
            throw SassValueError.notInteger(self)
        }
        return intVal
    }

    /// The value of this number within a closed range.
    ///
    /// - returns: The `Double` value corresponding to this `SassValue` in `range`.
    /// - throws: `SassValueError.notInRange(...)` if the number is not in
    ///   the range, using Sass's rounding rules at the ends of the range.
    public func asIn(range: ClosedRange<Double>) throws -> Double {
        guard let clamped = sassDouble.clampTo(range: range) else {
            throw SassValueError.notInRange(self, range.description)
        }
        return clamped
    }

    /// The value of this number within a half-open range.
    ///
    /// - returns: The `Double` value corresponding to this `SassValue` in `range`.
    /// - throws: `SassValueError.notInRange(...)` if the number is not in
    ///   the range, using Sass's rounding rules at the ends of the range.
    public func asIn(range: Range<Double>) throws -> Double {
        guard let clamped = sassDouble.clampTo(range: range) else {
            throw SassValueError.notInRange(self, range.description)
        }
        return clamped
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(number: self)
    }

    public override var description: String {
        return "Number(\(sassDouble.double))"
    }

    // Comparable

    /// Two `SassNumber`s are equal if ...
    public static func == (lhs: SassNumber, rhs: SassNumber) -> Bool {
        lhs.sassDouble == rhs.sassDouble
    }

    /// Compare two `SassNumber`s using Sass's comparison rules.
    public static func < (lhs: SassNumber, rhs: SassNumber) -> Bool {
        lhs.sassDouble < rhs.sassDouble
    }

    /// Hash the value.
    public override func hash(into hasher: inout Hasher) {
        sassDouble.hash(into: &hasher)
    }
}

extension SassValue {
    /// Reinterpret the value as a string.
    /// - throws: `SassTypeError` if it isn't a string.
    public func asNumber() throws -> SassNumber {
        guard let selfString = self as? SassNumber else {
            throw SassValueError.wrongType(expected: "SassNumber", actual: self)
        }
        return selfString
    }
}
