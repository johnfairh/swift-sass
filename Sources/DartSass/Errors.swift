//
//  Errors.swift
//  swift-sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

/// Errors thrown by this module
enum SassError: Error {
    /// There was an error communicating with the embedded sass compiler.
    /// The payload is english text describing the nature of the problem.  There is probably nothing that
    /// a user can do about this.
    case protocolError(String)
}
