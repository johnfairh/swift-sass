//
//  TestUtils.swift
//  SassEmbeddedTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import NIO
import XCTest
import Foundation
@testable import SassEmbedded

class SassEmbeddedTestCase: XCTestCase {

    var eventLoopGroup: EventLoopGroup! = nil

    var compilersToShutdown: [Compiler] = []

    override func setUpWithError() throws {
        XCTAssertNil(eventLoopGroup)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        Compiler.logger.logLevel = .debug
    }

    override func tearDownWithError() throws {
        try compilersToShutdown.forEach {
            try $0.syncShutdownGracefully()
        }
        compilersToShutdown = []
        try eventLoopGroup.syncShutdownGracefully()
        eventLoopGroup = nil
    }

    static var unitTestDirURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    static var dartSassEmbeddedDirURL: URL {
        let rootURL = unitTestDirURL.appendingPathComponent("dart-sass-embedded")
        #if os(Linux)
        let platformURL = rootURL.appendingPathComponent("linux")
        #else
        let platformURL = rootURL.appendingPathComponent("macos")
        #endif
        return platformURL.appendingPathComponent("sass_embedded")
    }

    static var dartSassEmbeddedURL: URL {
        dartSassEmbeddedDirURL.appendingPathComponent("dart-sass-embedded")
    }

    func newCompiler(importers: [ImportResolver] = [], functions: SassFunctionMap = [:]) throws -> Compiler {
        return try newCompiler(importers: importers, asyncFunctions: SassAsyncFunctionMap(functions))
    }

    func newCompiler(importers: [ImportResolver] = [], asyncFunctions: SassAsyncFunctionMap) throws -> Compiler {
        let c = Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
                         embeddedCompilerURL: SassEmbeddedTestCase.dartSassEmbeddedURL,
                         importers: importers,
                         functions: asyncFunctions)
        compilersToShutdown.append(c)
        return c
    }

    func newBadCompiler(timeout: Int = 1) throws -> Compiler {
        let c = Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
                         embeddedCompilerURL: URL(fileURLWithPath: "/usr/bin/tail"),
                         timeout: timeout)
        compilersToShutdown.append(c)
        return c
    }

    // Helper to trigger & validate a protocol error
    func checkProtocolError(_ compiler: Compiler, _ text: String? = nil, protocolNotLifecycle: Bool = true) {
        do {
            let results = try compiler.compile(text: "")
            XCTFail("Managed to compile with compiler that should have failed: \(results)")
        } catch {
            if (error is ProtocolError && protocolNotLifecycle) ||
                (error is LifecycleError && !protocolNotLifecycle) {
                if let text = text {
                    let errText = String(describing: error)
                    XCTAssertTrue(errText.contains(text))
                }
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // Helper to check a compiler is working normally
    func checkCompilerWorking(_ compiler: Compiler) throws {
        let results = try compiler.compile(text: "")
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
}

/// An async importer that can be stopped in `load`.
/// Accepts all `import` URLs and returns empty documents.
final class HangingAsyncImporter: AsyncImporter {
    func canonicalize(eventLoop: EventLoop, importURL: String) -> EventLoopFuture<URL?> {
        return eventLoop.makeSucceededFuture(URL(string: "custom://\(importURL)"))
    }

    var hangNextLoad: Bool { hangPromise != nil }
    private var hangPromise: EventLoopPromise<Void>? = nil
    var loadPromise: EventLoopPromise<ImporterResults>? = nil

    func hangLoad(eventLoop: EventLoop) -> EventLoopFuture<Void> {
        hangPromise = eventLoop.makePromise(of: Void.self)
        return hangPromise!.futureResult
    }

    func resumeLoad() throws {
        let promise = try XCTUnwrap(loadPromise)
        promise.succeed(.init(""))
        loadPromise = nil
    }

    func load(eventLoop: EventLoop, canonicalURL: URL) -> EventLoopFuture<ImporterResults> {
        let promise = eventLoop.makePromise(of: ImporterResults.self)
        if hangNextLoad {
            loadPromise = promise
            hangPromise?.succeed(())
            hangPromise = nil
        } else {
            promise.succeed(.init(""))
        }
        return promise.futureResult
    }
}
