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

extension LibSass.Compiler {
    func add(importer: ImportResolver) {
        switch importer {
        case .importer:
            preconditionFailure("Sass.Importer not supported with LibSass, use LibSassImporter")

        case .loadPath(let url):
            precondition(url.isFileURL)
            add(includePath: url.path)

        case .libSassImporter(let client):
            let newImporter = LibSass.Importer(priority: 1.0) { url, _, _ in
                let newImport: LibSass.Import
                do {
                    guard let results = try client.load(ruleURL: url,
                                                        contextFileURL: URL(fileURLWithPath: self.lastImport.absPath)) else {
                        return nil
                    }
                    newImport = LibSass.Import(string: results.contents,
                                               fileURL: results.sourceMapURL,
                                               syntax: results.syntax.toLibSass)
                } catch {
                    newImport = LibSass.Import(errorMessage: String(describing: error))
                }
                let list = LibSass.ImportList()
                list.push(import: newImport)
                return list
            }
            add(customImporter: newImporter)
        }
    }
}
