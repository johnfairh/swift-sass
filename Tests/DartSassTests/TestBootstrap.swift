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

        let results = try compiler.compile(sourceText: "")
        XCTAssertEqual("", results.css)
        XCTAssertNil(results.sourceMap)
    }
}
