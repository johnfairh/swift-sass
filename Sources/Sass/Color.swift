//
//  Color.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// MARK: Color values

private func checkRgb(_ val: Int, channel: String) throws -> Int {
    if !(0...255).contains(val) {
        throw SassValueError.channelNotInRange(channel, Double(val), "0...255")
    }
    return val
}

private func check(_ val: Double, range: ClosedRange<Double>, channel: String) throws -> Double {
    guard let clamped = SassDouble(val).clampTo(range: range) else {
        throw SassValueError.channelNotInRange(channel, val, range.description)
    }
    return clamped
}

private func checkAlpha(_ val: Double) throws -> Double {
    try check(val, range: 0...1, channel: "alpha")
}

private func checkSatLight(_ val: Double, channel: String) throws -> Double {
    try check(val, range: 0...100, channel: channel)
}

/// RGB
struct RgbColor: Hashable, CustomStringConvertible {
    let red: Int
    let green: Int
    let blue: Int

    var description: String {
        "RGB(\(red), \(green), \(blue))"
    }

    init(red: Int, green: Int, blue: Int) throws {
        self.red = try checkRgb(red, channel: "red")
        self.green = try checkRgb(green, channel: "green")
        self.blue = try checkRgb(blue, channel: "blue")
    }

    /// HSL -> RGB
    /// https://www.w3.org/TR/css-color-3/#hsl-color
    init(_ hsl: HslColor) {
        let h = hsl.hue / 360
        let s = hsl.saturation / 100
        let l = hsl.lightness / 100

        let m2: Double = {
            if l <= 0.5 {
                return l * (s + 1)
            }
            return l + s - l * s
        }()
        let m1 = l * 2 - m2

        func hueToRgb(_ h: Double) -> Double {
            let hue = h < 0 ? h + 1 : (h > 1 ? h - 1 : h)
            if hue * 6 < 1 {
                return m1 + (m2 - m1) * hue * 6
            }
            if hue * 2 < 1 {
                return m2
            }
            if hue * 3 < 2 {
                return m1 + (m2 - m1) * (2/3 - h) * 6
            }
            return m1
        }

        let r = hueToRgb(h + 1/3)
        let g = hueToRgb(h)
        let b = hueToRgb(h - 1/3)

        self.red = Int((r * 255).rounded())
        self.green = Int((g * 255).rounded())
        self.blue = Int((b * 255).rounded())
    }
}

/// HSL + A
struct HslColor: Equatable, CustomStringConvertible {
    let hue: Double
    let saturation: Double
    let lightness: Double

    var description: String {
        "HSL(\(hue)°, \(saturation)%, \(lightness)%)"
    }

    init(hue: Double, saturation: Double, lightness: Double) throws {
        self.hue = hue < 0 ? hue + 360 : hue
        self.saturation = try checkSatLight(saturation, channel: "saturation")
        self.lightness = try checkSatLight(lightness, channel: "lightness")
    }

    /// RGB -> HSL
    /// Reworked https://en.wikipedia.org/wiki/HSL_and_HSV#From_RGB
    init(_ rgb: RgbColor) {
        let r = Double(rgb.red) / 255
        let g = Double(rgb.green) / 255
        let b = Double(rgb.blue) / 255

        let xMax = max(r, b, g)
        let xMin = min(r, b, g)
        let c = xMax - xMin
        let h: Double = {
            if c == 0 {
                return 0
            }
            if xMax == r {
                let inter = (g - b) / c
                return inter < 0 ? inter + 6 : inter
            }
            if xMax == g {
                return (2 + (b - r) / c)
            }
            // xMax == b
            return (4 + (r - g) / c)
        }() * 60

        let l = (xMax + xMin) / 2

        let sl: Double = {
            if c == 0 {
                return 0
            }
            return c / (2 * min(l, 1 - l))
        }()

        self.hue = h
        self.saturation = sl * 100
        self.lightness = l * 100
    }
}

/// Wrap up representation & lazy conversion & alpha
enum ColorValue: CustomStringConvertible {
    case rgb(RgbColor, Double)
    case hsl(HslColor, Double)
    case rgb_hsl(RgbColor, HslColor, Double)

    init(_ rgb: RgbColor, alpha: Double) throws {
        self = .rgb(rgb, try checkAlpha(alpha))
    }

    init(_ hsl: HslColor, alpha: Double) throws {
        self = .hsl(hsl, try checkAlpha(alpha))
    }

    init(_ val: ColorValue, alpha: Double) throws {
        let newAlpha = try checkAlpha(alpha)
        switch val {
        case let .rgb(r, _): self = .rgb(r, newAlpha)
        case let .hsl(h, _): self = .hsl(h, newAlpha)
        case let .rgb_hsl(r, h, _): self = .rgb_hsl(r, h, newAlpha)
        }
    }

    var prefersRgb: Bool {
        switch self {
        case .rgb(_, _), .rgb_hsl(_, _, _): return true
        case .hsl(_, _): return false
        }
    }

    mutating func rgb() -> RgbColor { // 'var' can't be mutating!
        switch self {
        case let .rgb(r, _), let .rgb_hsl(r, _, _): return r
        case let .hsl(h, a):
            let r = RgbColor(h)
            self = .rgb_hsl(r, h, a)
            return r
        }
    }

    mutating func hsl() -> HslColor {
        switch self {
        case let .hsl(h, _), let .rgb_hsl(_, h, _): return h
        case let .rgb(r, a):
            let h = HslColor(r)
            self = .rgb_hsl(r, h, a)
            return h
        }
    }

    var alpha: Double {
        switch self {
        case let .rgb(_, a),
             let .hsl(_, a),
             let .rgb_hsl(_, _, a): return a
        }
    }

    var componentDescription: String {
        switch self {
        case .rgb(let r, _), .rgb_hsl(let r, _, _): return r.description
        case .hsl(let h, _): return h.description
        }
    }

    var description: String {
        "\(componentDescription) alpha=\(alpha)"
    }
}

// MARK: SassColor

/// A Sass color value.
public final class SassColor: SassValue {
    private var colorValue: ColorValue

    private init(_ value: ColorValue) {
        self.colorValue = value
    }

    /// Create a `SassColor` from RGB and alpha components.
    /// - parameter red: Red channel, must be between 0 and 255.
    /// - parameter green: Green channel, must be between 0 and 255.
    /// - parameter blue: Blue channel, must be between 0 and 255.
    /// - parameter alpha: Alpha channel, between 0.0 and 1.0.
    /// - throws: `SassValueError.channelNotInRange(...)` if any parameter is out of range.
    public init(red: Int, green: Int, blue: Int, alpha: Double = 1.0) throws {
        colorValue = try ColorValue(RgbColor(red: red, green: green, blue: blue), alpha: alpha)
    }

    /// Create a `SassColor` from HSL and alpha components.
    /// - parameter hue: Hue, from 0 to 360.
    /// - parameter saturation: Saturation, from 0 to 100.
    /// - parameter lightness: Lightness, from 0 to 100.
    /// - parameter alpha: Alpha channel, between 0.0 and 1.0.
    /// - throws: `SassValueError.channelNotInRange(...)` if any parameter is out of range.
    public init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1.0) throws {
        colorValue = try ColorValue(HslColor(hue: hue, saturation: saturation, lightness: lightness), alpha: alpha)
    }

    /// The red channel, between 0 and 255.
    public var red: Int { colorValue.rgb().red }
    /// The green channel, between 0 and 255.
    public var green: Int { colorValue.rgb().green }
    /// The blue channel, between 0 and 255.
    public var blue: Int { colorValue.rgb().blue }
    /// The HSL hue channel, between 0 and 360.
    public var hue: Double { colorValue.hsl().hue }
    /// The HSL saturation channel, between 0 and 100.
    public var saturation: Double { colorValue.hsl().saturation }
    /// The HSL lightness channel, between 0 and 100.
    public var lightness: Double { colorValue.hsl().lightness }
    /// The alpha channel between 0 and 1.
    public var alpha: Double { colorValue.alpha }

    /// Create a new `SassColor` by changing some of the RGB-A channels of this color.
    public func change(red: Int? = nil, green: Int? = nil, blue: Int? = nil, alpha: Double? = nil) throws -> SassColor {
        let rgb = colorValue.rgb()
        let newRed = red ?? rgb.red
        let newGreen = green ?? rgb.green
        let newBlue = blue ?? rgb.blue
        let newAlpha = alpha ?? colorValue.alpha
        return try SassColor(red: newRed, green: newGreen, blue: newBlue, alpha: newAlpha)
    }

    /// Create a new `SassColor` by changing some of the HSL-A channels of this color.
    public func change(hue: Double? = nil, saturation: Double? = nil, lightness: Double? = nil, alpha: Double? = nil) throws -> SassColor {
        let hsl = colorValue.hsl()
        let newHue = hue ?? hsl.hue
        let newSaturation = saturation ?? hsl.saturation
        let newLightness = lightness ?? hsl.lightness
        let newAlpha = alpha ?? colorValue.alpha
        return try SassColor(hue: newHue, saturation: newSaturation, lightness: newLightness, alpha: newAlpha)
    }

    /// Create a new `SassColor` by changing just the alpha channel of this color.
    public func change(alpha: Double) throws -> SassColor {
        SassColor(try ColorValue(colorValue, alpha: alpha))
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(color: self)
    }

    public override var description: String {
        "Color(\(colorValue))"
    }

    /// Colors are compared in their RGB-A forms, using  only 11 DP for the alpha.
    public static func == (lhs: SassColor, rhs: SassColor) -> Bool {
        lhs.colorValue.rgb() == rhs.colorValue.rgb() &&
            SassDouble.areEqual(lhs.colorValue.alpha, rhs.colorValue.alpha)
    }

    /// Hash the color.
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(colorValue.rgb())
        hasher.combine(SassDouble.hashEquivalent(colorValue.alpha))
    }

    /// :nodoc: helper for embedded protocol serialization
    public var _prefersRgb: Bool {
        colorValue.prefersRgb
    }
}

extension SassValue {
    /// Reinterpret the value as a color.
    /// - throws: `SassTypeError` if it isn't a color.
    public func asColor() throws -> SassColor {
        guard let selfColor = self as? SassColor else {
            throw SassValueError.wrongType(expected: "SassColor", actual: self)
        }
        return selfColor
    }
}
