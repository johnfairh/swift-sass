//
//  TestUtils.swift
//  DartSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

import Foundation

enum TestUtils {
    static var unitTestDirURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    static var dartSassEmbeddedURL: URL {
        let rootURL = unitTestDirURL.appendingPathComponent("dart-sass-embedded")
        #if os(Linux)
        let platformURL = rootURL.appendingPathComponent("linux")
        #else
        let platformURL = rootURL.appendingPathComponent("macos")
        #endif
        return platformURL.appendingPathComponent("sass_embedded")
            .appendingPathComponent("dart-sass-embedded")
    }
}
