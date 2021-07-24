//
//  Versions.swift
//  DartSass
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
                                           prereleaseIdentifiers: ["beta", "11"])

    /// Check the versions reported by the compiler are OK.
    func check() throws {
        if protocolVersion < Versions.minProtocolVersion {
            throw ProtocolError("Embedded Sass compiler does not support required protocol version \(Versions.minProtocolVersion).  Its versions are: \(self)")
        }
        if protocolVersion.major > Versions.minProtocolVersion.major {
            throw ProtocolError("Embedded Sass compiler protocol version is incompatible with required version \(Versions.minProtocolVersion) -> nextMajor.  Its versions are: \(self)")
        }
    }
}

import NIO

/// Version response injection for testing and bringup until the compiler implements the request.

protocol VersionsResponder {
    func provideVersions(eventLoop: EventLoop,
                         msg: Sass_EmbeddedProtocol_InboundMessage,
                         callback: @escaping (Sass_EmbeddedProtocol_OutboundMessage) -> Void)
}

struct DefaultVersionsResponder: VersionsResponder {
    static let defaultVersions =
        Versions(protocolVersionString: Versions.minProtocolVersion.toString(),
                 packageVersionString: "0.0.1",
                 compilerVersionString: "0.0.1",
                 compilerName: "ProbablyDartSass")

    private let versions: Versions
    init(_ versions: Versions = Self.defaultVersions) {
        self.versions = versions
    }

    func provideVersions(eventLoop: EventLoop,
                         msg: Sass_EmbeddedProtocol_InboundMessage,
                         callback: @escaping (Sass_EmbeddedProtocol_OutboundMessage) -> Void) {
        eventLoop.scheduleTask(in: .milliseconds(100)) {
            callback(.with {$0.versionResponse = .init(versions, id: msg.versionRequest.id) })
        }
    }
}

extension Versions {
    static var responder: VersionsResponder? = DefaultVersionsResponder()

    static func willProvideVersions(eventLoop: EventLoop,
                                    msg: Sass_EmbeddedProtocol_InboundMessage,
                                    callback: @escaping (Sass_EmbeddedProtocol_OutboundMessage) -> Void) -> Bool {
        guard let responder = responder else {
            return false
        }
        responder.provideVersions(eventLoop: eventLoop, msg: msg, callback: callback)
        return true
    }
}
