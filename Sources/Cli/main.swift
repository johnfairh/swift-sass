//
//  main.swift
//  Cli
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Shim wrapper around the dart sass compiler for large-scale testing.  This
// doesn't add any value over using dart-sass!

import SassEmbedded
import Foundation

// Expected to be run via `swift run` from the package directory.
var dartSassEmbeddedURL: URL {
    let packageRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let dartSassRootURL = packageRootURL
        .appendingPathComponent("Tests")
        .appendingPathComponent("SassEmbeddedTests")
        .appendingPathComponent("dart-sass-embedded")

    #if os(Linux)
    let platformURL = dartSassRootURL.appendingPathComponent("linux")
    #else
    let platformURL = dartSassRootURL.appendingPathComponent("macos")
    #endif
    return platformURL
        .appendingPathComponent("sass_embedded")
        .appendingPathComponent("dart-sass-embedded")
}

let args = ProcessInfo.processInfo.arguments
guard args.count == 3 else {
    fputs("Syntax: ssassc <input file> <output file>\n", stderr)
    exit(1)
}

do {
    let inputURL = URL(fileURLWithPath: args[1])
    let outputURL = URL(fileURLWithPath: args[2])

    let compiler = try Compiler(eventLoopGroupProvider: .createNew,
                                embeddedCompilerURL: dartSassEmbeddedURL)
    defer { try? compiler.syncShutdownGracefully() }

    let results = try compiler.compile(fileURL: inputURL)

    results.messages.forEach {
        print($0)
    }
    try results.css.write(to: outputURL, atomically: false, encoding: .utf8)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(2)
}
