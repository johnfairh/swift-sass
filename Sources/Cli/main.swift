//
//  main.swift
//  Cli
//
//  Copyright 2020-2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Shim wrapper around the dart sass compiler for large-scale testing.  This
// doesn't add any value over using dart-sass!

import DartSass
import Foundation

let args = ProcessInfo.processInfo.arguments
guard args.count == 3 else {
    fputs("Syntax: ssassc <input file> <output file>\n", stderr)
    exit(1)
}

do {
    let input = URL(fileURLWithPath: args[1])
    let output = URL(fileURLWithPath: args[2])

    let compiler = try Compiler(eventLoopGroupProvider: .createNew,
                                messageStyle: .terminalColored)
    defer { try? compiler.syncShutdownGracefully() }

    let results = try compiler.compile(fileURL: input)

    results.messages.forEach {
        print($0)
    }
    try results.css.write(to: output, atomically: false, encoding: .utf8)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(2)
}
