//
//  TestImporters.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import NIO
@testable import DartSass
import SourceMapper

///
/// Tests for importers.
///
class TestImporters: DartSassTestCase {

    // MARK: Load Paths

    let importingSass = """
    @import secondary
    """
    let usingSass = """
    @use 'secondary'
    """

    let secondaryCssBlue = """
    a{color:blue}
    """
    let secondaryCssRed = """
    a{color:red}
    """
    let secondaryCssFilename = "secondary.css"

    private func createFileInNewDir(_ content: String, filename: String) throws -> URL {
        let tmpDir = try FileManager.default.createTemporaryDirectory()
        let url = tmpDir.appendingPathComponent(filename)
        try content.write(to: url)
        return tmpDir
    }

    // compiler loadpath works
    func testCompilerLoadPath() async throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let compiler = try newCompiler(importers: [.loadPath(tmpDir)])
        let results = try await compiler.compile(string: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // job loadpath works
    func testJobLoadPath() async throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let compiler = try newCompiler()
        let results = try await compiler.compile(string: usingSass, syntax: .sass,
                                                 outputStyle: .compressed,
                                                 importers: [.loadPath(tmpDir)])
        XCTAssertEqual(secondaryCssBlue, results.css)
        XCTAssertEqual(1, results.loadedURLs.count)
    }

    // job loadpath searched after compiler loadpath
    func testLoadPathOrder() async throws {
        let tmpDirBlue = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let tmpDirRed = try createFileInNewDir(secondaryCssRed, filename: secondaryCssFilename)
        let compiler = try newCompiler(importers: [.loadPath(tmpDirRed)])
        let results = try await compiler.compile(string: usingSass, syntax: .sass,
                                                 outputStyle: .compressed,
                                                 importers: [.loadPath(tmpDirBlue)])
        XCTAssertEqual(secondaryCssRed, results.css)
    }

    // nonsense in loadpath doesn't affect anyone (not even a warning!)
    func testNonsenseLoadPath() async throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let nonsenseDir = URL(fileURLWithPath: "/not/a/directory")
        let compiler = try newCompiler(importers: [.loadPath(nonsenseDir), .loadPath(tmpDir)])
        let results = try await compiler.compile(string: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // no implicit loadpath - 1.50.1 spec clarification
    func testImplicitLoadPath() async throws {
        let tmpDir = try FileManager.default.createTemporaryDirectory()
        let filename = "imported.scss"
        try "a { a: 'hello'; }".write(to: tmpDir.appendingPathComponent(filename))

        try await tmpDir.withCurrentDirectory {
            let compiler = try newCompiler()
            await compiler.waitForRunning()
            do {
                let results = try await compiler.compile(string: "@import 'imported';", outputStyle: .compressed)
                XCTFail("Managed to resolve import: \(results)")
            } catch {
                print(error)
            }

            let results = try await compiler.compile(string: "@import 'imported';",
                                                     outputStyle: .compressed,
                                                     importers: [.loadPath(tmpDir.absoluteURL)])
            XCTAssertEqual(#"a{a:"hello"}"#, results.css)
        }
    }

    // MARK: Custom Importers

    // A custom importer
    final class TestImporter: Importer, @unchecked Sendable {
        let css: String

        init(css: String) {
            self.css = css
        }

        /// State next request 'cannot be canonicalized'
        var failNextCanon: String? = nil
        var failedCanonCount = 0
        struct Error: Swift.Error, CustomStringConvertible {
            let message: String
            var description: String { message }
        }

        /// Claim next request
        var claimRequest: Bool = true
        var unclaimedRequestCount = 0

        func canonicalize(ruleURL: String, context: DartSass.ImporterContext) async throws -> URL? {
            if let failNextCanon = failNextCanon {
                failedCanonCount += 1
                throw Error(message: failNextCanon)
            }
            guard claimRequest else {
                unclaimedRequestCount += 1
                return nil
            }
            if ruleURL.starts(with: "test://") {
                return URL(string: ruleURL)
            }
            return URL(string: "test://\(ruleURL)")
        }

        /// Fail the next import
        var failNextImport: String? = nil
        var nilNextImport = false
        var failedImportCount = 0
        var nilImportCount = 0

        func load(canonicalURL: URL) async throws -> ImporterResults? {
            if let failNextImport = failNextImport {
                failedImportCount += 1
                throw Error(message: failNextImport)
            }
            if nilNextImport {
                nilImportCount += 1
                return nil
            }
            return ImporterResults(css, syntax: .css, sourceMapURL: canonicalURL)
        }
    }

    // Goodpath.
    func testCustomImporter() async throws {
        let importer = TestImporter(css: secondaryCssRed)
        let compiler = try newCompiler(importers: [.importer(importer)])
        let results = try await compiler.compile(string: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssRed, results.css)
        XCTAssertEqual("test://secondary", results.loadedURLs.first!.absoluteString)
    }

    // Bad path harness
    func checkFaultyImporter(customize: (TestImporter) -> Void, check: (TestImporter, CompilerError) -> Void) async throws {
        let importer = TestImporter(css: secondaryCssRed)
        customize(importer)
        let compiler = try newCompiler(importers: [.importer(importer)])
        do {
            let results = try await compiler.compile(string: usingSass, syntax: .sass)
            XCTFail("Compiled something: \(results)")
        } catch let error as CompilerError {
            check(importer, error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Canon says nil (not recognized)
    func testImportNotFound() async throws {
        try await checkFaultyImporter(customize: { $0.claimRequest = false }) { i, e in
            XCTAssertEqual(1, i.unclaimedRequestCount)
            XCTAssertTrue(e.message.contains("Can't find stylesheet"))
        }
    }

    // Canon fails (ambiguous)
    func testImportCanonFails() async throws {
        try await checkFaultyImporter(customize: { $0.failNextCanon = "Objection" }) { i, e in
            XCTAssertEqual(i.failNextCanon, e.message)
            XCTAssertEqual(1, i.failedCanonCount)
        }
    }

    // load fails
    func testImportFails() async throws {
        try await checkFaultyImporter(customize: { $0.failNextImport = "Objection" }) { i, e in
            XCTAssertEqual(i.failNextImport, e.message)
            XCTAssertEqual(1, i.failedImportCount)
            XCTAssertEqual(1, e.loadedURLs.count)
            XCTAssertEqual("test://secondary", e.loadedURLs[0].absoluteString)
        }
    }

    // load not-found (still don't really understand why this is here, canon works but then this fails?)
    func testImportNil() async throws {
        try await checkFaultyImporter(customize: { $0.nilNextImport = true }) { i, e in
            XCTAssertTrue(e.message.contains("Can't find stylesheet"))
            XCTAssertEqual(1, i.nilImportCount)
        }
    }

    // Async importer
    func testAsyncImporter() async throws {
        let importer = HangingAsyncImporter()
        let compiler = try newCompiler(importers: [.importer(importer)])
        let results = try await compiler.compile(string: "@import 'something';")
        XCTAssertEqual("", results.css)
    }

    // Importer for string source doc
    func testStringImporter() async throws {
        let importer = TestImporter(css: secondaryCssRed)
        let compiler = try newCompiler()
        let results = try await compiler.compile(string: "@import 'something';",
                                                 url: URL(string: "test://vfs"),
                                                 importer: .importer(importer),
                                                 outputStyle: .compressed)
        XCTAssertEqual("a{color:red}", results.css)
        XCTAssertEqual(2, results.loadedURLs.count)
        let srcmap = try SourceMap(XCTUnwrap(results.sourceMap))
        XCTAssertEqual(1, srcmap.sources.count)
        XCTAssertEqual("test://vfs/something", srcmap.sources[0].url)
    }

    // fromImport flag
    func testFromImport() async throws {
        final class FromImportTester: Importer, @unchecked Sendable {
            var expectFromImport = false
            var wasInvoked = false

            func expectNext(_ fromImport: Bool) {
                wasInvoked = false
                expectFromImport = fromImport
            }

            func check() {
                XCTAssertTrue(wasInvoked)
            }

            func canonicalize(ruleURL: String, context: ImporterContext) async throws -> URL? {
                XCTAssertFalse(wasInvoked)
                wasInvoked = true
                XCTAssertEqual(expectFromImport, context.fromImport)
                return URL(string: "test://\(ruleURL)")
            }

            func load(canonicalURL: URL) async throws -> ImporterResults? {
                ImporterResults("", syntax: .css, sourceMapURL: canonicalURL)
            }
        }
        let importer = FromImportTester()
        let compiler = try newCompiler(importers: [.importer(importer)])

        importer.expectNext(true)
        _ = try await compiler.compile(string: "@import 'something'")
        importer.check()

        importer.expectNext(false)
        _ = try await compiler.compile(string: "@use 'something'")
        importer.check()
    }

    // multiple imports, loaded
    func testMultipleLoadedURLs() async throws {
        let importer = TestImporter(css: "a { b: 'c' }")
        let compiler = try newCompiler(importers: [.importer(importer)])
        let rootURL = URL(string: "original://file")!
        let scss = """
                   @import 'first';
                   @import 'second';
                   div { b: 'c' }
                   """
        let results = try await compiler.compile(string: scss, syntax: .scss, url: rootURL)
        let map = try SourceMap(XCTUnwrap(results.sourceMap))
        XCTAssertEqual(3, map.sources.count)
        XCTAssertEqual(3, results.loadedURLs.count)

        func s(_ urls: [URL]) -> [URL] {
            urls.sorted(by: { $0.absoluteString < $1.absoluteString})
        }
        let expected = s([rootURL, URL(string: "test://first")!, URL(string: "test://second")!])
        XCTAssertEqual(expected, s(results.loadedURLs))
        XCTAssertEqual(expected, s(map.sources.map { URL(string: $0.url)! }))
    }

    // noncanonical + containingURL for regular importers
    func testNonCanonical() async throws {
        final class NonCanonImporter: Importer, @unchecked Sendable {
            var expectContainingURL: URL? = nil
            var wasInvoked: Bool = false

            func expect(_ containingURL: URL?) {
                wasInvoked = false
                expectContainingURL = containingURL
            }

            func canonicalize(ruleURL: String, context: ImporterContext) async throws -> URL? {
                XCTAssertFalse(wasInvoked)
                wasInvoked = true
                // Swift 6 Linux nil URLs are not equal to nil...
                if let expectContainingURL, let contextContainingURL = context.containingURL {
                    XCTAssertEqual(expectContainingURL, contextContainingURL)
                }
                return URL(string: "test://\(ruleURL)")
            }

            func load(canonicalURL: URL) async throws -> ImporterResults? {
                ImporterResults("", syntax: .css, sourceMapURL: canonicalURL)
            }

            let noncanonicalURLSchemes: [String] = ["noncanon"]
        }

        let importer = NonCanonImporter()
        let compiler = try newCompiler(importers: [.importer(importer)])

        func doTest(rule: String, expectedContainingURL: Bool) async throws {
            let rootURL = URL(string: "fake://url")!

            importer.expect(expectedContainingURL ? rootURL : nil)
            _ = try await compiler.compile(string: "@import '\(rule)';", url: rootURL)
            XCTAssertTrue(importer.wasInvoked)
        }

        try await doTest(rule: "fred", expectedContainingURL: true)
        try await doTest(rule: "noncanon://fred", expectedContainingURL: true)
        try await doTest(rule: "canon://fred", expectedContainingURL: false)
    }

    // MARK: Custom filesystem importers

    class FilesysImporter: FilesystemImporter, @unchecked Sendable {
        let directoryURL: URL
        private(set) var resolveCount: Int
        var nextUnknown: Bool
        var nextFail: Bool
        var expectImport: Bool
        var expectContainingURL: URL?

        struct Error: Swift.Error, CustomStringConvertible {
            let description: String
        }

        init(_ directoryURL: URL) {
            self.directoryURL = directoryURL
            resolveCount = 0
            nextUnknown = false
            nextFail = false
            expectImport = false
        }

        func resolve(ruleURL: String, context: DartSass.ImporterContext) async throws -> URL? {
            resolveCount += 1
            XCTAssertEqual(expectImport, context.fromImport, ruleURL)
            // WTF Swift 6 Linux "nil != Optional()" smh
            if let expectContainingURL, let contextContainingURL = context.containingURL {
                XCTAssertEqual(expectContainingURL, contextContainingURL, ruleURL)
            }
            guard !nextUnknown else {
                nextUnknown = false
                return nil
            }

            guard !nextFail else {
                nextFail = false
                throw Error(description: "Programmed fail filesys import")
            }

            return directoryURL.appendingPathComponent(ruleURL)
        }
    }

    func testFilesystem() async throws {
        let dir = try FileManager.default.createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let imp = FilesysImporter(dir)

        let fileURL = dir.appendingPathComponent("test.scss")

        try "a { b: true }".write(to: fileURL)
        let compiler = try newCompiler(importers: [.filesystemImporter(imp)])

        // Goodpath, import
        imp.expectImport = true
        let results = try await compiler.compile(string: "@import 'test';", outputStyle: .compressed)
        XCTAssertEqual(1, imp.resolveCount)
        XCTAssertEqual(fileURL, results.loadedURLs[0])
        XCTAssertEqual("a{b:true}", results.css)

        // Goodpath, use
        imp.expectImport = false
        let results2 = try await compiler.compile(string: "@use 'test';", outputStyle: .compressed)
        XCTAssertEqual(2, imp.resolveCount)
        XCTAssertEqual("a{b:true}", results2.css)

        // Notfound
        imp.nextUnknown = true
        do {
            let res = try await compiler.compile(string: "@use 'test';", outputStyle: .compressed)
            XCTFail("Managed to resolve @use 'test': \(res)")
        } catch let error as CompilerError {
            XCTAssertTrue(error.message.contains("Can't find stylesheet"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(3, imp.resolveCount)

        // Err
        imp.nextUnknown = false
        imp.nextFail = true
        do {
            let res = try await compiler.compile(string: "@use 'test';", outputStyle: .compressed)
            XCTFail("Managed to resolve @use 'test': \(res)")
        } catch let error as CompilerError {
            XCTAssertTrue(error.message.contains("Programmed fail"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(4, imp.resolveCount)
    }

    /// Prove that the dart backend understands import-only
    func testFilesystemImportOnly() async throws {
        let dir = try FileManager.default.createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let imp = FilesysImporter(dir)

        let fileURL = dir.appendingPathComponent("test.scss")
        let importFileURL = dir.appendingPathComponent("test.import.scss")

        try "a { b: true }".write(to: fileURL)
        try "a { b: false }".write(to: importFileURL)
        let compiler = try newCompiler(importers: [.filesystemImporter(imp)])

        // Goodpath, import
        imp.expectImport = true
        let results = try await compiler.compile(string: "@import 'test';", outputStyle: .compressed)
        XCTAssertEqual(1, imp.resolveCount)
        XCTAssertEqual(importFileURL, results.loadedURLs[0])
        XCTAssertEqual("a{b:false}", results.css)
    }

    func testFilesystemContainingURL() async throws {
        let dir = try FileManager.default.createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let imp = FilesysImporter(dir)

        let fileURL = dir.appendingPathComponent("test.scss")

        let baseDir = try FileManager.default.createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let baseURL = baseDir.appendingPathComponent("main.scss")

        try "a { b: true }".write(to: fileURL)
        try "@import 'test';".write(to: baseURL)

        let compiler = try newCompiler(importers: [.filesystemImporter(imp)])

        imp.expectImport = true
        imp.expectContainingURL = baseURL
        let results = try await compiler.compile(fileURL: baseURL, outputStyle: .compressed)
        XCTAssertEqual(1, imp.resolveCount)
        XCTAssertEqual(baseURL, results.loadedURLs[0])
        XCTAssertEqual(fileURL, results.loadedURLs[1])
        XCTAssertEqual("a{b:true}", results.css)
    }

    // MARK: Node package importer

    func testNodePkgImporter() async throws {
        let rootDirURL = try FileManager.default.createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirURL) }

        let pkgDirURL = rootDirURL.appendingPathComponent("node_modules")
            .appendingPathComponent("test")
        try FileManager.default.createDirectory(at: pkgDirURL, withIntermediateDirectories: true)
        let packageJSONURL = pkgDirURL.appendingPathComponent("package.json")
        try """
        {
          "exports": {
            ".": {
              "sass": "./scss/index.scss"
            }
          }
        }
        """.write(to: packageJSONURL)

        let sassDirURL = pkgDirURL.appendingPathComponent("scss")
        try FileManager.default.createDirectory(at: sassDirURL, withIntermediateDirectories: true)

        let sassFileURL = sassDirURL.appendingPathComponent("index.scss")
        try "a { b: true }".write(to: sassFileURL)

        let compiler = try newCompiler(importers: [.nodePackageImporter(rootDirURL)])
        let results = try await compiler.compile(string: "@use \"pkg:test\"", outputStyle: .compressed)
        XCTAssertEqual("a{b:true}", results.css)
    }
}
