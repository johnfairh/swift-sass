//
//  LibSassConversion.swift
//  SassLibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import LibSass4
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
            let newImporter = LibSass.Importer(priority: Double(priority)) { [unowned self] url, _ in
                makeImportList {
                    try client(url, self.lastImport.absPath).flatMap {
                        LibSass.Import($0)
                    }
                }
            }
            add(customImporter: newImporter)

        case .fileImporter(let client):
            let newImporter = LibSass.Importer(priority: Double(priority)) { [unowned self] url, _ in
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
                let argsArray = try args.toSassValueList()
                return try callback(argsArray).toLibSassValue()
            } catch {
                return LibSass.Value(error: String(describing: error))
            }
        }
        add(customFunction: fn)
    }
}

// Values

extension SassSeparator {
    func toSeparator() throws -> SassList.Separator {
        switch self {
        case SASS_COMMA: return .comma
        case SASS_SPACE: return .space
        case SASS_UNDEF: return .undecided
        default: throw ConversionError("Unknown LibSass separator value: \(self)")
        }
    }
}

extension SassList.Separator {
    func toLibSass() throws -> SassSeparator {
        switch self {
        case .comma: return SASS_COMMA
        case .space: return SASS_SPACE
        case .undecided: return SASS_UNDEF
        case .slash: throw ConversionError("LibSass does not support slash-separated lists")
        }
    }
}

/// Thrown if something isn't representable or unknown.
/// Messages end up failing a compilation as a custom function fails.
fileprivate struct ConversionError: Swift.Error, CustomStringConvertible {
    let description: String
    init(_ text: String) {
        description = text
    }
}

extension LibSass.Value {
    func toSassValue() throws -> SassValue {
        switch kind {
        case SASS_BOOLEAN:
            return boolValue ? SassConstants.true : SassConstants.false

        case SASS_NULL:
            return SassConstants.null

        case SASS_STRING:
            return SassString(stringValue, isQuoted: stringIsQuoted)

        case SASS_NUMBER:
            let units = numberUnits.parseUnits()
            return try SassNumber(numberValue, numeratorUnits: units.0, denominatorUnits: units.1)

        case SASS_COLOR:
            return try SassColor(red: Int(colorRed), green: Int(colorGreen), blue: Int(colorBlue), alpha: colorAlpha)

        case SASS_LIST:
            return SassList(try toSassValueList(),
                            separator: try listSeparator.toSeparator(),
                            hasBrackets: listHasBrackets)

        case SASS_MAP:
            return SassMap(try toSassValueDictionary())

//        needs full-width SassCompilerFunction index
//        case SASS_FUNCTION:
//            return SassCompilerFunction(id: pointerValue)

        default:
            throw ConversionError("Unknown LibSass value tag: \(kind)")
        }
    }

    func toSassValueList() throws -> [SassValue] {
        try (0..<listSize).map { try self[$0].toSassValue() }
    }

    func toSassValueDictionary() throws -> [SassValue : SassValue] {
        var dict = [SassValue : SassValue]()
        let it = mapIterator
        while !it.isExhausted {
            dict[try it.key.toSassValue()] = try it.value.toSassValue()
            it.next()
        }
        return dict
    }
}

struct LibSassVisitor: SassValueVisitor {
    func visit(string: SassString) throws -> LibSass.Value {
        LibSass.Value(string: string.string, isQuoted: string.isQuoted)
    }

    func visit(number: SassNumber) throws -> LibSass.Value {
        LibSass.Value(number: number.double, units: number.libSassUnits)
    }

    func visit(color: SassColor) throws -> LibSass.Value {
        LibSass.Value(red: Double(color.red),
                      green: Double(color.green),
                      blue: Double(color.blue),
                      alpha: color.alpha)
    }

    func visit(list: SassList) throws -> LibSass.Value {
        LibSass.Value(values: try list.map { try $0.toLibSassValue() },
                      hasBrackets: list.hasBrackets,
                      separator: try list.separator.toLibSass())
    }

    func visit(map: SassMap) throws -> LibSass.Value {
        LibSass.Value(pairs: try map.dictionary.map {
            (try $0.key.toLibSassValue(), try $0.value.toLibSassValue())
        })
    }

    func visit(bool: SassBool) throws -> LibSass.Value {
        LibSass.Value(bool: bool.isTruthy)
    }

    func visit(null: SassNull) throws -> LibSass.Value {
        LibSass.Value()
    }

    func visit(compilerFunction: SassCompilerFunction) throws -> LibSass.Value {
//        needs fullwidth SassCompilerFunction index
//        LibSass.Value(pointerValue: compilerFunction.id)
        throw ConversionError("TODO")
    }

    func visit(dynamicFunction: SassDynamicFunction) throws -> LibSass.Value {
        throw ConversionError("LibSass does not support `SassDynamicFunction`s")
    }
}

private let visitor = LibSassVisitor()

extension SassValue {
    func toLibSassValue() throws -> LibSass.Value {
        try accept(visitor: visitor)
    }
}

// oh boy

private extension String {
    func parseUnits() -> ([String], [String]) {
        var units = self
        if units.hasSuffix("^-1") {
            units.removeLast(3)
            return ([], units.asUnitList)
        }
        let parts = units.split(separator: "/")
        switch parts.count {
        case 0, 1: return (units.asUnitList, [])
        default: return (String(parts[0]).asUnitList, String(parts[1]).asUnitList)
        }
    }

    var asUnitList: [String] {
        split(whereSeparator: { c in "()*".contains(c) }).map(String.init)
    }
}

extension SassNumber {
    var libSassUnits: String {
        numeratorUnits.joined(separator: "*") +
            "/" +
            denominatorUnits.joined(separator: "*")
    }
}
