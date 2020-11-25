//
//  SassList.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

/// A SassScript list.
///
/// Sass lists are immutable, have a separator and may be surrounded with brackets.
/// All Sass values can be treated as lists so much list-like behavior is available via
/// `SassValue`.  This type is mostly useful for constructing your own multi-element lists.
open class SassList: SassValue {
    /// A CSS list-separator style.
    public enum Separator: String, Equatable {
        /// Comma
        case comma = ","
        /// Whitespace
        case space = " "
        /// Forward slash
        case slash = "/"
        /// Not yet determined: singleton and empty lists don't have
        /// separators defined.
        case undecided = "?"
    }

    private let elements: [SassValue]
    private let _separator: Separator
    private let _hasBrackets: Bool
    public override var separator: Separator { _separator }
    public override var hasBrackets: Bool { _hasBrackets }
    override var listCount: Int { elements.count }

    /// Initialize a new list with the contents of a Swift collection.
    ///
    /// - parameter sequence: The `Sequence` whose contents should be copied into the list.
    /// - parameter separator: The separator character to use in any CSS generated from the list.
    ///   If `sequence` contains more than one element then an `.undecided` separator is promoted
    ///   to `.space`.
    /// - parameter hasBrackets: Whether the list should display with brackets.  Normally `true`.
    public init<C>(_ sequence: C, separator: Separator = .space, hasBrackets: Bool = true)
    where C: Sequence, C.Element == SassValue {
        self.elements = Array(sequence)
        self._hasBrackets = hasBrackets
        if elements.count > 1 && separator == .undecided {
            self._separator = .space
        } else {
            self._separator = separator
        }
    }

    public override func valueAt(sassIndex: SassValue) throws -> SassValue {
        let arrayIndex = try arrayIndexFrom(sassIndex: sassIndex)
        return elements[arrayIndex]
    }

    /// An iterator for the values in the list.
    public override func makeIterator() -> AnyIterator<SassValue> {
        AnyIterator(elements.makeIterator())
    }

    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(list: self)
    }

    /// A short description of the list.
    public override var description: String {
        "List(\(hasBrackets ? "[" : "")" +
            map { $0.description }.joined(separator: separator.rawValue) +
            "\(hasBrackets ? "]" : ""))"
    }

    /// List equality: two `SassList`s are equal if they have the same separator, brackets, and contents.
    ///
    /// TODO "An empty list is equal to an empty map." ffs - hashing!!
    public static func == (lhs: SassList, rhs: SassList) -> Bool {
        lhs.hasBrackets == rhs.hasBrackets &&
            lhs.separator == rhs.separator &&
            lhs.listCount == rhs.listCount &&
            zip(lhs, rhs).reduce(true) { eq, next in eq && next.0 == next.1 }
    }

    /// Hashes the list's properties and contents.
    public override func hash(into hasher: inout Hasher) {
        forEach { $0.hash(into: &hasher) }
        hasher.combine(hasBrackets)
        hasher.combine(separator)
    }
}
