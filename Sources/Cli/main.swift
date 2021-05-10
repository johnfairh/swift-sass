//
//  main.swift
//  Cli
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Shim wrapper around both compilers for large-scale testing.
// Wouldn't normally import both DartSass & LibSass...

import DartSass
import LibSass
import Foundation

let args = ProcessInfo.processInfo.arguments
guard args.count == 5 else {
    fputs("Syntax: ssassc dart|libsass <input file> <output css file> <output srcmap file>\n", stderr)
    exit(1)
}

func compileWithDartSass(input: URL) throws -> CompilerResults {
    let compiler = try DartSass.Compiler(messageStyle: .terminalColored)
    defer { try? compiler.syncShutdownGracefully() }

    return try compiler.compile(fileURL: input, createSourceMap: true)
}

func compileWithLibSass(input: URL) throws -> CompilerResults {
    let compiler = LibSass.Compiler(messageStyle: .terminalColored)
    return try compiler.compile(fileURL: input, createSourceMap: true)
}

let compilers = ["dart": compileWithDartSass,
                 "libsass": compileWithLibSass]

do {
    let compilerName = args[1]
    let input = URL(fileURLWithPath: args[2])
    let outputCss = URL(fileURLWithPath: args[3])
    let outputSrcMap = URL(fileURLWithPath: args[4])

    guard let compiler = compilers[compilerName] else {
        fputs("Unknown compiler '\(compilerName)' - should be 'dart' or 'libsass'\n", stderr)
        exit(3)
    }

    let results = try compiler(input)
        .withFileLocations(cssFileURL: outputCss, sourceMapFileURL: outputSrcMap)

    results.messages.forEach {
        print($0)
    }
    try results.css.write(to: outputCss, atomically: false, encoding: .utf8)
    try results.sourceMap?.write(to: outputSrcMap, atomically: false, encoding: .utf8)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(2)
}
