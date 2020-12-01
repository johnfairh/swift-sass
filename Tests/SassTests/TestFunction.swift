//
//  TestFunction.swift
//  SassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import Sass

/// Compiler & dynamic functions, data-structure tests
class TestFunction: XCTestCase {
    func testCompilerFunction() throws {
        let f1 = SassCompilerFunction(id: 103)
        XCTAssertEqual(103, f1.id)
        XCTAssertEqual("CompilerFunction(103)", f1.description)

        let f2: SassValue = SassCompilerFunction(id: 104)
        XCTAssertNoThrow(try f2.asCompilerFunction())
        XCTAssertThrowsError(try SassConstants.null.asCompilerFunction())
        XCTAssertNotEqual(f1, f2)

        let f3: SassValue = SassCompilerFunction(id: 103)
        XCTAssertEqual(f3, f1)

        let dict = [f1 as SassValue: true]
        XCTAssertTrue(dict[f3]!)
        XCTAssertNil(dict[f2])


    }
}
