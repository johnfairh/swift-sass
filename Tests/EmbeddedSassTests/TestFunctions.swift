//
//  TestFunctions.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import EmbeddedSass

///
/// Tests for custom functions.
///  - SassTests covers the base `SassValue` hierarchy.
///  - We don't need to test the compiler's implementation of this flow, just our side.
class TestFunctions: EmbeddedSassTestCase {

    // (String) values go back and forth

    let quoteStringFunction: SassFunctionMap = [
        "myQuoteString($param)" : { args in
            let str = try args[0].asString()
            return SassString(str.string, isQuoted: true)
        }
    ]

    func testEcho() throws {
        let compiler = try newCompiler(functions: quoteStringFunction)

        try [#"fish"#, #""fish""#].forEach {
            let results = try compiler.compile(text: "a { a: myQuoteString(\($0)) }", outputStyle: .compressed)
            XCTAssertEqual(#"a{a:"fish"}"#, results.css)
        }
    }

    // Errors reported

    let errorFunction: SassFunctionMap = [
        "badFunction($param)" : { args in
            let bool = try args[0].asBool()
            XCTFail("Managed to get a bool")
            return SassConstants.null
        }
    ]

    func testError() throws {
        let compiler = try newCompiler(functions: errorFunction)

        do {
            let results = try compiler.compile(text: "$data: badFunction('22');")
            XCTFail("Managed to compile nonsense: \(results)")
        } catch let error as CompilerError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Local func overrides global

    let globalOverrideFunction: SassFunctionMap = [
        "ofunc($param)" : { _ in
            return SassString("bucket")
        }
    ]

    let localOverrideFunction: SassFunctionMap = [
        "ofunc()" : { _ in
            return SassString("goat")
        }
    ]

    func testOverride() throws {
        let compiler = try newCompiler(functions: globalOverrideFunction)

        let results = try compiler.compile(text: "a { a: ofunc() }", outputStyle: .compressed, functions: localOverrideFunction)
        XCTAssertEqual(#"a{a:"goat"}"#, results.css)
    }

    // Corner error cases in Value conversion

    func testBadValueConversion() {
        let badValue1 = Sass_EmbeddedProtocol_Value()
        XCTAssertThrowsError(try badValue1.asSassValue())
    }

    /// SassList conversion
    func testSassListConversion() throws {
        // Round-trip
        let list = SassList([SassString("one")], separator: .slash)
        let value = Sass_EmbeddedProtocol_Value(list)
        let listBack = try value.asSassValue()
        XCTAssertEqual(list, listBack)

        // Tedious enum matching
        let separators: [(Sass_EmbeddedProtocol_Value.List.Separator,
                          SassList.Separator)] = [
                            (.comma, .comma),
                            (.slash, .slash),
                            (.space, .space),
                            (.undecided, .undecided)]
        try separators.forEach { pb, sw in
            XCTAssertEqual(pb, .init(sw))
            XCTAssertEqual(sw, try .init(pb))
        }

        // And the reason we have our own enum
        XCTAssertThrowsError(try SassList.Separator(.UNRECOGNIZED(1)))
    }

    /// SassConstant conversion
    func testSassConstantConversion() throws {
        try [SassConstants.true,
             SassConstants.false,
             SassConstants.null].forEach { sassVal in
            let pbVal = Sass_EmbeddedProtocol_Value(sassVal)
            let backVal = try pbVal.asSassValue()
            XCTAssertEqual(sassVal, backVal)
        }

        // Bad singleton value
        var value = Sass_EmbeddedProtocol_Value()
        value.singleton = .UNRECOGNIZED(2)
        XCTAssertThrowsError(try value.asSassValue())
    }

    /// SassMap conversion
    func testSassMapConversion() throws {
        let map = SassMap(uniqueKeysWithValues: [
            (SassConstants.true, SassString("str1")),
            (SassConstants.false, SassString("str2"))
        ])
        let pbVal = Sass_EmbeddedProtocol_Value(map)
        let backMap = try pbVal.asSassValue()
        XCTAssertEqual(map, backMap)

        // Dodgy map from the compiler
        var badPbVal = Sass_EmbeddedProtocol_Value()
        badPbVal.map = .with {
            $0.entries = [
                .with { ent in
                    ent.key = .init(SassConstants.true)
                    ent.value = .init(SassConstants.null)
                },
                .with { ent in
                    ent.key = .init(SassConstants.true)
                    ent.value = .init(SassConstants.null)
                }
            ]
        }
        XCTAssertThrowsError(try badPbVal.asSassValue())
    }

    /// SassNumber conversion
    func testSassNumberConversion() throws {
        let num = SassNumber(Double.pi)
        let pbVal = Sass_EmbeddedProtocol_Value(num)
        let backNum = try pbVal.asSassValue()
        XCTAssertEqual(num, backNum)

        let num2 = try SassNumber(76, numeratorUnits: ["trombone"], denominatorUnits: ["s"])
        let pbVal2 = Sass_EmbeddedProtocol_Value(num2)
        let backNum2 = try pbVal2.asSassValue()
        XCTAssertEqual(num2, backNum2)
    }

    /// SassColor conversion
    func testSassColorConversion() throws {
        let rgb = try SassColor(red: 20, green: 40, blue: 60, alpha: 0.0)
        let rgbVal = Sass_EmbeddedProtocol_Value(rgb)
        let backRgb = try rgbVal.asSassValue().asColor()
        XCTAssertTrue(backRgb._prefersRgb)
        XCTAssertEqual(rgb, backRgb)

        let hsl = try SassColor(hue: 40, saturation: 66, lightness: 22, alpha: 1.0)
        let hslVal = Sass_EmbeddedProtocol_Value(hsl)
        let backHsl = try hslVal.asSassValue().asColor()
        XCTAssertFalse(backHsl._prefersRgb)
        XCTAssertEqual(hsl, backHsl)
    }

    /// Compiler functions
    func testSassCompilerFunctionConversion() throws {
        let f1 = SassCompilerFunction(id: 100)
        let fVal = Sass_EmbeddedProtocol_Value(f1)
        let backF = try fVal.asSassValue()
        XCTAssertEqual(f1, backF)
    }

    func testSassCompilerFunction() throws {

        let echoFunc: SassFunction = { args in
            XCTAssertEqual(1, args.count)
            let funcVal = try args[0].asCompilerFunction()
            return funcVal
        }

        let scss = """
        @use "sass:meta";

        @function something() {
          @return "something";
        }

        @function something_else() {
          $s_fn: meta.get-function("something");
          $h_fn: hostEcho($s_fn);
          @return meta.call($h_fn);
        }

        a {
          b: something_else();
        }
        """

        let compiler = try newCompiler(functions: [
            "hostEcho($param)" : echoFunc
        ])
        let results = try compiler.compile(text: scss, outputStyle: .compressed)
        XCTAssertEqual(#"a{b:"something"}"#, results.css)
    }

    /// Dynamic host functions
    func testSassDynamicFunctionConversion() throws {
        let f1 = SassDynamicFunction(signature: "f()") { _ in SassConstants.false }
        let fVal = Sass_EmbeddedProtocol_Value(f1)
        XCTAssertThrowsError(try fVal.asSassValue())
        let hFunc = fVal.hostFunction
        XCTAssertEqual("f()", hFunc.signature)
        XCTAssertEqual(f1.id, hFunc.id)
    }

    func testSassDynamicFunction() throws {
        // A curried addition function!
        let adderMaker: SassFunction = { args in
            let lhsOp = try args[0].asNumber()
            return SassDynamicFunction(signature: "addN($n)") { args in
                let rhsOp = try args[0].asNumber()
                return SassNumber(lhsOp.double + rhsOp.double)
            }
        }

        let scss = """
        @use "sass:meta";

        @function curriedAdd($op1, $op2) {
          $hfn: makeAdder($op1);
          @return meta.call($hfn, $op2);
        }

        a {
          b: curriedAdd(4, 5);
        }
        """

        let compiler = try newCompiler(functions: [
            "makeAdder($op1)" : adderMaker
        ])
        let results = try compiler.compile(text: scss, outputStyle: .compressed)
        XCTAssertEqual(#"a{b:9}"#, results.css)

        // what a monstrosity
    }

    let slowEchoFunction: SassAsyncFunctionMap = [
        "slowEcho($param)" : { eventLoop, args in
            eventLoop.scheduleTask(in: .seconds(1)) { () -> SassValue in
                let str = try args[0].asString()
                return str
            }.futureResult
        }
    ]

    func testAsyncHostFunction() throws {
        let compiler = try newCompiler(asyncFunctions: slowEchoFunction)
        let results = try compiler.compile(text: "a { a: slowEcho('fish') }", outputStyle: .compressed)
        XCTAssertEqual(#"a{a:"fish"}"#, results.css)
    }

    func testAsyncDynamicFunction() throws {
        let fishMakerMaker: SassFunction = { args in
            return SassAsyncDynamicFunction(signature: "myFish()") { eventLoop, args in
                eventLoop.submit {
                    SassString("plaice")
                }
            }
        }

        let scss = """
        @use "sass:meta";

        a {
          b: meta.call(getFishMaker());
        }
        """

        let compiler = try newCompiler(functions: [
            "getFishMaker()" : fishMakerMaker
        ])
        let results = try compiler.compile(text: scss, outputStyle: .compressed)
        XCTAssertEqual(#"a{b:"plaice"}"#, results.css)

    }
}
