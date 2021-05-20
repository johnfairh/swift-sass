//
//  TestSourceMaps.swift
//  LibSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation
import XCTest
@testable import LibSass
import SourceMapper

/// Source map corners
class TestSourceMaps: XCTestCase {
    override func tearDown() { LibSass4.dumpMemLeaks() }

    /// 'file' inference
    func testFileInference() throws {
        let compiler = Compiler()

        try ["foo.scss", "foo", "foo.css.scss"].forEach { inputName in
            let results = try compiler.compile(string: "", fileURL: URL(fileURLWithPath: inputName))
            XCTAssertEqual("", results.css)
            let map = try SourceMap(string: XCTUnwrap(results.sourceMap))
            XCTAssertEqual("foo.css", map.file)
        }
    }
}
