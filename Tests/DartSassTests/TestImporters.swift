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
    func testCompilerLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let compiler = try newCompiler(importers: [.loadPath(tmpDir)])
        let results = try compiler.compile(string: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // job loadpath works
    func testJobLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let compiler = try newCompiler()
        let results = try compiler.compile(string: usingSass, syntax: .sass,
                                           outputStyle: .compressed,
                                           importers: [.loadPath(tmpDir)])
        XCTAssertEqual(secondaryCssBlue, results.css)
        XCTAssertEqual(1, results.loadedURLs.count)
    }

    // job loadpath searched after compiler loadpath
    func testLoadPathOrder() throws {
        let tmpDirBlue = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let tmpDirRed = try createFileInNewDir(secondaryCssRed, filename: secondaryCssFilename)
        let compiler = try newCompiler(importers: [.loadPath(tmpDirRed)])
        let results = try compiler.compile(string: usingSass, syntax: .sass,
                                           outputStyle: .compressed,
                                           importers: [.loadPath(tmpDirBlue)])
        XCTAssertEqual(secondaryCssRed, results.css)
    }

    // nonsense in loadpath doesn't affect anyone (not even a warning!)
    func testNonsenseLoadPath() throws {
        let tmpDir = try createFileInNewDir(secondaryCssBlue, filename: secondaryCssFilename)
        let nonsenseDir = URL(fileURLWithPath: "/not/a/directory")
        let compiler = try newCompiler(importers: [.loadPath(nonsenseDir), .loadPath(tmpDir)])
        let results = try compiler.compile(string: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssBlue, results.css)
    }

    // implicit loadpath works
    func testImplicitLoadPath() throws {
        let tmpDir1 = try FileManager.default.createTemporaryDirectory()
        let tmpDir2 = try FileManager.default.createTemporaryDirectory()
        let filename = "imported.scss"
        try "a { a: 'dir1'; }".write(to: tmpDir1.appendingPathComponent(filename))
        try "a { a: 'dir2'; }".write(to: tmpDir2.appendingPathComponent(filename))

        try tmpDir1.withCurrentDirectory {
            let compiler = try newCompiler()
            try checkCompilerWorking(compiler) // make sure child process is actually started...
            try tmpDir2.withCurrentDirectory {
                let results = try compiler.compile(string: "@import 'imported';", outputStyle: .compressed)
                XCTAssertEqual(#"a{a:"dir2"}"#, results.css)
            }
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

        func canonicalize(ruleURL: String, fromImport: Bool) async throws -> URL? {
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
        var failedImportCount = 0

        func load(canonicalURL: URL) async throws -> ImporterResults {
            if let failNextImport = failNextImport {
                failedImportCount += 1
                throw Error(message: failNextImport)
            }
            return ImporterResults(css, syntax: .css, sourceMapURL: canonicalURL)
        }
    }

    // Goodpath.
    func testCustomImporter() throws {
        let importer = TestImporter(css: secondaryCssRed)
        let compiler = try newCompiler(importers: [.importer(importer)])
        let results = try compiler.compile(string: importingSass, syntax: .sass, outputStyle: .compressed)
        XCTAssertEqual(secondaryCssRed, results.css)
        XCTAssertEqual("test://secondary", results.loadedURLs.first!.absoluteString)
    }

    // Bad path harness
    func checkFaultyImporter(customize: (TestImporter) -> Void, check: (TestImporter, CompilerError) -> Void) throws {
        let importer = TestImporter(css: secondaryCssRed)
        customize(importer)
        let compiler = try newCompiler(importers: [.importer(importer)])
        do {
            let results = try compiler.compile(string: usingSass, syntax: .sass)
            XCTFail("Compiled something: \(results)")
        } catch let error as CompilerError {
            check(importer, error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Canon says nil (not recognized)
    func testImportNotFound() throws {
        try checkFaultyImporter(customize: { $0.claimRequest = false }) { i, e in
            XCTAssertEqual(1, i.unclaimedRequestCount)
            XCTAssertTrue(e.message.contains("Can't find stylesheet"))
        }
    }

    // Canon fails (ambiguous)
    func testImportCanonFails() throws {
        try checkFaultyImporter(customize: { $0.failNextCanon = "Objection" }) { i, e in
            XCTAssertEqual(i.failNextCanon, e.message)
            XCTAssertEqual(1, i.failedCanonCount)
        }
    }

    // load fails
    func testImportFails() throws {
        try checkFaultyImporter(customize: { $0.failNextImport = "Objection" }) { i, e in
            XCTAssertEqual(i.failNextImport, e.message)
            XCTAssertEqual(1, i.failedImportCount)
        }
    }

    // Async importer
    func testAsyncImporter() throws {
        let importer = HangingAsyncImporter()
        let compiler = try newCompiler(importers: [.importer(importer)])
        let results = try compiler.compile(string: "@import 'something';")
        XCTAssertEqual("", results.css)
    }

    // Importer for string source doc
    func testStringImporter() throws {
        let importer = TestImporter(css: secondaryCssRed)
        let compiler = try newCompiler()
        let results = try compiler.compile(string: "@import 'something';",
                                           url: URL(string: "test://vfs"),
                                           importer: .importer(importer),
                                           outputStyle: .compressed)
        XCTAssertEqual("a{color:red}", results.css)
        XCTAssertEqual(2, results.loadedURLs.count)
        let srcmap = try SourceMap(string: XCTUnwrap(results.sourceMap), checkMappings: true)
        XCTAssertEqual(1, srcmap.sources.count)
        XCTAssertEqual("test://vfs/something", srcmap.sources[0].url)
    }

    // fromImport flag
    func testFromImport() throws {
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

            func canonicalize(ruleURL: String, fromImport: Bool) async throws -> URL? {
                XCTAssertFalse(wasInvoked)
                wasInvoked = true
                XCTAssertEqual(expectFromImport, fromImport)
                return URL(string: "test://\(ruleURL)")
            }

            func load(canonicalURL: URL) async throws -> ImporterResults {
                ImporterResults("", syntax: .css, sourceMapURL: canonicalURL)
            }
        }
        let importer = FromImportTester()
        let compiler = try newCompiler(importers: [.importer(importer)])

        importer.expectNext(true)
        _ = try compiler.compile(string: "@import 'something'")
        importer.check()

        importer.expectNext(false)
        _ = try compiler.compile(string: "@use 'something'")
        importer.check()
    }

    // multiple imports, loaded
    func testMultipleLoadedURLs() throws {
        let importer = TestImporter(css: "a { b: 'c' }")
        let compiler = try newCompiler(importers: [.importer(importer)])
        let rootURL = URL(string: "original://file")!
        let scss = """
                   @import 'first';
                   @import 'second';
                   div { b: 'c' }
                   """
        let results = try compiler.compile(string: scss, syntax: .scss, url: rootURL)
        let map = try SourceMap(string: XCTUnwrap(results.sourceMap))
        XCTAssertEqual(3, map.sources.count)
        XCTAssertEqual(3, results.loadedURLs.count)

        func s(_ urls: [URL]) -> [URL] {
            urls.sorted(by: { $0.absoluteString < $1.absoluteString})
        }
        let expected = s([rootURL, URL(string: "test://first")!, URL(string: "test://second")!])
        XCTAssertEqual(expected, s(results.loadedURLs))
        XCTAssertEqual(expected, s(map.sources.map { URL(string: $0.url)! }))
    }

    // MARK: Custom filesystem importers

    class FilesysImporter: FilesystemImporter, @unchecked Sendable {
        let directoryURL: URL
        private(set) var resolveCount: Int
        var nextUnknown: Bool
        var nextFail: Bool
        var expectImport: Bool

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

        func resolve(ruleURL: String, fromImport: Bool) async throws -> URL? {
            resolveCount += 1
            XCTAssertEqual(expectImport, fromImport, ruleURL)
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

    func testFilesystemNormal() throws {
        let dir = try FileManager.default.createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let imp = FilesysImporter(dir)

        let fileURL = dir.appendingPathComponent("test.scss")

        try "a { b: true }".write(to: fileURL)
        let compiler = try newCompiler(importers: [.filesystemImporter(imp)])

        // Goodpath, import
        imp.expectImport = true
        let results = try compiler.compile(string: "@import 'test';", outputStyle: .compressed)
        XCTAssertEqual(1, imp.resolveCount)
        XCTAssertEqual(fileURL, results.loadedURLs[0])
        XCTAssertEqual("a{b:true}", results.css)

        // Goodpath, use
        imp.expectImport = false
        let results2 = try compiler.compile(string: "@use 'test';", outputStyle: .compressed)
        XCTAssertEqual(2, imp.resolveCount)
        XCTAssertEqual("a{b:true}", results2.css)

        // Notfound
        imp.nextUnknown = true
        do {
            let res = try compiler.compile(string: "@use 'test';", outputStyle: .compressed)
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
            let res = try compiler.compile(string: "@use 'test';", outputStyle: .compressed)
            XCTFail("Managed to resolve @use 'test': \(res)")
        } catch let error as CompilerError {
            XCTAssertTrue(error.message.contains("Programmed fail"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(4, imp.resolveCount)
    }
}
