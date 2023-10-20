//
//  TestFunction.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@_spi(SassCompilerProvider) import Sass

/// Compiler & dynamic functions, data-structure tests
/// And mixins too because they are so silly
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

    func testMixin() throws {
        let m1 = SassMixin(id: 204)
        XCTAssertEqual(204, m1.id)
        XCTAssertEqual("Mixin(204)", m1.description)

        XCTAssertNoThrow(try m1.asMixin())
        XCTAssertThrowsError(try SassConstants.true.asMixin())

        let m2 = SassMixin(id: 205)
        XCTAssertNotEqual(m1, m2)

        let m3 = SassMixin(id: 204)
        XCTAssertEqual(m1, m3)

        let dict = [m1 as SassValue: true]
        XCTAssertTrue(dict[m3]!)
        XCTAssertNil(dict[m2])
    }
}
