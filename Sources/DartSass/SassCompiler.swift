//
//  SassCompiler.swift
//  DartSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

import Foundation

public struct Compiler {
    let child: Exec.Child
    public init(embeddedDartSass: URL) throws {
        child = try Exec.spawn(embeddedDartSass)
    }
}
