//
//  Compiler.swift
//  SassLibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//
@_exported import Sass
import struct Foundation.URL
import class Foundation.FileManager // getcwd()

/// A Sass compiler that uses LibSass.
///
/// ## Custom importer resolution
///
/// LibSass uses a different algorithm to Dart Sass for processing imports.  The ordering is:
/// 1. Consult every `ImportResolver.importer(_)` or `ImportResolver.fileImporter(_)`
///   in the order given.
/// 2. Attempt to resolve relative to the importing stylesheet's path, if it has one.
///   If the importing stylesheet does not have a path then use the current directory.
/// 3. Search every `.loadPath` in the order given.
///
/// The most important difference between this and `EmbeddedSass.Compiler` is that here,
/// custom importers always have priority over source-relative.  Further, the full list of custom importers
/// is always called in order: LibSass does not maintain any link between a stylesheet and the importer
/// that produced it.
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
    ///     Default `nil` meaning unknown, though it is best to avoid this if possible: LibSass substitutes
    ///     something like `stream://stdin` where necessary which is usually unhelpful.
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
        LibSass.chdir(to: FileManager.default.currentDirectoryPath)
        compiler.set(entryPoint: mainImport)
        compiler.set(style: outputStyle.toLibSass)
        compiler.set(precision: 10)
        compiler.set(loggerStyle: messageStyle.toLibSass)
        if createSourceMap {
            compiler.enableSourceMap()
            compiler.set(sourceMapEmbedContents: false) // to match embedded-sass API
            // sourceRoot - dart sets an empty string.  libsass just ignores the field if empty.
        }

        // Workaround LibSass bug: outputPath is not inferred properly.
        if case let mainURL = mainImport.absPath,
           mainURL.isFileURL {
            compiler.set(outputPath: mainURL.deletingPathExtension().appendingPathExtension("css"))
        }
        // End workaround

        compiler.add(importers: globalImporters + importers)
        compiler.parseCompileRender()
        if let error = compiler.error {
            throw CompilerError(error, messages: compiler.messages)
        }
        return CompilerResults(css: compiler.outputString, sourceMap: compiler.sourceMapString, messages: compiler.messages)
    }
}
