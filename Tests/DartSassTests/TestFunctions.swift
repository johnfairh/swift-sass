//
//  TestFunctions.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
@testable import DartSass
@_spi(SassCompilerProvider) import Sass

///
/// Tests for custom functions.
///  - SassTests covers the base `SassValue` hierarchy.
///  - We don't need to test the compiler's implementation of this flow, just our side.
class TestFunctions: DartSassTestCase {

    // (String) values go back and forth

    let quoteStringFunction: SassFunctionMap = [
        "myQuoteString($param)" : { args in
            let str = try args[0].asString()
            return SassString(str.string, isQuoted: true)
        }
    ]

    func testEcho() async throws {
        let compiler = try newCompiler(functions: quoteStringFunction)

        for str in [#"fish"#, #""fish""#] {
            let results = try await compiler.compile(string: "a { a: myQuoteString(\(str)) }", outputStyle: .compressed)
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

    func testError() async throws {
        let compiler = try newCompiler(functions: errorFunction)

        do {
            let results = try await compiler.compile(string: "$data: badFunction('22');")
            XCTFail("Managed to compile nonsense: \(results)")
        } catch let error as CompilerError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Function syntax fails compile not compiler

    func testBadFunctionDecl() async throws {
        let badFunction: SassFunctionMap = [
            "" : { _ in SassConstants.null }
        ]

        let compiler = try newCompiler(functions: badFunction)
        // hmm should we do a nul compile to check these function defs?

        do {
            let results = try await compiler.compile(string: "")
            XCTFail("Managed to compile with bad function nonsense: \(results)")
        } catch let error as CompilerError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Local func overrides global

    let globalOverrideFunction: SassFunctionMap = [
        "ofunc($param)" : { _ in
            SassString("bucket")
        }
    ]

    let localOverrideFunction: SassFunctionMap = [
        "ofunc()" : { _ in
            SassString("goat")
        }
    ]

    func testOverride() async throws {
        let compiler = try newCompiler(functions: globalOverrideFunction)

        let results = try await compiler.compile(string: "a { a: ofunc() }", outputStyle: .compressed, functions: localOverrideFunction)
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
        let separators: [(Sass_EmbeddedProtocol_ListSeparator,
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

    /// SassArgList conversion
    func testSassArgListConversion() throws {
        var observerCalled = false
        let argList = SassArgumentList([SassString("one")],
                                        keywords: ["two": SassNumber(23)],
                                        keywordsObserver: { observerCalled = true },
                                        separator: .slash)
        let value = Sass_EmbeddedProtocol_Value(argList)
        XCTAssertTrue(observerCalled)
        let listBack = try value.asSassValue()
        XCTAssertEqual(argList, listBack)
        XCTAssertEqual(argList.keywords, try listBack.asArgumentList().keywords)
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
        XCTAssertEqual(.rgb, backRgb.preferredFormat)
        XCTAssertEqual(rgb, backRgb)

        let hsl = try SassColor(hue: 40, saturation: 66, lightness: 22, alpha: 1.0)
        let hslVal = Sass_EmbeddedProtocol_Value(hsl)
        let backHsl = try hslVal.asSassValue().asColor()
        XCTAssertEqual(.hsl, backHsl.preferredFormat)
        XCTAssertEqual(hsl, backHsl)

        let hwb = try SassColor(hue: 40, whiteness: 66, blackness: 22, alpha: 1.0)
        let hwbVal = Sass_EmbeddedProtocol_Value(hwb)
        let backHwb = try hwbVal.asSassValue().asColor()
        XCTAssertEqual(.hwb, backHwb.preferredFormat)
        XCTAssertEqual(hwb, backHwb)
    }

    /// Compiler functions
    func testSassCompilerFunctionConversion() throws {
        let f1 = SassCompilerFunction(id: 100)
        let fVal = Sass_EmbeddedProtocol_Value(f1)
        let backF = try fVal.asSassValue()
        XCTAssertEqual(f1, backF)
    }

    func testSassCompilerFunction() async throws {

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
        let results = try await compiler.compile(string: scss, outputStyle: .compressed)
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

    func testSassDynamicFunction() async throws {
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
        let results = try await compiler.compile(string: scss, outputStyle: .compressed)
        XCTAssertEqual(#"a{b:9}"#, results.css)

        // what a monstrosity
    }

    let slowEchoFunction: SassFunctionMap = [
        "slowEcho($param)" : { args in
            try? await Task.sleep(nanoseconds: 1 * 1000 * 1000 * 1000)
            return try args[0].asString()
        }
    ]

    func testAsyncHostFunction() async throws {
        let compiler = try newCompiler(functions: slowEchoFunction)
        let results = try await compiler.compile(string: "a { a: slowEcho('fish') }", outputStyle: .compressed)
        XCTAssertEqual(#"a{a:"fish"}"#, results.css)
    }

    func testAsyncDynamicFunction() async throws {
        let fishMakerMaker: SassFunction = { args in
            SassDynamicFunction(signature: "myFish()") { args in
                SassString("plaice")
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
        let results = try await compiler.compile(string: scss, outputStyle: .compressed)
        XCTAssertEqual(#"a{b:"plaice"}"#, results.css)
    }

    /// ArgumentList
    func testVarargs() async throws {
        let varArgsFunction: SassFunctionMap = [
            "varFn($first, $args...)" : { args in
                XCTAssertEqual(2, args.count)
                try XCTAssertNoThrow(args[0].asNumber().asInt())
                let lst = try Array(args[1].asArgumentList())
                XCTAssertEqual(2, lst.count)
                return SassNumber(1)
            }
        ]

        let scss = """
        a {
          b: varFn(1, 2, "fish")
        }
        """

        let compiler = try newCompiler(functions: varArgsFunction)
        let results = try await compiler.compile(string: scss, outputStyle: .compressed)
        XCTAssertEqual("a{b:1}", results.css)
    }

    func testVarArgsKwArgs() async throws {
        let varArgsFunctions: SassFunctionMap = [
            "kwReadingFn($args...)" : { args in
                XCTAssertEqual(1, args.count)
                let argList = try args[0].asArgumentList()
                print(argList.keywords.keys) // access the keywords
                return SassNumber(1)
            },
            "kwIgnoringFn($args...)" : { args in
                XCTAssertEqual(1, args.count)
                return SassNumber(1)
            }
        ]

        func scss(_ fname: String) -> String {
        """
        a {
          b: \(fname)(1, 2, "fish", $kw1: 22, $kw2: "bucket")
        }
        """
        }

        let compiler = try newCompiler(functions: varArgsFunctions)
        let results = try await compiler.compile(string: scss("kwReadingFn"), outputStyle: .compressed)
        XCTAssertEqual("a{b:1}", results.css)

        do {
            let r = try await compiler.compile(string: scss("kwIgnoringFn"))
            XCTFail("Managed to compile: \(r)")
        } catch let error as CompilerError {
            XCTAssertTrue(error.description.contains("No arguments named"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Test host-created arg lists, that the ID of 0 isn't reported back to the compiler.
    func testHostCreatedArgList() async throws {
        let functions: SassFunctionMap = [
            "createAL()" : { _ in
                SassArgumentList([SassNumber(23)], keywords: ["first": SassConstants.true])
            },
            "verifyAL($al)" : { args in
                XCTAssertEqual(1, args.count)
                let al = try args[0].asArgumentList()
                XCTAssertEqual(1, Array(al).count)
                XCTAssertEqual(1, al.keywords.count)
                return SassNumber(1)
            }
        ]

        let scss = """
        a {
          b: verifyAL(createAL());
        }
        """

        let compiler = try newCompiler(functions: functions)
        let results = try await compiler.compile(string: scss, outputStyle: .compressed)
        XCTAssertEqual("a{b:1}", results.css)
    }

    // Calculations

    func testCalculationConversion() throws {
        let calc1 = SassCalculation(kind: .clamp, arguments: [.interpolation("$fred"), .string("$barney")])
        let calc2 = SassCalculation(calc: .operation(.calculation(calc1), .dividedBy, .number(28, unit: "px")))

        let protoCalc = Sass_EmbeddedProtocol_Value(calc2)
        let backCalc = try protoCalc.asSassValue()

        XCTAssertEqual(calc2, backCalc)
    }

    func testCalcOperators() throws {
        typealias S = SassCalculation.Operator
        typealias P = Sass_EmbeddedProtocol_CalculationOperator
        let p: [P] = [.plus, .minus, .times, .divide]
        let s: [S] = [.plus, .minus, .times, .dividedBy]

        try zip(p, s).forEach { ops in
            let sFromP = try S(ops.0)
            let pFromS = P(ops.1)
            XCTAssertEqual(ops.1, sFromP)
            XCTAssertEqual(ops.0, pFromS)
        }

        let weird: P = .UNRECOGNIZED(42)
        XCTAssertThrowsError(try S(weird))
    }

    func testProtocolErrors() throws {
        let unknownCalc: Sass_EmbeddedProtocol_Value.Calculation = .with {
            $0.name = "fred"
            $0.arguments = []
        }
        XCTAssertThrowsError(try SassCalculation(unknownCalc))

        let badOpCalc: Sass_EmbeddedProtocol_Value.Calculation = .with {
            $0.name = "calc"
            $0.arguments = [.with {
                $0.value = .operation(.with {
                    $0.operator = .times
                })
            }
            ]
        }
        XCTAssertThrowsError(try SassCalculation(badOpCalc))
    }
}
