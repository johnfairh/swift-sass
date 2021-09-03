//
//  List.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A Sass list value.
///
/// Sass lists have a separator and may be surrounded with brackets.
/// All Sass values can be treated as lists so much list-like behavior is available via
/// `SassValue`.  `SassList` is mostly useful for constructing your own multi-element lists.
public class SassList: SassValue {
    // MARK: Types
    /// The list-separator character.
    public enum Separator: String, Equatable {
        /// Comma.
        case comma = ","
        /// Whitespace.
        case space = " "
        /// Forward slash.
        case slash = "/"
        /// Not yet determined: singleton and empty lists don't have
        /// separators defined.
        case undecided = "?"
    }

    // MARK: Initializers

    /// Initialize a new list with the contents of a Swift sequence.
    ///
    /// - parameter sequence: The `Sequence` whose contents should be copied into the list.
    /// - parameter separator: The separator character to use in any CSS generated from the list.
    ///   If `sequence` contains more than one element then an `.undecided` separator is promoted
    ///   to `.space`.
    /// - parameter hasBrackets: Whether the list should display with brackets.  Normally `true`.
    public init<C>(_ sequence: C, separator: Separator = .space, hasBrackets: Bool = true)
    where C: Sequence, C.Element == SassValue {
        self.array = Array(sequence)
        self._hasBrackets = hasBrackets
        if array.count > 1 && separator == .undecided {
            self._separator = .space
        } else {
            self._separator = separator
        }
    }

    // MARK: Properties

    private let array: [SassValue]
    private let _separator: Separator
    private let _hasBrackets: Bool
    /// The list separator.
    public override var separator: Separator { _separator }
    /// Does the list have brackets?
    public override var hasBrackets: Bool { _hasBrackets }
    public override var listCount: Int { array.count }

    // MARK: Methods

    public override func valueAt(sassIndex: SassValue) throws -> SassValue {
        let arrayIndex = try arrayIndexFrom(sassIndex: sassIndex)
        return array[arrayIndex]
    }

    // MARK: Misc

    /// List equality: all empty `SassList`s are equal.  Non-empty lists are equal iff they have the same separator, brackets, and contents.
    public static func == (lhs: SassList, rhs: SassList) -> Bool {
        // Dart Sass defines the `==` relation on `List` to make it not be an
        // equivalance relation (two empty lists with different separators are not
        // equal to each other, but both are equal to the empty map) which is not
        // OK in Swift.  This feels like the easiest tweak to make it work.
        (lhs.array.isEmpty && rhs.array.isEmpty) ||
            (lhs.hasBrackets == rhs.hasBrackets &&
                lhs.separator == rhs.separator &&
                lhs.array == rhs.array)
    }

    private static let emptyMap = SassMap([:])

    /// Hashes the list's properties and contents.
    public override func hash(into hasher: inout Hasher) {
        if array.isEmpty {
            // Sass requires that empty lists and maps are the same.
            // The cross-type equality part of this is handled in `SassValue.==(_:_:)`.
            //
            // Further to "all empty lists are equal to each other" above, all empty
            // lists hash as though they were the empty map.
            hasher.combine(SassList.emptyMap)
        } else {
            hasher.combine(array)
            hasher.combine(hasBrackets)
            hasher.combine(separator)
        }
    }

    /// An iterator for the values in the list.
    public override func makeIterator() -> AnyIterator<SassValue> {
        AnyIterator(array.makeIterator())
    }

    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(list: self)
    }

    public override var description: String {
        "List(\(hasBrackets ? "[" : "")" +
            map { $0.description }.joined(separator: separator.rawValue) +
            "\(hasBrackets ? "]" : ""))"
    }
}
