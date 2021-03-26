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
// Or at least, don't crash.  Can't validate on the C side; Xcode 11.4 coverage doesn't
// seem to work properly in `deinit` either.
class TestApiCorners: XCTestCase {
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
