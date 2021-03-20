//
//  TestFunctions.swift
//  SassLibSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import TestHelpers
import SassLibSass

/// Custom functions, libsass-style.
/// Most of this is validating the round-tripping between our types and libsass.
class TestFunctions: XCTestCase {

    let echoFunction: SassFunctionMap = [
        "myEcho($param)" : { args in
            return args[0]
        }
    ]

    func testEcho() throws {
        let compiler = Compiler()
        let results = try compiler.compile(string: "a { b: myEcho(false) }",
                                           outputStyle: .compressed,
                                           functions: echoFunction)
        XCTAssertEqual("a{b:false}\n", results.css)
    }
}

