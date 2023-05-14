//
//  TestUtils.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import NIO
import XCTest
import Foundation
@testable import DartSass

class DartSassTestCase: XCTestCase {

    var eventLoopGroup: EventLoopGroup! = nil

    typealias CompilerTask = Task<Void, any Error>

    var compilersToShutdown: [Compiler] = []

    override func setUpWithError() throws {
        XCTAssertNil(eventLoopGroup)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        Compiler.logger.logLevel = .debug
    }

    override func tearDown() async throws {
        for compiler in compilersToShutdown {
            await compiler.shutdownGracefully()
        }
        compilersToShutdown = []
        try await eventLoopGroup.shutdownGracefully()
        eventLoopGroup = nil
    }

    func newCompiler(importers: [ImportResolver] = []) throws -> Compiler {
        try newCompiler(importers: importers, functions: [:])
    }

    func newCompiler(importers: [ImportResolver] = [], functions: SassAsyncFunctionMap) throws -> Compiler {
        let c = try Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
                             importers: importers,
                             functions: functions)
        compilersToShutdown.append(c)
        return c
    }

    func newBadCompiler(timeout: Int = 1) async throws -> Compiler {
        let c = Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
                         embeddedCompilerFileURL: URL(fileURLWithPath: "/usr/bin/tail"),
                         timeout: timeout)
        await c.setVersionsResponder(TestVersionsResponder())
        compilersToShutdown.append(c)
        return c
    }

    // Helper to trigger & validate a protocol error
    func checkProtocolError(_ compiler: Compiler, _ text: String? = nil, protocolNotLifecycle: Bool = true) async {
        do {
            let results = try await compiler.compile(string: "")
            XCTFail("Managed to compile with compiler that should have failed: \(results)")
        } catch {
            if (error is ProtocolError && protocolNotLifecycle) ||
                (error is LifecycleError && !protocolNotLifecycle) {
                if let text {
                    let errText = String(describing: error)
                    XCTAssertTrue(errText.contains(text))
                }
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // Helper to check a compiler is working normally
    func checkCompilerWorking(_ compiler: Compiler) async throws {
        let results = try await compiler.compile(string: "")
        XCTAssertEqual("", results.css)
    }
}

extension String {
    func write(to url: URL) throws {
        try write(toFile: url.path, atomically: false, encoding: .utf8)
    }
}

extension FileManager {
    func createTempFile(filename: String, contents: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: url)
        return url
    }

    /// Create a new empty temporary directory.  Caller must delete.
    func createTemporaryDirectory(inDirectory directory: URL? = nil, name: String? = nil) throws -> URL {
        let directoryName = name ?? UUID().uuidString
        let parentDirectoryURL = directory ?? temporaryDirectory
        let directoryURL = parentDirectoryURL.appendingPathComponent(directoryName)
        try createDirectory(at: directoryURL, withIntermediateDirectories: false)
        return directoryURL
    }

    public static func preservingCurrentDirectory<T>(_ code: () throws -> T) rethrows -> T {
        let fileManager = FileManager.default
        let cwd = fileManager.currentDirectoryPath
        defer {
            let rc = fileManager.changeCurrentDirectoryPath(cwd)
            precondition(rc)
        }
        return try code()
    }
}

extension URL {
    public func withCurrentDirectory<T>(code: () throws -> T) throws -> T {
        try FileManager.preservingCurrentDirectory {
            FileManager.default.changeCurrentDirectoryPath(path)
            return try code()
        }
    }
}

/// An async importer that can be stopped in `load`.
/// Accepts all `import` URLs and returns empty documents.
final class HangingAsyncImporter: Importer {

    final class State: @unchecked Sendable {
        var onLoadHang: (() async -> Void)?
        init() { onLoadHang = nil }
    }

    let state = State()

    init() {
    }

    func canonicalize(ruleURL: String, fromImport: Bool) async throws -> URL? {
        URL(string: "custom://\(ruleURL)")
    }

    func load(canonicalURL: URL) async throws -> ImporterResults? {
        if let onLoadHang = state.onLoadHang {
            await onLoadHang()
            state.onLoadHang = nil
        }
        return ImporterResults("")
    }
}

struct TestVersionsResponder: VersionsResponder {
    static let defaultVersions =
        Versions(protocolVersionString: Versions.minProtocolVersion.toString(),
                 packageVersionString: "0.0.1",
                 compilerVersionString: "0.0.1",
                 compilerName: "ProbablyDartSass")

    private let versions: Versions
    init(_ versions: Versions = Self.defaultVersions) {
        self.versions = versions
    }

    func provideVersions(msg: Sass_EmbeddedProtocol_InboundMessage) async -> Sass_EmbeddedProtocol_OutboundMessage {
        try? await Task.sleep(for: .milliseconds(100))
        return .with { $0.versionResponse = .init(versions, id: msg.versionRequest.id) }
    }
}

extension XCTest {
    func XCTAssertThrowsErrorA<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }

    func XCTAssertNoThrowA<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail(message(), file: file, line: line)
        }
    }

    func XCTUnwrapA<T>(
        _ expression: @autoclosure () async throws -> T?,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> T {
        guard let t = try await expression() else {
            XCTFail("Unexpectedly nil")
            throw AsyncUnwrapError()
        }
        return t
    }

    func XCTAssertEqualA<T>(
        _ expression1: @autoclosure () throws -> T,
        _ expression2: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async rethrows where T : Equatable {
        let e2 = try await expression2()
        XCTAssertEqual(try expression1(), e2, message(), file: file, line: line)
    }
}

struct AsyncUnwrapError: Error {}
