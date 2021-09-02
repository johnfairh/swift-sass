//
//  TestFunction.swift
//  SassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@_spi(SassCompilerProvider) import Sass

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

    func testDynamicFunction() throws {
        let f1 = SassDynamicFunction(signature: "f()") { args in SassConstants.false }
        XCTAssertEqual("f()", f1.signature)
        let f1ID = f1.id
        XCTAssertEqual("DynamicFunction(\(f1ID) f())", f1.description)
        XCTAssertEqual(SassDynamicFunction.lookUp(id: f1ID), f1)

        let val: SassValue = f1
        XCTAssertNoThrow(try val.asDynamicFunction())
        XCTAssertThrowsError(try SassConstants.null.asDynamicFunction())

        let dict = [f1 as SassValue: true]
        XCTAssertTrue(dict[val]!)
    }
}
