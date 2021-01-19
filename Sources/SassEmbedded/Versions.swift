//
//  Versions.swift
//  SassEmbedded
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Semver

/// The set of versions reported by the embedded Sass compiler.
///
/// The only part we police right now is the protocol version, the rest is just informative.
struct Versions: CustomStringConvertible {
    let protocolVersionString: String
    let packageVersionString: String
    let compilerVersionString: String
    let compilerName: String

    var description: String {
        "SassEmbeddedProtocol=\(protocolVersionString) " +
            "DartSassEmbedded=\(packageVersionString) " +
            "Compiler \(compilerName)=\(compilerVersionString)"
    }

    var protocolVersion: Semver {
        (try? Semver(string: protocolVersionString)) ?? Semver(major: 0)
    }

    /// Minimum supported version of the Embedded Sass Protocol that we support, from here up to the next major.
    static let minProtocolVersion = Semver(major: 1, minor: 0, patch: 0,
                                           prereleaseIdentifiers: ["beta", "6"])

    /// Check the versions reported by the compiler are OK.
    func check() throws {
        if protocolVersion < Versions.minProtocolVersion {
            throw ProtocolError("Embedded Sass compiler does not support required protocol version \(Versions.minProtocolVersion).  Its versions are: \(self)")
        }
        if protocolVersion.major > Versions.minProtocolVersion.major {
            throw ProtocolError("Embedded Sass compiler protocol version is incompatible with required version \(Versions.minProtocolVersion).  Its versions are: \(self)")
        }
    }
}

/// Version response injection for testing and bringup until the compiler implements the request.
extension Versions {
    static var fakeVersions: Versions? =
        Versions(protocolVersionString: Versions.minProtocolVersion.toString(),
                 packageVersionString: "0.0.1",
                 compilerVersionString: "0.0.1",
                 compilerName: "ProbablyDartSass")

    static var fakeVersionsMsg: Sass_EmbeddedProtocol_OutboundMessage? {
        fakeVersions.flatMap { ver in .with { $0.versionResponse = .init(ver) } }
    }
}
