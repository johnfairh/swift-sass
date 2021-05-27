//
//  LibSassConversion.swift
//  LibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import CLibSass4
import Sass

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

extension Sass.SourceMapStyle {
    var toLibSassMode: SassSrcMapMode {
        self == .none ? SASS_SRCMAP_NONE : SASS_SRCMAP_CREATE
    }

    var toLibSassEmbedded: Bool {
        self == .embeddedSources
    }
}

extension CompilerError {
    init(_ error: LibSass4.Error, messages: [CompilerMessage]) {
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

extension LibSass4.Trace {
    var text: String {
        "\(fileURL.path) \(lineNumber):\(columnNumber)\(name.isEmpty ? "" : " \(name)")"
    }
}

// LibSass doesn't provide structured access to warning etc. messages.
// We do a very superficial and approximate job at decomposing its massive strings.

extension LibSass4.Compiler {
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

extension LibSass4.Import {
    convenience init(_ importerResults: ImporterResults) {
        self.init(string: importerResults.contents,
                  fileURL: importerResults.fileURL,
                  syntax: importerResults.syntax.toLibSass)
    }
}

extension LibSass4.Compiler {
    func add(importers: [ImportResolver]) {
        importers.reversed().enumerated().forEach { x in
            add(importer: x.element, priority: x.offset)
        }
    }

    // Higher priority -> earlier in the internal list
    private func add(importer: ImportResolver, priority: Int) {

        func makeImportList( from: () throws -> LibSass4.Import?) -> LibSass4.ImportList? {
            do {
                guard let newImport = try from() else {
                    return nil
                }
                return .init(newImport)
            } catch {
                return .init(LibSass4.Import(errorMessage: String(describing: error)))
            }
        }

        switch importer {
        case .loadPath(let url):
            precondition(url.isFileURL)
            add(includePath: url.path)

        case .importer(let client):
            let newImporter = LibSass4.Importer(priority: Double(priority)) { [unowned self] url, _ in
                makeImportList {
                    try client(url, self.lastImport.absPath).flatMap {
                        LibSass4.Import($0)
                    }
                }
            }
            add(customImporter: newImporter)

        case .fileImporter(let client):
            let newImporter = LibSass4.Importer(priority: Double(priority)) { [unowned self] url, _ in
                makeImportList {
                    try client(url, self.lastImport.absPath).flatMap {
                        LibSass4.Import(fileURL: $0)
                    }
                }
            }
            add(customImporter: newImporter)
        }
    }
}
