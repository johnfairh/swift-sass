//
//  Errors.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

// Errors thrown by this module

/// There was an error communicating with the embedded Sass compiler: for example a badly formed
/// or out-of-sequence message.
/// The payload is english text describing the nature of the problem.  There is probably nothing that
/// a user can do about this.
public struct ProtocolError: Error, CustomStringConvertible {
    /// English text explaining the protocol error.
    public let description: String

    init(_ text: String) {
        description = text
        Compiler.logger.error(.init(stringLiteral: text))
    }
}

import NIO
extension EventLoop {
    func makeProtocolError<T>(_ text: String) -> EventLoopFuture<T> {
        makeFailedFuture(ProtocolError(text))
    }
}
