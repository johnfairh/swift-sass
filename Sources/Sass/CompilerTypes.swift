//
//  CompilerTypes.swift
//  Sass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//
//  Much text here taken verbatim or only slightly editted from the embedded Sass
//  protocol specification.
//  Copyright (c) 2019, Google LLC
//  Licensed under MIT (https://github.com/sass/embedded-protocol/blob/master/LICENSE)
//

import Foundation

// Sass compiler interface types, shared between embedded Sass and libsass.

/// How the Sass compiler should format the CSS it produces.
public enum CssStyle: Sendable {
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

/// The [syntax used for a stylesheet](https://sass-lang.com/documentation/syntax).
public enum Syntax: Sendable {
    /// The CSS-superset `.scss` syntax.
    case scss

    /// The indented `.sass` syntax.
    case indented, sass

    /// Plain CSS syntax that doesn't support any special Sass features.
    case css
}

/// The kind of source map to generate for the stylesheet, returned in `CompilerResults.sourceMap`.
public enum SourceMapStyle: Sendable {
    /// Do not generate a source map.
    case none

    /// Generate a source map that references sources by URL only.
    case separateSources

    /// Generate a source map with embedded sources.
    case embeddedSources
}

/// Thrown as an error after a failed compilation.
public struct CompilerError: Swift.Error, CustomStringConvertible, Sendable {
    /// A message describing the reason for the failure.
    public let message: String

    /// Optionally, the section of stylesheet that triggered the failure.
    public let span: Span?

    /// The stack trace through the compiler input stylesheets that led to the failure.
    public let stackTrace: String?

    /// Any compiler diagnostics found before the error.
    public let messages: [CompilerMessage]

    /// The canonical URLs of all source files used before the compilation failed.
    ///
    /// If the compilation fails while attempting to import a file after determining its canonical URL
    /// then that file's URL is included in the list.
    ///
    /// This includes the URL of the initial Sass file if it is known.
    public let loadedURLs: [URL]

    /// A rich multi-line user-readable description of this error, containing  `message`, `span`,
    /// and `stackTrace`, but not `messages`.  This is provided by the underlying Sass compiler,
    /// format controlled using `CompilerMessageStyle`.
    public let description: String

    /// :nodoc:
    public init(message: String, span: Span?, stackTrace: String?, messages: [CompilerMessage], loadedURLs: [URL], description: String) {
        self.message = message
        self.span = span
        self.stackTrace = stackTrace
        self.messages = messages
        self.loadedURLs = loadedURLs
        self.description = description
    }
}

/// A section of a stylesheet.
public struct Span: CustomStringConvertible, Sendable {
    // MARK: Types

    /// A single point in a stylesheet.
    public struct Location: CustomStringConvertible, Sendable {
        /// The 0-based byte offset of this location within the stylesheet.
        public let offset: Int

        /// The 1-based line number of this location within the stylesheet.
        public let line: Int

        /// The 1-based column number of this location within its line.
        public let column: Int

        /// A short description of the location.
        public var description: String {
            "\(line):\(column)"
        }

        /// :nodoc:
        public init(offset: Int, line: Int, column: Int) {
            self.offset = offset
            self.line = line
            self.column = column
        }
    }

    // MARK: Properties

    /// The text covered by the span, or `nil` if there is no
    /// associated text.
    public let text: String?

    /// The URL of the stylesheet to which the span refers, or `nil` if it refers to
    /// an inline compilation that doesn't specify a URL.
    public let url: URL?

    /// The location of the first character in the span.
    public let start: Location

    /// The location of the first character after this span, or `nil` to mean
    /// the span is zero-length and points just before `start`.
    public let end: Location?

    /// Additional source text surrounding the span.
    ///
    /// This usually contains the full lines the span begins and ends on if the
    /// span itself doesn't cover the full lines.
    public let context: String?

    /// A short description of the span.
    public var description: String {
        var desc = url?.lastPathComponent ?? "[input]"
        desc.append(" \(start)")
        if let end = end {
            desc.append("-\(end)")
        }
        return desc
    }

    /// :nodoc:
    public init(text: String?, url: URL?, start: Location, end: Location?, context: String?) {
        self.text = text
        self.url = url
        self.start = start
        self.end = end
        self.context = context
    }
}

/// A diagnostic message generated by the Sass compiler that does not prevent the compilation
/// from succeeding.
///
/// Appropriate for display to end users who own the stylesheets.
public struct CompilerMessage: CustomStringConvertible, Sendable {
    // MARK: Types

    /// Kinds of diagnostic message.
    public enum Kind: Sendable {
        /// A warning for something other than a deprecated Sass feature. Often
        /// emitted due to a stylesheet using the [`@warn` rule](https://sass-lang.com/documentation/at-rules/warn).
        case warning

        /// A warning indicating that the stylesheet is using a deprecated Sass
        /// feature. The accompanying text does not include text like "deprecation warning".
        case deprecation

        /// Text from a [`@debug` rule](https://sass-lang.com/documentation/at-rules/debug).
        case debug
    }

    // MARK: Properties

    /// The kind of the message.
    public let kind: Kind

    /// The text of the message.
    public let message: String

    /// Optionally, the section of stylesheet that triggered the message.
    public let span: Span?

    /// The stack trace through the compiler input stylesheets that led to the message.
    public let stackTrace: String?

    /// A rich multi-line user-readable description of this error, containing the message, span,
    /// and stacktrace.  This is provided by the underlying Sass compiler, format controlled using
    /// `CompilerMessageStyle`.
    public let description: String

    /// :nodoc:
    public init(kind: Kind, message: String, span: Span?, stackTrace: String?, description: String) {
        self.kind = kind
        self.message = message
        self.span = span
        self.stackTrace = stackTrace
        self.description = description
    }
}

/// The format used for `CompilerError.description` and  `CompilerMessage.description`.
public enum CompilerMessageStyle: Sendable {
    /// Plain text.
    case plain

    /// Colorized with terminal escape sequences.
    case terminalColored
}

// Until Foundation catches up / decides we're wrong...
extension URL: @unchecked Sendable {}
