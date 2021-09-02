//
//  DynamicFunction.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Dispatch

struct Lock {
    private let dsem: DispatchSemaphore

    init() {
        dsem = DispatchSemaphore(value: 1)
    }

    func locked<T>(_ call: () throws -> T) rethrows -> T {
        dsem.wait()
        defer { dsem.signal() }
        return try call()
    }
}

/// Dynamic function IDs have to be unique across all compilations, wrap that  up here.
/// Paranoid about multithreading especially in a NIO world so lock things.
///
/// All dispatch etc. is pushed back to the compiler module so that subclasses of `DynamicFunction`
/// can get handled properly.
///
/// Bit thorny that refs here stay around forever but unclear what is safe.
private struct DynamicFunctionRuntime {
    private let lock = Lock()
    private var idCounter = UInt32(2000)
    private var functions = [UInt32 : SassDynamicFunction]()

    mutating func allocateID() -> UInt32 {
        lock.locked {
            idCounter += 1
            return idCounter
        }
    }

    mutating func register(_ fn: SassDynamicFunction) {
        lock.locked {
            functions[fn.id] = fn
        }
    }

    func lookUp(id: UInt32) -> SassDynamicFunction? {
        lock.locked {
            functions[id]
        }
    }
}

private var runtime = DynamicFunctionRuntime()

/// A dynamic Sass function.
///
/// These are Sass functions, written in Swift, that are not declared up-front to the compiler when
/// starting compilation.  Instead they are returned as `SassValue`s from other `SassFunction`s
/// (that _were_ declared up-front) so the compiler can call them later on.
///
/// Use `SassAsyncDynamicFunction` instead if your function is blocking and you want to use it with
/// `DartSass.Compiler`.
open class SassDynamicFunction: SassValue {
    // MARK: Initializers

    /// Create a new dynamic function.
    /// - parameter signature: The Sass function signature.
    /// - parameter function: The callback implementing the function.
    ///
    /// The runtime holds a reference to all created `SassDynamicFunction`s so they never reach `deinit`.
    public init(signature: SassFunctionSignature, function: @escaping SassFunction) {
        self.signature = signature
        self.function = function
        self.id = runtime.allocateID()
        super.init()
        runtime.register(self)
    }

    // MARK: Properties

    /// The Sass signature of the function.
    public let signature: String
    /// The actual function.
    public let function: SassFunction
    /// The ID of the function, used by the Sass compiler to refer to it.
    public let id: UInt32

    // MARK: Misc

    /// Dynamic functions are equal if they have the same ID.
    public static func == (lhs: SassDynamicFunction, rhs: SassDynamicFunction) -> Bool {
        lhs.id == rhs.id
    }

    /// Hash the dynamic function
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(dynamicFunction: self)
    }

    public override var description: String {
        "DynamicFunction(\(id) \(signature))"
    }

    /// API from a compiler implementation to understand how to handle a request for a host function
    /// received from the compiler.  :nodoc:
    @_spi(SassCompilerProvider)
    public static func lookUp(id: UInt32) -> SassDynamicFunction? {
        runtime.lookUp(id: id)
    }
}

extension SassValue {
    /// Reinterpret the value as a dynamic function.
    /// - throws: `SassFunctionError.wrongType(...)` if it isn't a compiler function.
    public func asDynamicFunction() throws -> SassDynamicFunction {
        guard let selfDynamicFunction = self as? SassDynamicFunction else {
            throw SassFunctionError.wrongType(expected: "SassDynamicFunction", actual: self)
        }
        return selfDynamicFunction
    }
}
