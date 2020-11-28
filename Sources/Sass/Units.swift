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
        toCanonical[canonical] = .init(1, 1)
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
        "mm" : .init(96, 254),
        "q"  : .init(96, 254 * 4),
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
        "x"    : .init(1, 1) // why this gets an alias! and what an alias!
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
struct Unit {
    /// A unit's name.
    typealias Name = String

    /// This unit's name, lower-cased.
    let name: Name
    /// Any dimension that this unit is known to be part of
    let dimension: Dimension?

    init(name: String) {
        self.name = name.lowercased()
        self.dimension = Dimension.knownUnits[self.name]
    }
}
