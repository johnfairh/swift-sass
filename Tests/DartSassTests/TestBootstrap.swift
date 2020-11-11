//
//  DartSassTests.swift
//  DartSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

import XCTest
@testable import DartSass

final class DartSassTests: XCTestCase {
    func testBootstrap() throws {
        let compiler = try Compiler(embeddedDartSass: TestUtils.dartSassEmbeddedURL)
        compiler.child.process.terminate()
        let results = compiler.child.await()
        XCTAssertEqual(15, results.terminationStatus)
    }
}
