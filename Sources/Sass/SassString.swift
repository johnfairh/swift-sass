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
open class SassString: SassValue {
    /// The text value of the string.  Does not include any quotes.
    public let text: String
    /// Whether the string is quoted " or raw.
    public let isQuoted: Bool

    /// Initialize a new string.  You should quote strings unless there's a good reason not to.
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
    public func scalarIndexFrom(sassIndex: SassValue) throws -> String.UnicodeScalarIndex {
        throw SassValueError.subscriptType(sassIndex)
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(string: self)
    }

    /// A short description of the string.
    public override var description: String {
        let quote = isQuoted ? "\"" : ""
        return "String(\(quote)\(text)\(quote))"
    }

    /// String equality: two `SassString`s are equal if they have the same text, whether or not either is quoted.
    public static func == (lhs: SassString, rhs: SassString) -> Bool {
        lhs.text == rhs.text
    }

    /// Hash the string's text.
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

extension SassValue {
    /// Reinterpret the value as a string.
    /// - throws: `SassTypeError` if it isn't a string.
    public func asString() throws -> SassString {
        guard let selfString = self as? SassString else {
            throw SassValueError.wrongType(expected: "SassString", actual: self)
        }
        return selfString
    }
}
