//
//  TestVersions.swift
//  SassEmbeddedTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import SassEmbedded

extension Versions {
    init(protocolVersionString: String) {
        self.init(protocolVersionString: protocolVersionString,
                  packageVersionString: "1.0.0",
                  compilerVersionString: "2.0.0",
                  compilerName: "test")
    }
}

/// Tests for version checking
class TestVersions: SassEmbeddedTestCase {
    func testCreation() {
        let vers = Versions(protocolVersionString: "1.0.3", packageVersionString: "2.0.0", compilerVersionString: "3.0.0", compilerName: "test")
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
        let compiler = try newCompiler()
        let version = try XCTUnwrap(compiler.compilerVersion.wait())
        XCTAssertEqual("0.0.1", version)
        let name = try XCTUnwrap(compiler.compilerName.wait())
        XCTAssertEqual("ProbablyDartSass", name)
    }

    func testBadVersionReport() throws {
        let normalFakeVersions = Versions.fakeVersions
        defer { Versions.fakeVersions = normalFakeVersions }
        Versions.fakeVersions = Versions(protocolVersionString: "huh")
        let compiler = try newCompiler()
        let version = try compiler.compilerVersion.wait()
        XCTAssertNil(version)
    }
}
