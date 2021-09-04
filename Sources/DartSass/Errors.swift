//
//  Errors.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

// Errors thrown by this module

/// Thrown on detecting an error communicating with the Sass embedded compiler: for example a badly
/// formed or out-of-sequence message.
///
/// The payload is text describing the nature of the problem.  There is probably nothing that
/// a user can do about this.
public struct ProtocolError: Error, CustomStringConvertible {
    /// Text explaining the protocol error.
    public let description: String

    init(_ text: String) {
        description = text
        Compiler.logger.debug("protocol_error: \(text)")
    }
}

/// Thrown on detecting a usage error of the `Compiler` API, for example trying to use it after shutdown.
public struct LifecycleError: Error, CustomStringConvertible {
    /// Text explaining the lifecycle error.
    public let description: String

    init(_ text: String) {
        description = text
        Compiler.logger.debug("lifecycle_error: \(text)")
    }
}

import NIO
extension EventLoop {
    func makeProtocolError<T>(_ text: String) -> EventLoopFuture<T> {
        makeFailedFuture(ProtocolError(text))
    }

    func makeLifecycleError<T>(_ text: String) -> EventLoopFuture<T> {
        makeFailedFuture(ProtocolError(text))
    }
}
