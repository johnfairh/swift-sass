//
//  LibSassConversion.swift
//  SassLibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import LibSass4
import Sass
import Foundation

// Helpers to flip between common Sass types and LibSass API types.

extension Sass.Syntax {
    var toLibSass: SassImportSyntax {
        switch self {
        case .css: return SASS_IMPORT_CSS
        case .indented, .sass: return SASS_IMPORT_SASS
        case .scss: return SASS_IMPORT_SCSS
        }
    }
}

extension Sass.CssStyle {
    var toLibSass: SassOutputStyle {
        switch self {
        case .expanded: return SASS_STYLE_EXPANDED
        case .compressed: return SASS_STYLE_COMPRESSED
        case .nested: return SASS_STYLE_NESTED
        case .compact: return SASS_STYLE_COMPACT
        }
    }
}

extension CompilerMessageStyle {
    var toLibSass: SassLoggerStyle {
        switch self {
        case .plain: return SASS_LOGGER_UNICODE_MONO
        case .terminalColored: return SASS_LOGGER_UNICODE_COLOR
        }
    }
}

extension CompilerError {
    init(_ error: LibSass.Error, messages: [CompilerMessage]) {
        self.init(message: error.message,
                  span: Span(text: nil,
                             url: error.fileURL,
                             start: Span.Location(offset: 0,
                                                  line: error.lineNumber,
                                                  column: error.columnNumber),
                             end: nil,
                             context: nil),
                  // The stack trace format isn't specified, just throw the details together.
                  // Normal usage is to access the nice `description`.
                  stackTrace: error.stackTrace.reversed().map(\.text).joined(separator: "\n"),
                  messages: messages,
                  description: error.formatted)
    }
}

extension LibSass.Trace {
    var text: String {
        "\(fileURL.path) \(lineNumber):\(columnNumber)\(name.isEmpty ? "" : " \(name)")"
    }
}

// LibSass doesn't provide structured access to warning etc. messages.
// We do a very superficial and approximate job at decomposing its massive strings.

extension LibSass.Compiler {
    var messages: [CompilerMessage] {
        let warningString = self.warningString
        guard !warningString.isEmpty else {
            return []
        }
        let lines = warningString
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        var messages: [CompilerMessage] = []
        var currentStr = ""

        func emitCurrent() {
            guard !currentStr.isEmpty else { return }
            messages.append(CompilerMessage(libSassString: currentStr))
            currentStr = ""
        }

        lines.forEach { line in
            if let _ = CompilerMessage.Kind(libSass: line) {
                emitCurrent()
            }
            currentStr += line + "\n"
        }
        emitCurrent()
        return messages
    }
}

extension CompilerMessage {
    init(libSassString msg: String) {
        self.init(kind: Kind(libSass: msg)!,
                  message: msg,
                  span: nil,
                  stackTrace: nil,
                  description: msg)
    }
}

extension CompilerMessage.Kind {
    init?(libSass: String) {
        if libSass.contains(" DEBUG:") {
            self = .debug
        } else if libSass.contains("DEPRECATION WARNING") {
            self = .deprecation
        } else if libSass.contains("WARNING") {
            self = .warning
        } else {
            return nil
        }
    }
}

// Importers

extension LibSass.Import {
    convenience init(_ importerResults: ImporterResults) {
        self.init(string: importerResults.contents,
                  fileURL: importerResults.fileURL,
                  syntax: importerResults.syntax.toLibSass)
    }
}

extension LibSass.Compiler {
    func add(importers: [ImportResolver]) {
        importers.reversed().enumerated().forEach { x in
            add(importer: x.element, priority: x.offset)
        }
    }

    // Higher priority -> earlier in the internal list
    private func add(importer: ImportResolver, priority: Int) {

        func makeImportList( from: () throws -> LibSass.Import?) -> LibSass.ImportList? {
            do {
                guard let newImport = try from() else {
                    return nil
                }
                return .init(newImport)
            } catch {
                return .init(LibSass.Import(errorMessage: String(describing: error)))
            }
        }

        switch importer {
        case .loadPath(let url):
            precondition(url.isFileURL)
            add(includePath: url.path)

        case .importer(let client):
            let newImporter = LibSass.Importer(priority: Double(priority)) { [unowned self] url, _, _ in
                makeImportList {
                    try client(url, self.lastImport.absPath).flatMap {
                        LibSass.Import($0)
                    }
                }
            }
            add(customImporter: newImporter)

        case .fileImporter(let client):
            let newImporter = LibSass.Importer(priority: Double(priority)) { [unowned self] url, _, _ in
                makeImportList {
                    try client(url, self.lastImport.absPath).flatMap {
                        LibSass.Import(fileURL: $0)
                    }
                }
            }
            add(customImporter: newImporter)
        }
    }
}

// Functions

extension LibSass.Compiler {
    func add<S: Sequence>(functions: S) where S.Element == (key: String, value: SassFunction) {
        functions.forEach { addFunction(signature: $0.0, callback: $0.1) }
    }

    func addFunction(signature: String, callback: @escaping SassFunction) {
        let fn = LibSass.Function(signature: signature) { args, _ in
            do {
                // LibSass always builds a list to put the args in.
                // We do this level of unpacking for the client.
                precondition(args.kind == SASS_LIST, "LibSass didn't put function args in a list?")
                var argsArray = [SassValue]()
                for idx in 0..<args.listSize {
                    argsArray.append(try args[idx].asSassValue())
                }
                let retVal = try callback(argsArray)
                return try LibSass.Value.from(sassValue: retVal)
            } catch {
                return LibSass.Value(error: String(describing: error))
            }
        }
        add(customFunction: fn)
    }
}

// Values

// figure this out...
struct Error: Swift.Error {
}

extension LibSass.Value {
    func asSassValue() throws -> SassValue {
        switch kind {
        case SASS_BOOLEAN:
            return boolValue ? SassConstants.true : SassConstants.false

        default:
            throw Error()
        }
    }
}

struct LibSassVisitor: SassValueVisitor {
    func visit(string: SassString) throws -> LibSass.Value {
        throw Error()
    }

    func visit(number: SassNumber) throws -> LibSass.Value {
        throw Error()
    }

    func visit(color: SassColor) throws -> LibSass.Value {
        throw Error()
    }

    func visit(list: SassList) throws -> LibSass.Value {
        throw Error()
    }

    func visit(map: SassMap) throws -> LibSass.Value {
        throw Error()
    }

    func visit(bool: SassBool) throws -> LibSass.Value {
        LibSass.Value(bool: bool.isTruthy)
    }

    func visit(null: SassNull) throws -> LibSass.Value {
        throw Error()
    }

    func visit(compilerFunction: SassCompilerFunction) throws -> LibSass.Value {
        throw Error()
    }

    func visit(dynamicFunction: SassDynamicFunction) throws -> LibSass.Value {
        throw Error()
    }
}

extension LibSass.Value {
    static let visitor = LibSassVisitor()

    static func from(sassValue: SassValue) throws -> LibSass.Value {
        try sassValue.accept(visitor: visitor)
    }
}
