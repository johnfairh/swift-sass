//
//  ArgumentList.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// A Sass value representing a `$arg...` function argument list.
///
/// This type is a `SassList` holding positional arguments with an addition set of
/// named keyword arguments.  See [the Sass docs](https://sass-lang.com/documentation/at-rules/mixin#taking-arbitrary-arguments).
///
/// - warning: You'll typically use this type to access arguments passed in this way to a custom Sass
///   function.  Be careful in other scenarios: the keyword argument part of the type is excluded
///   from equality and listification, meaning it is easy to accidentally lose that part of the type
///   when passing instances through generic `SassValue` code.
public final class SassArgumentList: SassList {
    // MARK: Initializers

    /// Initialize a new argument list with the contents of a Swift sequence.
    ///
    /// - parameter positional: The `Sequence` whose contents should make up the positional
    ///   arguments of the argument list.
    /// - parameter keywords: The keywords and values to make the keyword arguments of the
    ///   argument list.  Default is no keyword arguments.
    /// - parameter keywordsObserver: A callback to be invoked when the keywords are accessed.
    ///   Used by compiler implementations.  Default is an observer that does nothing.
    /// - parameter separator: The separator character to use in any CSS generated from the list.
    ///   If `sequence` contains more than one element then an `.undecided` separator is promoted
    ///   to `.space`.
    public init<C>(_ positional: C,
                   keywords: [String: SassValue] = [:],
                   keywordsObserver: @escaping () -> Void = {},
                   separator: Separator = .space) where C: Sequence, C.Element == SassValue {
        self._keywords = keywords
        self.keywordsObserver = keywordsObserver
        super.init(positional, separator: separator, hasBrackets: false)
    }

    // MARK: Keyword arguments

    private let _keywords: [String: SassValue]
    private let keywordsObserver: () -> Void

    /// The argument list's keyword arguments.
    ///
    /// Any keywords observer is notified on every access to this property.
    public var keywords: [String: SassValue] {
        keywordsObserver()
        return _keywords
    }

    // MARK: Misc

    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(argumentList: self)
    }

    // Does not count as 'accessing keywords'!
    public override var description: String {
        "ArgList(" +
            map { $0.description }.joined(separator: separator.rawValue) +
            " kw(" +
            _keywords.map { "[\($0.0):\($0.1)]" }.joined(separator: ",") +
            "))"
    }
}

extension SassValue {
    /// Reinterpret the value as an argument list.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't an argument list.
    public func asArgumentList() throws -> SassArgumentList {
        guard let selfArgList = self as? SassArgumentList else {
            throw SassFunctionError.wrongType(expected: "SassArgumentList", actual: self)
        }
        return selfArgList
    }
}
