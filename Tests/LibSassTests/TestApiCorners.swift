//
//  TestApiCorners.swift
//  LibSassTests
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import TestHelpers
@testable import LibSass

// Dumb tests that the RAII bits work.
// Or at least, don't crash: Xcode coverage doesn't work properly in `deinit`.
// Tested for leaks manually using libsass4 patch and DEBUG_SHARED_PTR.
class TestApiCorners: XCTestCase {
    override func tearDown() { LibSass4.dumpMemLeaks() }

    func testImport() {
        let myImport = LibSass4.Import(fileURL: URL(fileURLWithPath: "file.scss"))
        print(myImport)
    }

    func testImporter() {
        let myImporter = LibSass4.Importer(priority: 100, callback: { _, _ in nil })
        print(myImporter)
    }

    func testImportList() {
        let myImportList = LibSass4.ImportList()
        print(myImportList)
    }

    func testFunction() {
        let myFunction = LibSass4.Function(signature: "", callback: { _, _ in LibSass4.Value() })
        print(myFunction)
    }

    func testValue() {
        let myValue = LibSass4.Value(string: "", isQuoted: false)
        print(myValue)
    }
}
