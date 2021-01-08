//
//  DartSassEmbedded.swift
//  SassEmbedded
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

#if os(macOS)
@_implementationOnly import DartSassEmbeddedMacOS
#elseif os(Linux)
@_implementationOnly import DartSassEmbeddedLinux
#else
final class DartSassEmbeddedBundle {
    static var bundle: Bundle? { nil }
}
#endif

enum DartSassEmbedded {
    /// Decode the platform and locate the platform-specific binary.
    static func getURL() throws -> URL {
        guard let bundle = DartSassEmbeddedBundle.bundle,
              let url = bundle.url(forResource: "dart-sass-embedded",
                                   withExtension: nil,
                                   subdirectory: "sass_embedded") else {
            throw LifecycleError("No `dart-sass-embedded` is available for the current platform.")
        }
        return url
    }
}
