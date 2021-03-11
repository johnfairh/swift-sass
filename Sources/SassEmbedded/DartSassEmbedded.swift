//
//  DartSassEmbedded.swift
//  SassEmbedded
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation
import SystemPackage

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
    static func getFilePath() throws -> FilePath {
        let programName = getenv("DART_SASS_EMBEDDED_NAME").flatMap { String(cString: $0) } ?? "dart-sass-embedded"
        guard let bundle = DartSassEmbeddedBundle.bundle,
              let path = bundle.path(forResource: programName,
                                     ofType: nil,
                                     inDirectory: "sass_embedded") else {
            throw LifecycleError("No `\(programName)` is available for the current platform.")
        }
        return FilePath(path)
    }
}
