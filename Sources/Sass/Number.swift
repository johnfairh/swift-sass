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
/// Integer / equality rounding has special rules that unfortunately don't seem to be sound.  Will gently pursue
/// this upstream.  For now we implement our own thing inspired by theirs, basically rounding to 11 decimal
/// places.
///
/// Infinities and NaNs are left vague but they probably don't crop up very often in the domain --
/// will do divide-by-zero test and see what happens.
///
/// The `SassDouble` type wraps up these concerns.  It's private.
struct SassDouble: Hashable, Comparable {
    static let tolerance = Double(1e-11)

    /// From the sass protocol spec: "A hash code with the same equality semantics can be generated
    /// for a number x by [schoolbook] rounding x * 1e11 to the nearest integer and taking the hash
    /// code of the result."  This is definitely _not_ the "same equality semantics", it's rounding to
    /// 11 decimal places.
    static let hashInverseTolerance = Double(1e11)

    static func hashEquivalent(_ double: Double) -> Int {
        Int((double * hashInverseTolerance).rounded())
    }

    /// Sass protocol spec: Two numbers are equal if their numerical value are within 1e-11 of one another.
    /// This is an unsound definition of equality, inconsistent with the same spec's hashing idea (above),
    /// and is keeping me awake at night.  So we don't use it.
//    static func sass_areEqual(_ lhs: Double, _ rhs: Double) -> Bool {
//        let r = (lhs - rhs).magnitude < tolerance
//        return r
//    }

    /// Instead use the hash approach - schoolbook round to 11 decimal places.  This is sound (equivalence
    /// relation) and doesn't break Swift hashing (values equal guarantee their hashvalues are equal).
    ///
    /// It's inconsistent with Dart Sass.  Oh well.
    static func areEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        hashEquivalent(lhs) == hashEquivalent(rhs)
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

    var hashEquivalent: Int {
        SassDouble.hashEquivalent(double)
    }

    /// A hash value compatible with the definitely of equality.
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
/// Sass numbers are `Double`s with units.
///
/// Sass has its own rules for numeric equality and integer conversion that use only the first
/// 11 decimal places.  Use the `SassNumber` methods to convert to integers and test for ranges.
///
/// The units on a `SassNumber` can describe the result of multiplying and dividing numbers with
/// primitive units.  Best described in the
/// [Sass docs](https://sass-lang.com/documentation/values/numbers#units).
/// The [CSS values spec](https://www.w3.org/TR/css-values-4/#intro) defines several common
/// units and how to convert between them, for example _px_ to _pt_.  `asConvertedTo(...)`
/// implements these conversions which lets you, for example, write a function that accepts any length unit
/// that you can easily convert to your preferred unit.
///
/// Because of units, `SassNumber` is not `Comparable` --- there is no ordering relation
/// possible between "5 cm" and "12 kHz".  It is `Equatable` though respecting unit conversion
/// so that "1 cm" == "10 mm".
public final class SassNumber: SassValue {
    private let sassDouble: SassDouble
    private let units: UnitQuotient

    // MARK: Initializers

    /// Initialize a new number from a value and optionally a unit.
    public init(_ double: Double, unit: String? = nil) {
        sassDouble = SassDouble(double)
        units = try! UnitQuotient(numerator: unit.flatMap { [$0] } ?? [], denominator: [])
    }

    /// Initialize a new number from a value and a list of numerator and denominator units.
    ///
    /// For example an acceleration:
    /// ```swift
    /// let g = SassNumber(981, numeratorUnits: ["cm"], denominatorUnits: ["s", "s"])
    /// ```
    ///
    /// - parameter double: The value of the number.
    /// - parameter numeratorUnits: The names of units applied to the number.
    /// - parameter denominatorUnits: The names of units whose reciprocals are applied to the number.
    /// - throws: `SassFunctionError.uncancelledUnits(...)` if units for the same dimension are listed in
    ///   both `numeratorUnits` and `denominatorUnits`.
    public init(_ double: Double, numeratorUnits: [String] = [], denominatorUnits: [String] = []) throws {
        sassDouble = SassDouble(double)
        units = try UnitQuotient(numerator: numeratorUnits, denominator: denominatorUnits)
    }

    private init(_ double: Double, units: UnitQuotient) {
        self.sassDouble = SassDouble(double)
        self.units = units
    }

    // MARK: Properties

    /// The underlying sign and magnitude of the number.
    ///
    /// Fairly meaningless without understanding the number's units.
    ///
    /// - warning: Take care using this value directly because Sass and Swift use different
    ///   tolerances for comparison and integer conversion.
    ///
    ///   * Use `asInt()` to check a  `SassNumber` is an integer  instead of `Int.init(exactly:)`.
    ///     (It could be that `Int(exactly: n.double)` would fail.)
    ///   * Use `asIn(range:)` to check a floating point `SassNumber` is within a range and convert
    ///     it to a Swift `Double` within the range. (It could be that `range.contains(n.double)`
    ///     would fail.)
    ///   * If you must compare floating-point `SassNumber`s then consistently compare the `SassNumber`s
    ///     themselves, not the `double`s within.  Similarly, use the `SassNumber` itself as a dictionary key.
    public var double: Double {
        sassDouble.double
    }

    // MARK: Comparison

    /// The integer value of this number.
    ///
    /// This has the same role as `Int.init(exactly:)` but maps more floating point values to
    /// the same integer according to the Sass specification.
    /// - returns: The integer that this `SassNumber` exactly represents.
    /// - throws: `SassFunctionError.notInteger(...)` if the number is not an integer
    ///   according to Sass's rounding rules.
    public func asInt() throws -> Int {
        guard let intVal = Int(sassDouble) else {
            throw SassFunctionError.notInteger(self)
        }
        return intVal
    }

    /// The value of this number within a closed range.
    ///
    /// If you have an integer range than do `asInt()` first and work on that.
    ///
    /// - returns: The `Double` value corresponding to this `SassValue` in `range`.
    /// - throws: `SassFunctionError.notInRange(...)` if the number is not in
    ///   the range, using Sass's rounding rules at the ends of the range.
    public func asIn(range: ClosedRange<Double>) throws -> Double {
        guard let clamped = sassDouble.clampTo(range: range) else {
            throw SassFunctionError.notInRange(self, range.description)
        }
        return clamped
    }

    /// The value of this number within a half-open range.
    ///
    /// If you have an integer range than do `asInt()` first and work on that.
    ///
    /// - returns: The `Double` value corresponding to this `SassValue` in `range`.
    /// - throws: `SassFunctionError.notInRange(...)` if the number is not in
    ///   the range, using Sass's rounding rules at the ends of the range.
    public func asIn(range: Range<Double>) throws -> Double {
        guard let clamped = sassDouble.clampTo(range: range) else {
            throw SassFunctionError.notInRange(self, range.description)
        }
        return clamped
    }

    // MARK: Units

    /// Is the number free of units?
    public var hasNoUnits: Bool {
        !units.hasUnits
    }

    /// Throw an error if the number has any units.
    public func checkNoUnits() throws {
        guard hasNoUnits else {
            throw SassFunctionError.unexpectedUnits(self)
        }
    }

    /// Does the number have exactly this unit?
    public func hasUnit(name: String) -> Bool {
        try! units == UnitQuotient(numerator: [name], denominator: [])
    }

    /// Throw an error unless the number has exactly the single unit.
    public func checkHasUnit(name: String) throws {
        guard hasUnit(name: name) else {
            throw SassFunctionError.missingUnit(self, name)
        }
    }

    /// The names of the 'numerator' units.
    public var numeratorUnits: [String] {
        units.numerator.units.names
    }

    /// The names of the 'denominator' units.
    public var denominatorUnits: [String] {
        units.denominator.units.names
    }

    /// The equivalent `SassNumber` converted to the requested units.
    ///
    /// Only units described in the [CSS spec](https://www.w3.org/TR/css-values-4/#intro) as 'convertible'
    /// can be converted.
    ///
    /// A number without any units can be 'converted' to any set of units.
    ///
    /// - throws: `SassFunctionError` If the requested units are invalid, or if the number's units
    /// are not convertible to the requested units.
    public func asConvertedTo(numeratorUnits: [String] = [], denominatorUnits: [String] = []) throws -> SassNumber {
        let newUnits = try UnitQuotient(numerator: numeratorUnits, denominator: denominatorUnits)
        if !units.hasUnits || !newUnits.hasUnits || units == newUnits {
            return SassNumber(double, units: newUnits)
        }
        return try asConvertedTo(units: newUnits)
    }

    private func asConvertedTo(units newUnits: UnitQuotient) throws -> SassNumber {
        let ratio = try units.ratio(to: newUnits)
        return SassNumber(ratio.apply(double), units: newUnits)
    }

    // MARK: Misc

    /// Two `SassNumber`s are equal iff:
    /// 1. Neither have units and their values are the same to 11 decimal places; or
    /// 2. They have convertible units and, when both converted to the same units, have values
    ///   that are equal to 11dp.
    public static func == (lhs: SassNumber, rhs: SassNumber) -> Bool {
        if lhs.hasNoUnits != rhs.hasNoUnits {
            return false
        }
        if lhs.hasNoUnits || lhs.units == rhs.units {
            return lhs.sassDouble == rhs.sassDouble
        }
        do {
            let lhsScaled = try lhs.asConvertedTo(units: rhs.units)
            return lhsScaled.sassDouble == rhs.sassDouble
        } catch {
            // units not compatible
            return false
        }
    }

    /// Hash the value.
    public override func hash(into hasher: inout Hasher) {
        if hasNoUnits {
            sassDouble.hash(into: &hasher)
            return
        }
        let canon = units.canonicalUnitsAndRatio
        let canonValue = canon.1.apply(double)
        hasher.combine(SassDouble.hashEquivalent(canonValue))
        hasher.combine(canon.0)
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(number: self)
    }

    public override var description: String {
        let unitStr = hasNoUnits ? "" : " \(units)"
        return "Number(\(sassDouble.double)\(unitStr))"
    }
}

extension SassValue {
    /// Reinterpret the value as a number.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't a number.
    public func asNumber() throws -> SassNumber {
        guard let selfString = self as? SassNumber else {
            throw SassFunctionError.wrongType(expected: "SassNumber", actual: self)
        }
        return selfString
    }
}
