//
//  SassString.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A SassScript string.
///
/// Strings are immutable and may be quoted.
///
/// ## SassString indexes
///
/// Sass models strings as a sequence of unicode scalars, not Swift's primary view as a sequence
/// of extended grapheme clusters.  So any string index you receive through Sass applies to the unicode
/// scalar view of the string.
///
/// Further, Sass models 1 as the first element and `count` as the last.  This class offers
/// a `sassIndexToSwiftIndex(...)`  method to wrap up both parts of this conversion, but offers
/// only sympathy to users having to deal with the results.
public class SassString: SassValue, Hashable, CustomStringConvertible {
    /// The text value of the string.  Does not include any quotes.
    public let text: String
    /// Whether the string is quoted " or raw.
    public let isQuoted: Bool

    /// Initialize a new string.  Quote the string unless there's a good reason not to.
    public init(_ text: String, isQuoted: Bool = true) {
        self.text = text
        self.isQuoted = isQuoted
    }

    /// The length of the string according to Sass.
    ///
    /// The number of unicode scalars in the string.
    public var sassLength: Int {
        text.unicodeScalars.count
    }

    /// Interpret a Sass string index.
    /// - parameter index: A Sass value intended to be used as a string index.  This must be an
    ///   integer between 1 and `sassLength` inclusive.
    /// - throws: `SassValueError` if `index` is not an integer or out of range.
    public func sassIndexToScalarIndex(_ index: SassValue) throws -> String.UnicodeScalarIndex {
        throw SassValueError.subscriptType(index)
    }

    public override var css: String {
        let quote = isQuoted ? "\"" : ""
        return "\(quote)\(text)\(quote)"
    }

    /// : nodoc:
    public var description: String {
        "String(\(css))"
    }

    /// Two `SassString`s are equal if they have the same text, whether or not either is quoted.
    public static func == (lhs: SassString, rhs: SassString) -> Bool {
        lhs.text == rhs.text
    }

    /// Two `SassString`s are equal if they have the same text, whether or not either is quoted.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

extension SassValue {
    /// Reinterpret the value as a string.
    /// - throws: `SassTypeError` if it isn't a string.
    public func asString() throws -> SassString {
        guard let selfString = self as? SassString else {
            throw SassValueError.wrongType(expected: "String", actual: self)
        }
        return selfString
    }
}
