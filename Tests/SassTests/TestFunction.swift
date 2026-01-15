//
//  TestFunction.swift
//  SassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Testing
@_spi(SassCompilerProvider) import Sass

/// Compiler & dynamic functions, data-structure tests
/// And mixins too because they are so silly
struct TestFunction {
    @Test
    func testCompilerFunction() {
        let f1 = SassCompilerFunction(id: 103)
        #expect(103 == f1.id)
        #expect("CompilerFunction(103)" == f1.description)

        let f2: SassValue = SassCompilerFunction(id: 104)
        do { _ = try f2.asCompilerFunction() } catch { Issue.record("asCompilerFunction threw unexpectedly: \(error)") }
        #expect(throws: Error.self) { _ = try SassConstants.null.asCompilerFunction() }
        #expect(f1 != f2)

        let f3: SassValue = SassCompilerFunction(id: 103)
        #expect(f3 == f1)

        let dict = [f1 as SassValue: true]
        #expect(dict[f3] == true)
        #expect(dict[f2] == nil)
    }

    @Test
    func testDynamicFunction() {
        let f1 = SassDynamicFunction(signature: "f()") { args in SassConstants.false }
        #expect("f()" == f1.signature)
        let f1ID = f1.id
        #expect("DynamicFunction(\(f1ID) f())" == f1.description)
        #expect(SassDynamicFunction.lookUp(id: f1ID) == f1)

        let val: SassValue = f1
        do { _ = try val.asDynamicFunction() } catch { Issue.record("asDynamicFunction threw unexpectedly: \(error)") }
        #expect(throws: Error.self) { _ = try SassConstants.null.asDynamicFunction() }

        let dict = [f1 as SassValue: true]
        #expect(dict[val] == true)
    }

    @Test
    func testMixin() {
        let m1 = SassMixin(id: 204)
        #expect(204 == m1.id)
        #expect("Mixin(204)" == m1.description)

        do { _ = try m1.asMixin() } catch { Issue.record("asMixin threw unexpectedly: \(error)") }
        #expect(throws: Error.self) { _ = try SassConstants.true.asMixin() }

        let m2 = SassMixin(id: 205)
        #expect(m1 != m2)

        let m3 = SassMixin(id: 204)
        #expect(m1 == m3)

        let dict = [m1 as SassValue: true]
        #expect(dict[m3] == true)
        #expect(dict[m2] == nil)
    }
}
