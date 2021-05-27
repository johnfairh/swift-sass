//
//  Compiler.swift
//  LibSass
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
/// 1. Consult every `ImportResolver.importer(...)` or `ImportResolver.fileImporter(...)`
///   in the order given.
/// 2. Attempt to resolve relative to the importing stylesheet's path, if it has one.
///   If the importing stylesheet does not have a path then use the current directory.
/// 3. Search every `ImportResolver.loadPath(...)` in the order given.
///
/// The most important difference between this and `DartSass.Compiler` is that here,
/// custom importers always have priority over source-relative.  Further, the full list of custom importers
/// is always called in order: LibSass does not maintain any link between a stylesheet and the importer
/// that produced it.
public final class Compiler {
    private let messageStyle: CompilerMessageStyle
    private let globalImporters: [ImportResolver]
    private let globalFunctions: SassFunctionMap

    // MARK: Lifecycle

    /// Set up a new instance of the compiler.
    ///
    /// - parameter messageStyle: Style for diagnostic message descriptions.  Default `.plain`.
    /// - parameter importers: Rules for resolving `@import` that cannot be satisfied relative to
    ///   the source file's path, used for all this compiler's compilations.
    /// - parameter functions: Custom Sass functions available to all this compiler's compilations.
    public init(messageStyle: CompilerMessageStyle = .plain,
                importers: [ImportResolver] = [],
                functions: SassFunctionMap = [:]) {
        self.messageStyle = messageStyle
        self.globalImporters = importers
        self.globalFunctions = functions
    }

    /// The version of the underlying LibSass library, in [semver](https://semver.org/spec/v2.0.0.html) format.
    public static var libVersion: String {
        LibSass4.version
    }

    // MARK: Compilation

    /// Compile to CSS from a stylesheet file.
    ///
    /// - parameters:
    ///   - fileURL: The URL of the file to compile.  The file extension determines the
    ///     expected syntax of the contents, so it must be css/scss/sass.
    ///   - outputStyle: How to format the produced CSS.  Default `.nested`.
    ///   - sourceMapStyle: Kind of source map to create for the CSS.  Default `.separateSources`.
    ///   - importers: Rules for resolving `@import` etc. for this compilation, used in order after
    ///     `sourceFileURL`'s directory and any set globally.  Default none.
    ///   - functions: Custom functions for this compilation, overriding any with the same name
    ///     previously set globally. Default none.
    /// - throws: `CompilerError` if the stylesheet can't be compiled, for example a syntax error.
    /// - returns: `CompilerResults` with CSS and optional source map.
    public func compile(fileURL: URL,
                        outputStyle: CssStyle = .nested,
                        sourceMapStyle: SourceMapStyle = .separateSources,
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        precondition(fileURL.isFileURL)
        return try compile(mainImport: LibSass4.Import(fileURL: fileURL),
                           outputStyle: outputStyle, sourceMapStyle: sourceMapStyle,
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
    ///   - sourceMapStyle: Kind of source map to create for the CSS.  Default `.separateSources`.
    ///   - importers: Rules for resolving `@import` etc. for this compilation, used in order after
    ///     any set globally.  Default none.
    ///   - functions: Custom functions for this compilation, overriding any with the same name
    ///     previously set globally.  Default none.
    /// - throws: `CompilerError` if the stylesheet can't be compiled, for example a syntax error.
    /// - returns: `CompilerResults` with CSS and optional source map.
    public func compile(string: String, syntax: Syntax = .scss, fileURL: URL? = nil,
                        outputStyle: CssStyle = .nested,
                        sourceMapStyle: SourceMapStyle = .separateSources,
                        importers: [ImportResolver] = [],
                        functions: SassFunctionMap = [:]) throws -> CompilerResults {
        fileURL.flatMap { precondition($0.isFileURL) }
        return try compile(mainImport: LibSass4.Import(string: string, fileURL: fileURL, syntax: syntax.toLibSass),
                           outputStyle: outputStyle, sourceMapStyle: sourceMapStyle,
                           importers: importers, functions: functions)
    }

    private func compile(mainImport: LibSass4.Import,
                         outputStyle: CssStyle,
                         sourceMapStyle: SourceMapStyle,
                         importers: [ImportResolver],
                         functions: SassFunctionMap) throws -> CompilerResults {
        let compiler = LibSass4.Compiler()
        LibSass4.chdir(to: FileManager.default.currentDirectoryPath)
        compiler.set(entryPoint: mainImport)
        compiler.set(style: outputStyle.toLibSass)
        compiler.set(precision: 10)
        compiler.set(loggerUnicode: true)
        compiler.set(loggerColors: messageStyle == .terminalColored)
        compiler.set(sourceMapMode: sourceMapStyle.toLibSassMode)
        compiler.set(sourceMapEmbedContents: sourceMapStyle.toLibSassEmbedded)
        compiler.set(sourceMapFileURLs: true)
        compiler.set(suppressStderr: true)

        // Importers
        compiler.add(importers: globalImporters + importers)

        // Functions
        // Override global functions with per-compile ones that have the same name.
        let localFnsNameMap = functions._asSassFunctionNameElementMap
        let globalFnsNameMap = globalFunctions._asSassFunctionNameElementMap
        let mergedFnsNameMap = globalFnsNameMap.merging(localFnsNameMap) { g, l in l }
        compiler.add(functions: mergedFnsNameMap.values)

        // Go
        compiler.parseCompileRender()
        if let error = compiler.error {
            throw CompilerError(error, messages: compiler.messages)
        }
        return CompilerResults(css: compiler.outputString,
                               sourceMap: compiler.sourceMapString?.withoutFile,
                               messages: compiler.messages)
    }
}

// Delete the 'file' key from the sourcemap to bring in line with Dart Sass - our
// model is to figure this out later if necessary via `CompilerResults.withFileLocations(...)`.
private extension String {
    var withoutFile: String {
        replacingOccurrences(of: #"\#t"file": "stream://stdout",\#n"#, with: "")
    }
}
