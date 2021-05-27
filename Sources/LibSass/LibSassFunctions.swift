//
//  LibSassFunctions.swift
//  LibSass
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import CLibSass4
import Sass

// MARK: Functions

extension LibSass4.Compiler {
    func add<S: Sequence>(functions: S) where S.Element == (key: String, value: SassFunction) {
        functions.forEach { addFunction(signature: $0.0, callback: $0.1) }
    }

    func addFunction(signature: String, callback: @escaping SassFunction) {
        let fn = LibSass4.Function(signature: signature) { args, _ in
            do {
                // LibSass always builds a list to put the args in.
                // We do this level of unpacking for the client.
                precondition(args.kind == SASS_LIST, "LibSass didn't put function args in a list?")
                let argsArray = try args.toSassValueList()
                return try callback(argsArray).toLibSassValue()
            } catch {
                return LibSass4.Value(error: String(describing: error))
            }
        }
        add(customFunction: fn)
    }
}

// MARK: Values

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

extension LibSass4.Value {
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

        case SASS_FUNCTION:
            return SassCompilerFunction(id: pointerValue)

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
    func visit(string: SassString) throws -> LibSass4.Value {
        LibSass4.Value(string: string.string, isQuoted: string.isQuoted)
    }

    func visit(number: SassNumber) throws -> LibSass4.Value {
        LibSass4.Value(number: number.double, units: number.libSassUnits)
    }

    func visit(color: SassColor) throws -> LibSass4.Value {
        LibSass4.Value(red: Double(color.red),
                      green: Double(color.green),
                      blue: Double(color.blue),
                      alpha: color.alpha)
    }

    func visit(list: SassList) throws -> LibSass4.Value {
        LibSass4.Value(values: try list.map { try $0.toLibSassValue() },
                      hasBrackets: list.hasBrackets,
                      separator: try list.separator.toLibSass())
    }

    func visit(map: SassMap) throws -> LibSass4.Value {
        LibSass4.Value(pairs: try map.dictionary.map {
            (try $0.key.toLibSassValue(), try $0.value.toLibSassValue())
        })
    }

    func visit(bool: SassBool) throws -> LibSass4.Value {
        LibSass4.Value(bool: bool.isTruthy)
    }

    func visit(null: SassNull) throws -> LibSass4.Value {
        LibSass4.Value()
    }

    func visit(compilerFunction: SassCompilerFunction) throws -> LibSass4.Value {
        LibSass4.Value(pointerValue: compilerFunction.id)
    }

    func visit(dynamicFunction: SassDynamicFunction) throws -> LibSass4.Value {
        throw ConversionError("LibSass does not support `SassDynamicFunction`s")
    }
}

private let visitor = LibSassVisitor()

extension SassValue {
    func toLibSassValue() throws -> LibSass4.Value {
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
