//
//  Compiler.swift
//  SassLibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//
@_exported import Sass
import struct Foundation.URL

public final class Compiler {
    private let messageStyle: CompilerMessageStyle
    private let globalImporters: [ImportResolver]
    private let globalFunctions: SassFunctionMap

    public init(messageStyle: CompilerMessageStyle = .plain,
                importers: [ImportResolver] = [],
                functions: SassFunctionMap = [:]) {
        self.messageStyle = messageStyle
        self.globalImporters = importers
        self.globalFunctions = functions
    }

    /// The version of the underlying LibSass library, in [semver](https://semver.org/spec/v2.0.0.html) format.
    public static var libVersion: String {
        LibSass.version
    }

    public func compile(fileURL: URL,
                        outputStyle: CssStyle = .nested,
                        createSourceMap: Bool = false,
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        precondition(fileURL.isFileURL)
        return try compile(mainImport: LibSass.Import(fileURL: fileURL),
                           outputStyle: outputStyle, createSourceMap: createSourceMap,
                           importers: importers, functions: functions)
    }

    public func compile(string: String, syntax: Syntax = .scss, fileURL: URL? = nil,
                        outputStyle: CssStyle = .nested,
                        createSourceMap: Bool = false,
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        fileURL.flatMap { precondition($0.isFileURL) }
        return try compile(mainImport: LibSass.Import(string: string, fileURL: fileURL, syntax: syntax.toLibSass),
                           outputStyle: outputStyle, createSourceMap: createSourceMap,
                           importers: importers, functions: functions)
    }

    private func compile(mainImport: LibSass.Import,
                         outputStyle: CssStyle, createSourceMap: Bool,
                         importers: [ImportResolver],
                         functions: SassFunctionMap) throws -> CompilerResults {
        let compiler = LibSass.Compiler()
        compiler.set(entryPoint: mainImport)
        compiler.set(style: outputStyle.toLibSass)
        compiler.set(precision: 10)
        compiler.set(loggerStyle: messageStyle.toLibSass)
        if createSourceMap {
            compiler.enableSourceMap()
            compiler.set(sourceMapEmbedContents: false) // to match embedded-sass API
            // sourceRoot - dart sets an empty string.  libsass just ignores the field if empty.
        }
        compiler.parseCompileRender()
        if let error = compiler.error {
            throw CompilerError(error, messages: compiler.messages)
        }
        return CompilerResults(css: compiler.outputString, sourceMap: compiler.sourceMapString, messages: compiler.messages)
    }
}
