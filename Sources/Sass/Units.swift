//
//  Units.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Unit support for SassNumber

// From CSS Values and Units Module Level 4 Nov 2020

/// A ratio - stored as num/denom to avoid FP loss of sig during conversions
struct Ratio {
    let num: Double
    let denom: Double

    init(_ n: Double, _ d: Double) {
        self.num = n
        self.denom = d
    }

    init(inverse: Ratio) {
        self.num = inverse.denom
        self.denom = inverse.num
    }

    static let identity = Ratio(1, 1)

    /// Create a ratio from the product of a bunch of others
    init(_ ratios: [Ratio]) {
        self = ratios.reduce(.identity) { result, next in
            result.multiplied(by: next)
        }
    }

    /// New ratio by multiplying by another.
    func multiplied(by other: Ratio) -> Ratio {
        Ratio(num * other.num, denom * other.denom)
    }

    /// New ratio by dividing by another.
    func divided(by other: Ratio) -> Ratio {
        Ratio(num * other.denom, denom * other.num)
    }

    /// Finally apply the ratio to a value
    func apply(_ double: Double) -> Double {
        (num * double) / denom
    }
}

/// A dimension supporting multiple compatible units.
final class Dimension: Sendable {
    let canonical: Unit.Name
    /// Compatible units and their conversion ratio to the the canonical unit
    let conversions: [Unit.Name : Ratio]

    init(canonical: Unit.Name, compatible: [Unit.Name : Ratio] = [:]) {
        var toCanonical = compatible
        toCanonical[canonical] = .identity
        self.canonical = canonical
        self.conversions = toCanonical
    }

    /// Ratio to convert from some unit to the canonical unit.
    func ratioToCanonical(from name: Unit.Name) -> Ratio {
        guard let conversion = conversions[name] else {
            preconditionFailure("Bad unit-dimension association for \(name).")
        }
        return conversion
    }

    /// Ratio to convert to some unit from the canonical unit.
    func ratioFromCanonical(to name: Unit.Name) -> Ratio {
        .init(inverse: ratioToCanonical(from: name))
    }

    /// Ratio to convert between two units
    func ratio(from fromName: Unit.Name, to toName: Unit.Name) -> Ratio {
        .init([ratioToCanonical(from: fromName),
               ratioFromCanonical(to: toName)])
    }
}

/// The dimensions with convertible units from the CSS spec
private let dimensions: [Dimension] = [
    /// Absolute length
    Dimension(canonical: "px", compatible: [
        "cm" : .init(96, 2.54),
        "mm" : .init(96, 25.4),
        "q"  : .init(96, 25.4 * 4),
        "in" : .init(96, 1),
        "pc" : .init(96, 6),
        "pt" : .init(96, 72)
    ]),

    /// Angle
    Dimension(canonical: "deg", compatible: [
        "grad" : .init(360, 400),
        "rad"  : .init(360, 2 * Double.pi),
        "turn" : .init(360, 1)
    ]),

    /// Time
    Dimension(canonical: "s", compatible: [
        "ms" : .init(1, 1000)
    ]),

    /// Frequency
    Dimension(canonical: "hz", compatible: [
        "khz" : .init(1000, 1)
    ]),

    /// Resolution
    Dimension(canonical: "dppx", compatible: [
        "dpi"  : .init(1, 96),
        "dpcm" : .init(2.54, 96),
        "x"    : .identity
    ])
]

extension Dimension {
    /// Global unit lookup
    static let knownUnits: [Unit.Name : Dimension] = {
        var units = [Unit.Name : Dimension]()
        dimensions.forEach { dim in
            dim.conversions.keys.forEach { units[$0] = dim }
        }
        return units
    }()
}

/// A unit - some we know, others are opaque.
struct Unit: Hashable {
    /// A unit's name.
    typealias Name = String

    /// This unit's name, lower-cased.
    let name: Name
    /// Any dimension that this unit is known to be part of
    let dimension: Dimension?

    init(name: Name) {
        self.name = name.lowercased()
        self.dimension = Dimension.knownUnits[self.name]
    }

    init(canonicalFor dimension: Dimension) {
        self.name = dimension.canonical
        self.dimension = dimension
    }

    static func == (lhs: Unit, rhs: Unit) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    var canonicalUnitName: Name {
        dimension?.canonical ?? name
    }

    var canonicalUnitAndRatio: (Unit, Ratio) {
        guard let dimension = dimension else {
            return (self, .identity)
        }
        return (Unit(canonicalFor: dimension),
                dimension.ratioToCanonical(from: name))
    }

    func isConvertibleTo(_ other: Unit) -> Bool {
        if self == other {
            return true
        }
        if let myDimension = dimension,
           let otherDimension = other.dimension,
           myDimension.canonical == otherDimension.canonical {
            return true
        }
        return false
    }

    func ratio(to other: Unit) -> Ratio {
        precondition(isConvertibleTo(other))
        guard let dimension = dimension else {
            return .identity
        }
        return dimension.ratio(from: name, to: other.name)
    }
}

extension Array where Element == Unit {
    var names: [String] {
        map { $0.name }
    }

    var descriptionText: String {
        names.joined(separator: " * ")
    }
}

/// A compound unit formed by multiplying units.  Legitimate to have repeated units,
/// or multiple units sharing the same dimension, eg. cm * cm for area.
struct UnitProduct: CustomStringConvertible, Hashable {
    /// The factors in the compound unit, sorted by unit name.  The sort defines
    /// the canonical form for a given multiset of units.
    let units: [Unit]

    /// Human-readable description of the unit product.
    var description: String {
        units.descriptionText
    }

    /// Initialize a product from a list of unit names.
    init(names: [Unit.Name]) {
        self.units = names.sorted().map { .init(name: $0) }
    }

    /// Initialize a product from a list of units.
    init(_ units: [Unit]) {
        self.units = units.sorted(by: { $0.name < $1.name })
    }

    /// The product with convertible units in their canonical form, along with the
    /// `Ratio` required to convert a value to that form.  Guaranteed to exist.
    var canonicalUnitsAndRatio: (UnitProduct, Ratio) {
        let (newUnits, ratios) = units.reduce(([Unit](), [Ratio]())) { results, unit in
            let (u, r) = unit.canonicalUnitAndRatio
            return (results.0 + [u], results.1 + [r])
        }
        return (UnitProduct(newUnits), Ratio(ratios))
    }

    /// The ratio required to convert a value of our unit-product to the given other product.
    /// Exists only if the two unit-products are compatible.
    ///
    /// For example: ["frogs"] and ["frogs"]
    ///           ["cm"] and ["mm"]
    ///           ["cm * frogs"] and ["frogs * pt"]
    ///
    /// But not: ["frogs"] and ["fish"]
    ///       ["cm"] and ["cm * deg"]
    func ratio(to other: UnitProduct) throws -> Ratio {
        guard self != other else {
            // Optimize conversion to ourselves
            return .identity
        }
        var ratios = [Ratio]()
        var otherUnits = other.units
        // for every unit in our product, identify a unit in the other guy
        // that is convertible to ours.
        // Don't use the other guy's units more than once!  If any are left
        // over or we can't find a match then no converto.
        try units.forEach { unit in
            guard let index = otherUnits.firstIndex(where: { $0.isConvertibleTo(unit) }) else {
                throw SassFunctionError.unconvertibleUnit1(from: self.description,
                                                           to: other.description,
                                                           specifically: unit.name)
            }
            let otherUnit = otherUnits.remove(at: index)
            ratios.append(unit.ratio(to: otherUnit))
        }
        guard otherUnits.isEmpty else {
            throw SassFunctionError.unconvertibleUnit2(from: self.description,
                                                       to: other.description,
                                                       leftovers: otherUnits.descriptionText)
        }
        return Ratio(ratios)
    }
}

/// A compound unit formed by dividing two sets of units.
/// Not permitted to have units with the same dimension in num & denom.
struct UnitQuotient: CustomStringConvertible, Hashable {
    let numerator: UnitProduct
    let denominator: UnitProduct

    /// Form a new unit quotient from unit names.
    /// Throws an error if the two lists share a dimension.
    init(numerator: [Unit.Name], denominator: [Unit.Name]) throws {
        self.numerator = UnitProduct(names: numerator)
        self.denominator = UnitProduct(names: denominator)

        // Check for user not doing their cancelling...
        let numCanon = Set(self.numerator.units.map { $0.canonicalUnitName })
        let denomCanon = Set(self.denominator.units.map { $0.canonicalUnitName })
        guard numCanon.intersection(denomCanon).isEmpty else {
            throw SassFunctionError.uncancelledUnits(numerator: self.numerator.description,
                                                    denominator: self.denominator.description)
        }
    }

    /// Form a quotient from a single unit
    init(unit: Unit.Name) {
        try! self.init(numerator: [unit], denominator: [])
    }

    /// Form a unitless quotient
    init() {
        try! self.init(numerator: [], denominator: [])
    }

    private init(numerator: UnitProduct, denominator: UnitProduct) {
        self.numerator = numerator
        self.denominator = denominator
    }

    /// Are there actually any units in this unit quotient?
    var hasUnits: Bool {
        !numerator.units.isEmpty || !denominator.units.isEmpty
    }

    /// Human-readable description of the unit quotient.
    var description: String {
        if numerator.units.isEmpty {
            if denominator.units.isEmpty {
                return ""
            }
            return "(\(denominator))^-1"
        }
        if denominator.units.isEmpty {
            return numerator.description
        }
        return "\(numerator) / \(denominator)"
    }

    /// The quotient with convertible units in their canonical form, along with the
    /// `Ratio` required to convert a value to that form.  Guaranteed to exist.
    var canonicalUnitsAndRatio: (UnitQuotient, Ratio) {
        let numUnitsAndRatio = numerator.canonicalUnitsAndRatio
        let denomUnitsAndRatio = denominator.canonicalUnitsAndRatio

        return (UnitQuotient(numerator: numUnitsAndRatio.0, denominator: denomUnitsAndRatio.0),
                numUnitsAndRatio.1.divided(by: denomUnitsAndRatio.1))
    }

    /// The ratio required to convert a value of our unit-quotient to the given other quotient.
    /// Exists only if the two unit-quotients are compatible.
    func ratio(to other: UnitQuotient) throws -> Ratio {
        let numRatio = try numerator.ratio(to: other.numerator)
        let denomRatio = try denominator.ratio(to: other.denominator)
        return numRatio.divided(by: denomRatio)
    }
}
