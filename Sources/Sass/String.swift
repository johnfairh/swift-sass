//
//  String.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A Sass string value.
///
/// Strings may be quoted.
///
/// ## SassString indexes
///
/// Sass models strings as a sequence of unicode scalars, not Swift's primary view as a sequence
/// of extended grapheme clusters.  So any string index you receive through Sass applies to the unicode
/// scalar view of the string.
///
/// Further, Sass models 1 as the index of the first scalar in the string, and `count` as the index of the last.
/// This class offers a `scalarIndexFrom(sassIndex:)`  method to wrap up both parts of this
/// conversion, but offers only sympathy to users having to deal with the results.
///
/// `SassString` conforms to `Sequence` via `SassValue`.  This sequence is a singleton sequence
/// containing the string value, not a sequence of scalars.
public final class SassString: SassValue {
    // MARK: Initializers

    /// Initialize a new string.  You should quote strings unless there's a good reason not to.
    public init(_ string: String, isQuoted: Bool = true) {
        self.string = string
        self.isQuoted = isQuoted
    }

    // MARK: Properties

    /// The value of the string.  Does not include any quotes.
    public let string: String
    /// Whether the string is quoted " or raw.
    public let isQuoted: Bool

    /// The length of the string according to Sass.
    ///
    /// The number of unicode scalars in the string.
    public var sassLength: Int {
        string.unicodeScalars.count
    }

    // MARK: Methods

    /// Interpret a Sass string index.
    /// - parameter index: A Sass value intended to be used as a string index.  This must be an
    ///   integer between 1 and `sassLength` inclusive, or negative with the same magnitude to
    ///   index from the end.
    /// - throws: `SassFunctionError` if `index` is not an integer or out of range.
    public func scalarIndexFrom(sassIndex: SassValue) throws -> String.UnicodeScalarIndex {
        let indexValue = try sassIndex.asNumber().asInt()
        guard indexValue.magnitude >= 1 && indexValue.magnitude <= sassLength else {
            throw SassFunctionError.badStringIndex(max: sassLength, actual: indexValue)
        }
        let offset = indexValue > 0 ? (indexValue - 1) : (sassLength + indexValue)
        return string.unicodeScalars.index(string.unicodeScalars.startIndex, offsetBy: offset)
    }

    // MARK: Misc

    /// Two `SassString`s are equal if they have the same text, whether or not either is quoted.
    public static func == (lhs: SassString, rhs: SassString) -> Bool {
        lhs.string == rhs.string
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(string: self)
    }

    public override var description: String {
        let quote = isQuoted ? "\"" : ""
        return "String(\(quote)\(string)\(quote))"
    }

    /// Hash the string's text.
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(string)
    }
}

extension SassValue {
    /// Reinterpret the value as a string.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't a string.
    public func asString() throws -> SassString {
        guard let selfString = self as? SassString else {
            throw SassFunctionError.wrongType(expected: "SassString", actual: self)
        }
        return selfString
    }
}
