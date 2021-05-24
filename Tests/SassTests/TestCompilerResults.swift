//
//  TestCompilerResults.swift
//  DartSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation
import XCTest
import SourceMapper
import Sass

/// CompilerResults URL mangling -- all running against dummy css.
/// passed through unchanged here without looking at / touching mappings at all
class TestCompilerResults: XCTestCase {
    let dummyCSS = "Some CSS\n"
    func checkCss(_ css: String, sourceMapURL: String) throws {
        XCTAssertTrue(css.starts(with: dummyCSS))
        let matches = try XCTUnwrap(css.re_match(#"^/\*# sourceMappingURL=(.*) \*/$"#, options: .m))
        XCTAssertEqual(sourceMapURL, matches[1])
    }

    func checkSourceMap(_ mapStr: String, file: String, sourceRoot: String? = nil, sources: [String] = []) throws {
        let map = try SourceMap(string: mapStr)
        XCTAssertEqual(file, map.file)
        XCTAssertEqual(sourceRoot, map.sourceRoot)
        XCTAssertEqual(sources, map.sources.map(\.url))
    }

    func makeCompilerResults(sources: [String] = []) -> CompilerResults {
        let map = SourceMap()
        map.sources = sources.map { .init(url: $0) }
        return CompilerResults(css: "Some CSS\n", sourceMap: try! map.encodeString(), messages: [])
    }

    func testNoSourceMap() throws {
        let results = CompilerResults(css: dummyCSS, sourceMap: nil, messages: [])
        do {
            let updated = try results.withFileLocations(cssFileURL: URL(fileURLWithPath: "out.css"),
                                                        sourceMapFileURL: URL(fileURLWithPath: "out.css.map"))
            XCTFail("Worked: \(updated))")
        } catch let error as CompilerResults.Error {
            print(error)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAllAbsolute() throws {
        let cssURL = URL(fileURLWithPath: "out.css")
        let mapURL = URL(fileURLWithPath: "out.css.map")
        let results = try makeCompilerResults()
            .withFileLocations(cssFileURL: cssURL,
                               sourceMapFileURL: mapURL,
                               style: .allAbsolute)

        try checkCss(results.css, sourceMapURL: mapURL.absoluteString)
        try checkSourceMap(try XCTUnwrap(results.sourceMap), file: "out.css")
    }
}

// quickly grabbed and chopped up RE lib from bebop...

/// Provide concise aliases for regexp options
extension NSRegularExpression.Options {
    /// Case insensitive
    static let i = Self.caseInsensitive
    /// Comments
    static let x = Self.allowCommentsAndWhitespace
    /// Dot matches line endings
    static let s = Self.dotMatchesLineSeparators
    /// ^ $ match lines not text
    static let m = Self.anchorsMatchLines
    /// unicode-correct \b -- maybe this should always be on?
    static let w = Self.useUnicodeWordBoundaries
}

extension String {
    /// Regex match result data
    ///
    /// This is more than an array of strings because of named capture groups
    struct ReMatchResult {
        private let string: String
        private let textCheckingResult: NSTextCheckingResult

        fileprivate init(string: String, textCheckingResult: NSTextCheckingResult) {
            self.string = string
            self.textCheckingResult = textCheckingResult
        }

        /// Get the capture group contents.  Index 0 is the entire match.
        /// Returns the empty string for optional capture groups that were not matched.
        public subscript(rangeIndex: Int) -> String {
            let nsRange = textCheckingResult.range(at: rangeIndex)
            return String(string.from(nsRange: nsRange) ?? "")
        }
    }

    /// Match the regular expression against the string and return info about the first match
    ///
    /// - parameter pattern: pattern to match against
    /// - parameter options: regex options
    /// - returns: `ReMatchResult` object that can be queried for capture groups, or `nil` if there is no match
    func re_match(_ pattern: String,
                  options: NSRegularExpression.Options = []) -> ReMatchResult? {
        let re = try! NSRegularExpression(pattern: pattern, options: options)
        guard let match = re.firstMatch(in: self, range: nsRange) else {
            return nil
        }
        return ReMatchResult(string: self, textCheckingResult: match)
    }

    /// Feel like this exists somewhere already...
    private var nsRange: NSRange {
        NSRange(startIndex..<endIndex, in: self)
    }

    /// And this too...
    private func from(nsRange: NSRange) -> Substring? {
        Range(nsRange, in: self).flatMap { self[$0] }
    }
}
