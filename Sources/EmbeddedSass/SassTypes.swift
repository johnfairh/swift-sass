//
//  SassTypes.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

// Sass interface types, common between any implementation.
// Doc comments mostly lifted from sass docs.

/// Namespace
public enum Sass {
    /// Possible ways to format the CSS produced by a Sass compiler.
    public enum OutputStyle {
        /// Each selector and declaration is written on its own line.
        case expanded

        /// The entire stylesheet is written on a single line, with as few
        /// characters as possible.
        case compressed

        /// CSS rules and declarations are indented to match the nesting of the
        /// Sass source.
        case nested

        /// Each CSS rule is written on its own single line, along with all its
        /// declarations.
        case compact
    }

    /// Language used for some input to a Sass compiler.
    public enum InputSyntax {
        /// The CSS-superset `.scss` syntax.
        case scss

        /// The indented `.sass` syntax.
        case indented, sass

        /// Plain CSS syntax that doesn't support any special Sass features.
        case css
    }

    /// Results of a successful compilation.
    public struct Results {
        /// The  CSS output from the compiler.
        public let css: String
        /// The JSON sourcemap, provided only if requested at compile time.
        public let sourceMap: String?
    }

    /// Error thrown indicating a failed compilation.
    public struct CompilerError: Error {
        /// A message describing the reason for the failure.
        public let message: String

        /// The span if any associated with the failure.
        public let span: SourceSpan?

        /// The stack trace associated with the failure.
        public let stackTrace: String?
    }

    /// A section of a source file.
    public struct SourceSpan {
        /// The text covered by the source span, or `nil` if there is no
        /// source text associated with this report.
        public let text: String?

        /// The URL of the file to which this span refers, or `nil` if it refers to
        /// an inline compilation that doesn't specify a URL.
        public let url: String?

        /// A single point in s source file.
        public struct Location {
            /// The 0-based byte offset of this location within the source file.
            public let offset: Int

            /// The 0-based line number of this location within the source file.
            public let line: Int

            /// The 0-based column number of this location within its line.
            public let column: Int
        }

        /// The location of the first character in this span.
        public let start: Location

        /// The location of the first character after this span, or `nil` to mean
        /// this span is zero-length and points just before `start`.
        public let end: Location?

        /// Additional source text surrounding this span.
        ///
        /// This usually contains the full lines the span begins and ends on if the
        /// span itself doesn't cover the full lines.
        public let context: String?
    }

    /// Kinds of messages generated during compilation that do not prevent a successful result.
    public enum WarningType {
        /// A warning for something other than a deprecated Sass feature. Often
        /// emitted due to a stylesheet using the `@warn` rule.
        case warning

        /// A warning indicating that the stylesheet is using a deprecated Sass
        /// feature. The accompanying text does include text like "deprecation warning".
        case deprecation
    }

    /// A message generated by the compiler during compilation that does not prevent a
    /// successful result.  Appropriate for display to end users that own the stylesheets.
    public struct CompilerWarning {
        /// Type of the message.
        public let type: WarningType

        /// Text of the message, english.
        public let message: String

        /// Optionally a description of the source that triggered the warning.
        public let span: SourceSpan?

        /// The stack trace through the compiler input source files leading to the
        /// point of the warning.
        public let stackTrace: String?
    }

    /// A routine to receive log events during compilation.
    public typealias WarningHandler = (CompilerWarning) -> Void

    /// A log message generated by the system.  May help with debug.
    /// Not for end users.
    public struct DebugMessage {
        /// Text of the message, english.
        public let message: String

        /// Optionally a description of the source that triggered the log.
        public let span: SourceSpan?
    }

    /// A routine to receive log events during compilation.
    public typealias DebugHandler = (DebugMessage) -> Void
}

// MARK: Pretty-printers

extension Sass.SourceSpan.Location: CustomStringConvertible {
    /// A short human-readable description of the location.
    public var description: String {
        "\(line + 1):\(column + 1)"
    }
}

import Foundation

extension Sass.SourceSpan: CustomStringConvertible {
    /// A short human-readable description of the span.
    public var description: String {
        var desc = url.flatMap { URL(string: $0)?.lastPathComponent } ?? "[input]"
        desc.append(" \(start)")
        if let end = end {
            desc.append("-\(end)")
        }
        return desc
    }
}

/// Gadget to share implementation between the subtly different error/warning/debug log types.
protocol LogFormatter {
    var message: String { get }
    var messageType: String? { get }
    var span: Sass.SourceSpan? { get }
    var stackTrace: String? { get }

    var description: String { get }
}

extension LogFormatter {
    var messageType: String? { nil }

    /// A  human-readable description of the message.
    public var description: String {
        var desc = span.flatMap { "\($0): " } ?? ""
        desc += messageType.flatMap { "\($0): " } ?? ""
        desc += message
        if let trace = stackTrace?.trimmingCharacters(in: .newlines),
           !trace.isEmpty {
            let paddedTrace = trace.split(separator: "\n")
                .map { "    " + $0 }
                .joined(separator: "\n")
            desc += "\n\(paddedTrace)"
        }
        return desc
    }
}

extension Sass.CompilerError: CustomStringConvertible, LogFormatter {
    var messageType: String? { "error" }
}

extension Sass.WarningType: CustomStringConvertible {
    /// A human-readable description of the warning type.
    public var description: String {
        switch self {
        case .deprecation: return "deprecation warning"
        case .warning: return "warning"
        }
    }
}

extension Sass.CompilerWarning: CustomStringConvertible, LogFormatter {
    var messageType: String? { type.description }
}

extension Sass.DebugMessage: CustomStringConvertible, LogFormatter {
    var stackTrace: String? { nil }
}