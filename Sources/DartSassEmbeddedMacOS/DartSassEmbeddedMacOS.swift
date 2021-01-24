//
//  DartSassEmbeddedMacOS.swift
//  DartSassEmbeddedMacOS
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

// This is a wrapper around the macOS Dart Sass Embedded binary that, all being
// well, is linked and packaged only when building for a macOS destination.
//
// Some further shenanigans here to make the xctest-in-Xcode version work.

public final class DartSassEmbeddedBundle {
    public static var bundle: Bundle? {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.init(for: DartSassEmbeddedBundle.self)
        #endif
    }
}
