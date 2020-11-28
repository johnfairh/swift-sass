//
//  Units.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
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

    init(_ ratios: [Ratio]) {
        let product = ratios.reduce((1,1)) { result, next in
            (result.0 * next.num, result.1 * next.denom)
        }
        self.num = product.0
        self.denom = product.1
    }

    func multiply(_ double: Double) -> Double {
        (num * double) / denom
    }

    func divide(_ double: Double) -> Double {
        (denom * double) / num
    }
}

/// A dimension supporting multiple compatible units.
final class Dimension {
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
struct Unit: Equatable {
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
    var descriptionText: String {
        map { $0.name }.joined(separator: " * ")
    }
}

/// A compound unit formed by multiplying units.  Legitimate to have repeated units,
/// or multiple units sharing the same dimension, eg. cm * cm for area.
struct UnitProduct: CustomStringConvertible, Equatable {
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
                throw SassValueError.unconvertibleUnit1(from: self.description,
                                                        to: other.description,
                                                        specifically: unit.name)
            }
            let otherUnit = otherUnits.remove(at: index)
            ratios.append(unit.ratio(to: otherUnit))
        }
        guard otherUnits.isEmpty else {
            throw SassValueError.unconvertibleUnit2(from: self.description,
                                                    to: other.description,
                                                    leftovers: otherUnits.descriptionText)
        }
        return Ratio(ratios)
    }
}
