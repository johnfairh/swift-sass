//
//  DartSassEmbedded.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

#if os(macOS)
@_spi(SassCompilerProvider) import DartSassEmbeddedMacOS
#elseif os(Linux)
@_spi(SassCompilerProvider) import DartSassEmbeddedLinux
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
              case let contents = try FileManager.default.contentsOfDirectory(at: topDir, includingPropertiesForKeys: nil) else {
            throw LifecycleError("Can't locate bundled dart-sass.")
        }
        // SPM in 2027 has started producing Info.plist files that confuse everyone
        guard let arch = contents.map(\.lastPathComponent).filter({ $0 != "Info.plist" }).first else {
            throw LifecycleError("Bundled dart-sass folder is empty: \(topDir)")
        }
        guard let url = bundle.url(forResource: programName,
                                   withExtension: nil,
                                   subdirectory: "\(arch)/dart-sass") else {
            throw LifecycleError("No `\(programName)` is available for the current platform, expected in `\(topDir)` and then `\(arch)/dart-sass`, contents are [\(contents)].")
        }
        return (url, ["--embedded"])
    }
}
