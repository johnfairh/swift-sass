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
                  compilerVersionString: "2.3.0",
                  compilerName: "test")
    }
}

/// Tests for version checking
class TestVersions: DartSassTestCase {
    func testCreation() {
        let vers = Versions(protocolVersionString: "3.1.1")
        XCTAssertEqual("3", vers.protocolVersion.major)
        XCTAssertEqual("1", vers.protocolVersion.patch)
        XCTAssertNoThrow(try vers.check())
    }

    func testBadVersions() throws {
        let notSemver = Versions(protocolVersionString: "version?")
        XCTAssertThrowsError(try notSemver.check())

        let tooLow = Versions(protocolVersionString: "1.0.0-beta.1")
        XCTAssertThrowsError(try tooLow.check())

        let tooHigh = Versions(protocolVersionString: "4.1")
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
        XCTAssertEqual("dart-sass", name)
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
        func provideVersions(msg: OutboundMessage) async -> InboundMessage? {
            nil // drop it
        }
    }

    func testInterruptedVersionRequest() async throws {
        await setSuspend(at: .sendVersionRequest)
        let compiler = try newCompiler()
        await testSuspend?.waitUntilSuspended(at: .sendVersionRequest)
        let pid = await compiler.compilerProcessIdentifier!
        stopProcess(pid: pid)
        await compiler.waitForQuiescing()
        await compiler.handleError(TestCaseError())
        await testSuspend?.resume(from: .sendVersionRequest)
        await compiler.waitForRunning()
        await compiler.assertStartCount(2)
        try await checkCompilerWorking(compiler)
    }

    func testStuckVersionReport() async throws {
        let compiler = try await newBadCompiler(timeout: 1)
        await compiler.setVersionsResponder(HangingVersionsResponder())
        let version = await compiler.compilerVersion
        XCTAssertNil(version)
    }

    struct CorruptVersionsResponder: VersionsResponder {
        func provideVersions(msg: OutboundMessage) async -> InboundMessage? {
            .init(msg.versionRequest.id, .with {
                $0.importRequest = .init()
            })
        }
    }

    func testCorruptVersionReport() async throws {
        let compiler = try newCompiler()
        await compiler.setVersionsResponder(CorruptVersionsResponder())
        let version = await compiler.compilerVersion
        XCTAssertNil(version)
    }
}
