//
//  Compiler.swift
//  SassLibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//
@_exported import Sass
import struct Foundation.URL

/// A Sass compiler interface using LibSass.
///
public struct Compiler {
    private let messageStyle: CompilerMessageStyle
    private let globalImporters: [ImportResolver]
    private let globalFunctions: SassFunctionMap

    /// Set up a new instance of the compiler.
    ///
    /// - parameter messageStyle: Style for diagnostic message descriptions.  Default `.plain`.
    /// - parameter importers: Rules for resolving `@import` that cannot be satisfied relative to
    ///   the source file's path, used for all this compiler's compilations.
    /// - parameter functions: Sass functions available to all this compiler's compilations.
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

    /// Compile to CSS from a stylesheet file.
    ///
    /// - parameters:
    ///   - fileURL: The URL of the file to compile.  The file extension determines the
    ///     expected syntax of the contents, so it must be css/scss/sass.
    ///   - outputStyle: How to format the produced CSS.  Default `.nested`.
    ///   - createSourceMap: Create a JSON source map for the CSS.  Default `false`.
    ///   - importers: Rules for resolving `@import` etc. for this compilation, used in order after
    ///     `sourceFileURL`'s directory and any set globally..  Default none.
    ///   - functions: Functions for this compilation, overriding any with the same name previously
    ///     set globally. Default none.
    /// - throws: `CompilerError` if the stylesheet can't be compiled, for example a syntax error.
    /// - returns: `CompilerResults` with CSS and optional source map.
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

    /// Compile to CSS from an inline stylesheet.
    ///
    /// - parameters:
    ///   - string: The stylesheet text to compile.
    ///   - syntax: The syntax of `text`, default `.scss`.
    ///   - fileURL: The absolute URL to associate with `string`, from where it was loaded.
    ///     Default `nil` meaning unknown.  LibSass substitutes something like `stream://stdin`
    ///     where necessary.
    ///   - outputStyle: How to format the produced CSS.  Default `.nested`.
    ///   - createSourceMap: Create a JSON source map for the CSS.  Default `false`.
    ///   - importers: Rules for resolving `@import` etc. for this compilation, used in order after
    ///     any set globally.  Default none.
    ///   - functions: Functions for this compilation, overriding any with the same name previously
    ///     set globally.  Default none.
    /// - throws: `CompilerError` if the stylesheet can't be compiled, for example a syntax error.
    /// - returns: `CompilerResults` with CSS and optional source map.
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
