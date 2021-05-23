//
//  CompilerResults.swift
//  Sass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

/// The output from a successful compilation.
public struct CompilerResults {
    /// The  CSS produced by the Sass compiler.
    public let css: String

    /// The JSON sourcemap for `css`, style according to the `SourceMapStyle` provided at compile time.
    public let sourceMap: String?

    /// Any compiler warnings and debug statements.
    public let messages: [CompilerMessage]

    /// :nodoc:
    public init(css: String, sourceMap: String?, messages: [CompilerMessage]) {
        self.css = css
        self.sourceMap = sourceMap
        self.messages = messages
    }
}
