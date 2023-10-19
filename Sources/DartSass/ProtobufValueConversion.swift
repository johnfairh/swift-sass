//
//  ProtobufValueConversion.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// Helpers to shuffle data between the protobuf and SassValue types.

@_spi(SassCompilerProvider) import Sass

// MARK: SassValueMonitor

// Some stuff to handle requirements introduced by 'argument list', basically
// side-effects of access to the value types.

final class SassValueMonitor {
    typealias ArgListAccessFn = (UInt32) -> Void
    var argListAccess: ArgListAccessFn
    init(_ argListAccess: @escaping ArgListAccessFn = { _ in }) {
        self.argListAccess = argListAccess
    }

    static func with<T>(_ accessFn: @escaping ArgListAccessFn, work: () throws -> T) rethrows -> T {
        try $current.withValue(SassValueMonitor(accessFn), operation: work)
    }

    @TaskLocal static var current = SassValueMonitor()
}

extension Sass_EmbeddedProtocol_Value {
    var monitor: SassValueMonitor {
        SassValueMonitor.current
    }
}

// MARK: SassValue conversion

// Protobuf -> SassValue

extension SassList.Separator {
    init(_ separator: Sass_EmbeddedProtocol_ListSeparator) throws {
        switch separator {
        case .comma: self = .comma
        case .slash: self = .slash
        case .space: self = .space
        case .undecided: self = .undecided
        case .UNRECOGNIZED(let u):
            throw ProtocolError("Unrecognized list separator: \(u)")
        }
    }
}

extension SassCalculation {
    convenience init(_ proto: Sass_EmbeddedProtocol_Value.Calculation) throws {
        guard let kind = Kind(rawValue: proto.name) else {
            throw ProtocolError("Unknown Calculation name '\(proto.name)'")
        }
        try self.init(kind: kind, arguments: proto.arguments.map { try .init($0) })
    }
}

extension SassCalculation.Operator {
    init(_ proto: Sass_EmbeddedProtocol_CalculationOperator) throws {
        switch proto {
        case .plus: self = .plus
        case .minus: self = .minus
        case .times: self = .times
        case .divide: self = .dividedBy
        case .UNRECOGNIZED(let u):
            throw ProtocolError("Unknown Calculation operator '\(proto)' '\(u)'")
        }
    }
}

extension SassCalculation.Value {
    init(_ proto: Sass_EmbeddedProtocol_Value.Calculation.CalculationValue) throws {
        switch proto.value {
        case .number(let n):
            self = .number(try SassNumber(n))

        case .string(let s):
            self = .string(s)

        case .interpolation(let s):
            self = .interpolation(s)

        case .operation(let o):
            self = try .operation(.init(o.left), .init(o.operator), .init(o.right))

        case .calculation(let c):
            self = .calculation(try .init(c))

        case nil:
            throw ProtocolError("Unexpected missing CalculationValue")
        }
    }
}

extension SassNumber {
    convenience init(_ proto: Sass_EmbeddedProtocol_Value.Number) throws {
        try self.init(proto.value,
                      numeratorUnits: proto.numerators,
                      denominatorUnits: proto.denominators)
    }
}

extension Sass_EmbeddedProtocol_Value {
    func asSassValue() throws -> SassValue {
        switch value {
        case .string(let m):
            return SassString(m.text, isQuoted: m.quoted)

        case .number(let n):
            return try SassNumber(n)

        case .rgbColor(let c):
            return try SassColor(red: Int(c.red),
                                 green: Int(c.green),
                                 blue: Int(c.blue),
                                 alpha: c.alpha)

        case .hslColor(let c):
            return try SassColor(hue: c.hue,
                                 saturation: c.saturation,
                                 lightness: c.lightness,
                                 alpha: c.alpha)

        case .hwbColor(let c):
            return try SassColor(hue: c.hue,
                                 whiteness: c.whiteness,
                                 blackness: c.blackness,
                                 alpha: c.alpha)

        case .list(let l):
            return try SassList(l.contents.map { try $0.asSassValue() },
                                separator: .init(l.separator),
                                hasBrackets: l.hasBrackets_p)

        case .argumentList(let l):
            let monitorFn = monitor.argListAccess
            return try SassArgumentList(l.contents.map { try $0.asSassValue() },
                                        keywords: l.keywords.mapValues { try $0.asSassValue() },
                                        keywordsObserver: { monitorFn(l.id) },
                                        separator: .init(l.separator))

        case .map(let m):
            var dict = [SassValue: SassValue]()
            try m.entries.forEach { entry in
                let key = try entry.key.asSassValue()
                let value = try entry.value.asSassValue()
                guard dict[key] == nil else {
                    throw ProtocolError("Bad map from compiler, duplicate key \(key).")
                }
                dict[key] = value
            }
            return SassMap(dict)

        case .singleton(let s):
            switch s {
            case .false: return SassConstants.false
            case .true: return SassConstants.true
            case .null: return SassConstants.null
            case .UNRECOGNIZED(let i):
                throw ProtocolError("Unknown singleton type \(i)")
            }

        case .compilerFunction(let c):
            return SassCompilerFunction(id: Int(c.id))

        case .calculation(let c):
            return try SassCalculation(c)

        case .hostFunction(let h):
            // not supposed to receive these in arguments
            throw ProtocolError("Don't know how to deserialize hostfunction \(h)")

        case .compilerMixin:
            preconditionFailure("Unsupported CompilerMixin") // XXX

        case nil:
            throw ProtocolError("Missing SassValue type.")
        }
    }
}

// SassValue -> Protobuf

extension Sass_EmbeddedProtocol_ListSeparator {
    init(_ separator: SassList.Separator) {
        switch separator {
        case .comma: self = .comma
        case .slash: self = .slash
        case .space: self = .space
        case .undecided: self = .undecided
        }
    }
}

extension Sass_EmbeddedProtocol_CalculationOperator {
    init(_ op: SassCalculation.Operator) {
        switch op {
        case .plus: self = .plus
        case .minus: self = .minus
        case .times: self = .times
        case .dividedBy: self = .divide
        }
    }
}

extension Sass_EmbeddedProtocol_Value.Calculation.CalculationValue {
    init(_ val: SassCalculation.Value) {
        switch val {
        case .number(let n):
            self.number = .init(n)
        case .string(let s):
            self.string = s
        case .interpolation(let s):
            self.interpolation = s
        case .operation(let l, let o, let r):
            self.operation = .with {
                $0.left = .init(l)
                $0.operator = .init(o)
                $0.right = .init(r)
            }
        case .calculation(let c):
            self.calculation = .init(c)
        }
    }
}

extension Sass_EmbeddedProtocol_Value.Calculation {
    init(_ calc: SassCalculation) {
        self = .with {
            $0.name = calc.kind.rawValue
            $0.arguments = calc.arguments.map { .init($0) }
        }
    }
}

extension Sass_EmbeddedProtocol_Value.Number {
    init(_ number: SassNumber) {
        self = .with {
            $0.value = number.double
            $0.numerators = number.numeratorUnits
            $0.denominators = number.denominatorUnits
        }
    }
}

extension Sass_EmbeddedProtocol_Value: SassValueVisitor {
    func visit(string: SassString) throws -> OneOf_Value {
        .string(.with {
            $0.text = string.string
            $0.quoted = string.isQuoted
        })
    }

    func visit(number: SassNumber) throws -> OneOf_Value {
        .number(.init(number))
    }

    func visit(color: SassColor) throws -> OneOf_Value {
        switch color.preferredFormat {
        case .rgb:
            return .rgbColor(.with {
                $0.red = UInt32(color.red)
                $0.green = UInt32(color.green)
                $0.blue = UInt32(color.blue)
                $0.alpha = color.alpha
            })
        case .hsl:
            return .hslColor(.with {
                $0.hue = color.hue
                $0.saturation = color.saturation
                $0.lightness = color.lightness
                $0.alpha = color.alpha
            })
        case .hwb:
            return .hwbColor(.with {
                $0.hue = color.hue
                $0.whiteness = color.whiteness
                $0.blackness = color.blackness
                $0.alpha = color.alpha
            })
        }
    }

    func visit(list: SassList) throws -> OneOf_Value {
        .list(.with {
            $0.separator = .init(list.separator)
            $0.hasBrackets_p = list.hasBrackets
            $0.contents = list.map { .init($0) }
        })
    }

    func visit(argumentList: SassArgumentList) throws -> OneOf_Value {
        .argumentList(.with {
            // id / keywords access, an essay:
            // We're really creating a _new_ ArgList here, that sure may
            // be copied wholesale from something the compiler gave us, so
            // we set id=0 and don't worry about accessing the keywords: even
            // if the user is passing back an ArgList, they could just as well
            // be copying it manually themselves which would trigger the callback.
            $0.id = 0
            $0.separator = .init(argumentList.separator)
            $0.contents = argumentList.map { .init($0) }
            $0.keywords = argumentList.keywords.mapValues { .init($0) }
        })
    }

    func visit(map: SassMap) throws -> OneOf_Value {
        .map(.with { mapVal in
            mapVal.entries = map.dictionary.map { kv in
                .with {
                    $0.key = .init(kv.key)
                    $0.value = .init(kv.value)
                }
            }
        })
    }

    func visit(bool: SassBool) throws -> OneOf_Value {
        .singleton(bool.value ? .true : .false)
    }

    func visit(null: SassNull) throws -> OneOf_Value {
        .singleton(.null)
    }

    func visit(compilerFunction: SassCompilerFunction) throws -> OneOf_Value {
        .compilerFunction(.with {
            $0.id = UInt32(compilerFunction.id)
        })
    }

    func visit(dynamicFunction: SassDynamicFunction) throws -> OneOf_Value {
        .hostFunction(.with {
            $0.id = dynamicFunction.id
            $0.signature = dynamicFunction.signature
        })
    }

    func visit(calculation: SassCalculation) throws -> OneOf_Value {
        .calculation(.init(calculation))
    }

    init(_ val: SassValue) {
        self.value = try! val.accept(visitor: self)
    }
}
