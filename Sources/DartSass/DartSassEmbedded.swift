//
//  DartSassEmbedded.swift
//  DartSass
//
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
    /// Decode the platform and locate the platform-specific binary and any arguments
    static func getURLAndArgs() throws -> (URL, [String]) {
        let programName = getenv("DART_SASS_EMBEDDED_NAME").flatMap { String(cString: $0) } ?? "sass"
        guard let bundle = DartSassEmbeddedBundle.bundle,
              let topDir = bundle.resourceURL?.resolvingSymlinksInPath(),
              case let contents = try FileManager.default.contentsOfDirectory(at: topDir, includingPropertiesForKeys: nil),
              let arch = contents.first?.lastPathComponent,
              let url = bundle.url(forResource: programName,
                                    withExtension: nil,
                                    subdirectory: "\(arch)/dart-sass") else {
            throw LifecycleError("No `\(programName)` is available for the current platform.")

            // This archdir stuff is a mess - struggling with SPM not being able to rename stuff, or something
            // to let us collapse the file structure.
        }
        return (url, ["--embedded"])
    }
}
