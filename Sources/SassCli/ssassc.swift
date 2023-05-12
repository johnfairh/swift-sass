//
//  ssassc.swift
//  SassCli
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Shim wrapper around the dart sass compiler for large-scale testing.  This
// doesn't add any value over using dart-sass!

import DartSass
import Foundation

func compileWithDartSass(input: URL) async throws -> CompilerResults {
    let compiler = try DartSass.Compiler(messageStyle: .terminalColored)
    return try await compiler.compile(fileURL: input)
}

func compileWithLibSass(input: URL) throws -> CompilerResults {
    preconditionFailure()
    //    let compiler = LibSass.Compiler(messageStyle: .terminalColored)
    //    return try compiler.compile(fileURL: input)
}

@main
struct SassC {
    static func main() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.count == 5 else {
            fputs("Syntax: ssassc dart|libsass <input file> <output css file> <output srcmap file>\n", stderr)
            exit(1)
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

            let results = try await compiler(input)
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
    }
}
