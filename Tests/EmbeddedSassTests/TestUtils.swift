//
//  TestUtils.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import NIO
import XCTest
import Foundation
import EmbeddedSass

class EmbeddedSassTestCase: XCTestCase {

    var eventLoopGroup: EventLoopGroup! = nil

    override func setUpWithError() throws {
        XCTAssertNil(eventLoopGroup)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override func tearDownWithError() throws {
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
        Compiler.logger.logLevel = .debug
        let c = try Compiler(eventLoopGroup: eventLoopGroup,
                             embeddedCompilerURL: EmbeddedSassTestCase.dartSassEmbeddedURL,
                             importers: importers,
                             functions: functions)
        return c
    }

    func newBadCompiler(timeout: Int = 1) throws -> Compiler {
        Compiler.logger.logLevel = .debug
        let c = try Compiler(eventLoopGroup: eventLoopGroup,
                             embeddedCompilerURL: URL(fileURLWithPath: "/usr/bin/tail"),
                             timeout: timeout)
        return c
    }

    // Helper to trigger & validate a protocol error
    func checkProtocolError(_ compiler: Compiler, _ text: String? = nil) {
        do {
            let results = try compiler.compile(text: "")
            XCTFail("Managed to compile with compiler that should have failed: \(results)")
        } catch let error as ProtocolError {
            print(error)
            if let text = text {
                XCTAssertTrue(error.description.contains(text))
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
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
