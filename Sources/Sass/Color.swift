//
//  Color.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

//
// Version 2 of this for the CSS Color 4 rework.
// Might look to do ergonomic support for mixing & conversion by porting the dart-sass
// code, but for now just provide a skeleton.
//
// 1. Wide variety of colour spaces, some of which non-isomorphic
// 2. Channels can be _missing_ including alpha
//

// MARK: Channel value policing

private func checkRgb(_ val: Int, channel: String) throws -> Int {
    if !(0...255).contains(val) {
        throw SassFunctionError.channelNotInRange(channel, Double(val), "0...255")
    }
    return val
}

private func check(_ val: Double, range: ClosedRange<Double>, channel: String) throws -> Double {
    guard let clamped = SassDouble(val).clampTo(range: range) else {
        throw SassFunctionError.channelNotInRange(channel, val, range.description)
    }
    return clamped
}

private func checkAlpha(_ val: Double) throws -> Double {
    try check(val, range: 0...1, channel: "alpha")
}

private func checkHue(_ val: Double) throws -> Double {
    try check(val, range: 0...360, channel: "hue")
}

private func checkPercentage(_ val: Double, channel: String) throws -> Double {
    try check(val, range: 0...100, channel: channel)
}

// MARK: SassColor

/// A Sass color value.
///
/// Supports the bare features of CSS Color Module Level 4 by supporting a wide range of color spaces,
/// but does not offer anything particularly profound for working with such values such as converting between
/// them or mixing colours or policing channel values outside of the legacy spaces.
///
/// - note: Parameter values follow web standards rather the Apple SDK standards,
///   so for example 'red' is modelled as an integer in 0...255.
public final class SassColor: SassValue, @unchecked Sendable {
    // MARK: Spaces

    /// Known color spaces
    public enum Space: String, Sendable {
        /// Legacy RGB space
        case rgb
        /// Legacy HSL space
        case hsl
        /// Legacy HWB space
        case hwb
        /// The [sRGB color space](https://www.w3.org/TR/css-color-4/#predefined-sRGB)
        case srgb
        /// The [linear-light sRGB color space](https://www.w3.org/TR/css-color-4/#predefined-sRGB-linear)
        case srgbLinear = "srgb-linear"
        /// The [display-p3 color space](https://www.w3.org/TR/css-color-4/#predefined-display-p3)
        case displayP3 = "display-p3"
        /// The [a98-rgb color space](https://www.w3.org/TR/css-color-4/#predefined-a98-rgb)
        case a98Rgb = "a98-rgb"
        /// The [prophoto-rgb color space](https://www.w3.org/TR/css-color-4/#predefined-prophoto-rgb)
        case prophotoRgb = "prophoto-rgb"
        /// The [rec2020 color space](https://www.w3.org/TR/css-color-4/#predefined-rec2020)
        case rec2020
        /// The [xyz-d65 color space](https://www.w3.org/TR/css-color-4/#predefined-xyz)
        case xyzD65 = "xyz-d65"
        /// The [xyz-d50 color space](https://www.w3.org/TR/css-color-4/#predefined-xyz)
        case xyzD50 = "xyz-d50"
        /// The [CIE Lab color space](https://www.w3.org/TR/css-color-4/#cie-lab)
        case lab
        /// The [CIE LCH color space](https://www.w3.org/TR/css-color-4/#cie-lab)
        case lch
        /// The [Oklab color space](https://www.w3.org/TR/css-color-4/#ok-lab)
        case oklab
        /// The [Oklch color space](https://www.w3.org/TR/css-color-4/#ok-lab)
        case oklch
    }
    /// The color space this color is defined in
    public let space: Space

    // MARK: Initializers

    /// Create a `SassColor` from base parameters.
    ///
    /// This is unchecked for channel ranges.
    public init(space: Space, _ channel1: Double?, _ channel2: Double?, _ channel3: Double?, alpha: Double?) {
        self.space = space
        self.channel1 = channel1
        self.channel2 = channel2
        self.channel3 = channel3
        self.alpha = alpha
    }

    /// Create a `SassColor` from RGB and alpha components.
    /// - parameter red: Red channel, must be between 0 and 255.
    /// - parameter green: Green channel, must be between 0 and 255.
    /// - parameter blue: Blue channel, must be between 0 and 255.
    /// - parameter alpha: Alpha channel, between 0.0 and 1.0.
    /// - throws: `SassFunctionError.channelNotInRange(...)` if any parameter is out of range.
    public convenience init(red: Int, green: Int, blue: Int, alpha: Double = 1.0) throws {
        self.init(space: .rgb,
                  try Double(checkRgb(red, channel: "red")),
                  try Double(checkRgb(green, channel: "green")),
                  try Double(checkRgb(blue, channel: "blue")),
                  alpha: try checkAlpha(alpha))
    }

    /// Create a `SassColor` from HSL and alpha components.
    /// - parameter hue: Hue, from 0 to 360.
    /// - parameter saturation: Saturation, from 0 to 100.
    /// - parameter lightness: Lightness, from 0 to 100.
    /// - parameter alpha: Alpha channel, between 0.0 and 1.0.
    /// - throws: `SassFunctionError.channelNotInRange(...)` if any parameter is out of range.
    public convenience init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1.0) throws {
        self.init(space: .hsl,
                  try Double(checkHue(hue)),
                  try Double(checkPercentage(saturation, channel: "saturation")),
                  try Double(checkPercentage(lightness, channel: "lightness")),
                  alpha: try checkAlpha(alpha))
    }

    /// Create a `SassColor` from HWB and alpha components.
    /// - parameter hue: Hue, from 0 to 360.
    /// - parameter whiteness: Whiteness, from 0 to 100.
    /// - parameter blackness: Blackness,  from 0 to 100.
    /// - parameter alpha: Alpha channel, between 0.0 and 1.0.
    /// - throws: `SassFunctionError.channelNotInRange(...)` if any parameter is out of range.
    public convenience init(hue: Double, whiteness: Double, blackness: Double, alpha: Double = 1.0) throws {
        self.init(space: .hwb,
                  try Double(checkHue(hue)),
                  try Double(checkPercentage(whiteness, channel: "whiteness")),
                  try Double(checkPercentage(blackness, channel: "blackness")),
                  alpha: try checkAlpha(alpha))
    }

    // MARK: Properties

    /// The first channel's value, or `nil` if missing
    public let channel1: Double?
    /// The second channel's value, or `nil` if missing
    public let channel2: Double?
    /// The third channel's value, or `nil` if missing
    public let channel3: Double?
    /// The alpha channel's value, or `nil` if missing
    public let alpha: Double?

    // MARK: Misc

    /// Colors in different spaces are incomparable; otherwise compared fieldwise using only 10DP  for channels.
    public static func == (lhs: SassColor, rhs: SassColor) -> Bool {
        // XXX legacy spaces should be convertible
        lhs.space == rhs.space &&
            SassDouble.areEqualWithNil(lhs.channel1, rhs.channel1) &&
            SassDouble.areEqualWithNil(lhs.channel2, rhs.channel2) &&
            SassDouble.areEqualWithNil(lhs.channel3, rhs.channel3) &&
            SassDouble.areEqualWithNil(lhs.alpha, rhs.alpha)
    }

    /// Hash the color.
    public override func hash(into hasher: inout Hasher) {
        // XXX legacy spaces have special rules (convert to rgb)
        hasher.combine(space)
        hasher.combine(SassDouble.hashEquivalent(channel1 ?? 0))
        hasher.combine(SassDouble.hashEquivalent(channel2 ?? 0))
        hasher.combine(SassDouble.hashEquivalent(channel3 ?? 0))
        hasher.combine(SassDouble.hashEquivalent(alpha ?? 0))
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(color: self)
    }

    public override var description: String {
        func n(_ s: Double?) -> String { s.map(\.description) ?? "missing" }
        return "Color(\(space) [\(n(channel1)), \(n(channel2)), \(n(channel3))] a=\(n(alpha)))"
    }
}

@_spi(SassCompilerProvider)
extension SassColor {
    public convenience init(space: String, _ channel1: Double?, _ channel2: Double?, _ channel3: Double?, alpha: Double?) throws {
        guard let space = Space(rawValue: space) else {
            throw SassFunctionError.badColorSpace(space)
        }
        self.init(space: space,
                  channel1, channel2, channel3,
                  alpha: alpha)
    }
}

extension SassValue {
    /// Reinterpret the value as a color.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't a color.
    public func asColor() throws -> SassColor {
        guard let selfColor = self as? SassColor else {
            throw SassFunctionError.wrongType(expected: "SassColor", actual: self)
        }
        return selfColor
    }
}
