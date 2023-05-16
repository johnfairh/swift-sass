//
//  TestVersions.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIO
import XCTest
@testable import DartSass

extension Versions {
    init(protocolVersionString: String) {
        self.init(protocolVersionString: protocolVersionString,
                  packageVersionString: "1.0.0",
                  compilerVersionString: "2.0.0",
                  compilerName: "test")
    }
}

/// Tests for version checking
class TestVersions: DartSassTestCase {
    func testCreation() {
        let vers = Versions(protocolVersionString: "1.1.3")
        XCTAssertEqual("1", vers.protocolVersion.major)
        XCTAssertEqual("3", vers.protocolVersion.patch)
        XCTAssertNoThrow(try vers.check())
    }

    func testBadVersions() throws {
        let notSemver = Versions(protocolVersionString: "version?")
        XCTAssertThrowsError(try notSemver.check())

        let tooLow = Versions(protocolVersionString: "1.0.0-beta.1")
        XCTAssertThrowsError(try tooLow.check())

        let tooHigh = Versions(protocolVersionString: "2.1")
        XCTAssertThrowsError(try tooHigh.check())
    }

    func readSassVersion() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VERSION_DART_SASS")
        return try String(contentsOf: url).trimmingCharacters(in: .newlines)
    }

    func testVersionReport() async throws {
        let expectedVersion = try readSassVersion()
        let compiler = try newCompiler()
        let version = try await XCTUnwrapA(await compiler.compilerVersion)
        XCTAssertEqual(expectedVersion, version)
        let name = try await XCTUnwrapA(await compiler.compilerName)
        XCTAssertEqual("Dart Sass", name)
        let package = try await XCTUnwrapA(await compiler.compilerPackageVersion)
        XCTAssertEqual(expectedVersion, package)
    }

    func testBadVersionReport() async throws {
        let compiler = try newCompiler()
        await compiler.setVersionsResponder(TestVersionsResponder(Versions(protocolVersionString: "huh")))
        let version = await compiler.compilerVersion
        XCTAssertNil(version)
    }

    struct HangingVersionsResponder: VersionsResponder {
        func provideVersions(msg: DartSass.Sass_EmbeddedProtocol_InboundMessage) async -> DartSass.Sass_EmbeddedProtocol_OutboundMessage? {
            nil // drop it
        }
    }

    func testStuckVersionReport() async throws {
        let compiler = try await newBadCompiler(timeout: 1)
        await compiler.setVersionsResponder(HangingVersionsResponder())
        let version = await compiler.compilerVersion
        XCTAssertNil(version)
    }

    struct CorruptVersionsResponder: VersionsResponder {
        func provideVersions(msg: DartSass.Sass_EmbeddedProtocol_InboundMessage) async -> DartSass.Sass_EmbeddedProtocol_OutboundMessage? {
//            try? await Task.sleep(for: .milliseconds(100)) // not sure why this was here
            return .with {
                    $0.importRequest = .with {
                        $0.compilationID = msg.versionRequest.id
                    }
                }
        }
    }

    func testCorruptVersionReport() async throws {
        let compiler = try newCompiler()
        await compiler.setVersionsResponder(CorruptVersionsResponder())
        let version = await compiler.compilerVersion
        XCTAssertNil(version)
    }
}
