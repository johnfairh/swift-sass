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
        let vers = Versions(protocolVersionString: "1.0.3")
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

    func testVersionReport() throws {
        try asyncTest(asyncTestVersionReport)
    }

    func asyncTestVersionReport() async throws {
        let expectedPackage = "1.0.0-beta.12"
        let expectedCompiler = "1.42.1"
        let compiler = try newCompiler()
        let version = try await XCTUnwrapA(await compiler.compilerVersion)
        XCTAssertEqual(expectedCompiler, version)
        let name = try await XCTUnwrapA(await compiler.compilerName)
        XCTAssertEqual("Dart Sass", name)
        let package = try await XCTUnwrapA(await compiler.compilerPackageVersion)
        XCTAssertEqual(expectedPackage, package)
    }

    func testBadVersionReport() throws {
        try asyncTest(asyncTestBadVersionReport)
    }

    func asyncTestBadVersionReport() async throws {
        let compiler = try newCompiler()
        compiler.versionsResponder = TestVersionsResponder(Versions(protocolVersionString: "huh"))
        let version = await compiler.compilerVersion
        XCTAssertNil(version)
    }

    struct HangingVersionsResponder: VersionsResponder {
        func provideVersions(eventLoop: EventLoop, msg: Sass_EmbeddedProtocol_InboundMessage, callback: @escaping (Sass_EmbeddedProtocol_OutboundMessage) -> Void) {
            // drop it
        }
    }

    func testStuckVersionReport() throws {
        try asyncTest(asyncTestStuckVersionReport)
    }

    func asyncTestStuckVersionReport() async throws {
        let compiler = try newBadCompiler(timeout: 1)
        compiler.versionsResponder = HangingVersionsResponder()
        let version = await compiler.compilerVersion
        XCTAssertNil(version)
    }

    struct CorruptVersionsResponder: VersionsResponder {
        func provideVersions(eventLoop: EventLoop,
                             msg: Sass_EmbeddedProtocol_InboundMessage,
                             callback: @escaping (Sass_EmbeddedProtocol_OutboundMessage) -> Void) {
            eventLoop.scheduleTask(in: .milliseconds(100)) {
                callback(.with {
                    $0.importRequest = .with {
                        $0.compilationID = msg.versionRequest.id
                    }
                })
            }
        }
    }

    func testCorruptVersionReport() throws {
        try asyncTest(asyncTestCorruptVersionReport)
    }

    func asyncTestCorruptVersionReport() async throws {
        let compiler = try newCompiler()
        compiler.versionsResponder = CorruptVersionsResponder()
        let version = await compiler.compilerVersion
        XCTAssertNil(version)
    }
}
