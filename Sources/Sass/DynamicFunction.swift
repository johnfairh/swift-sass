//
//  DynamicFunction.swift
//  Sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

/// Dynamic function IDs have to be unique across all compilations, wrap that  up here.
/// Paranoid about multithreading especially in a NIO world so lock things.
///
/// All dispatch etc. is pushed back to the compiler module so that subclasses of `DynamicFunction`
/// can get handled properly.
///
/// Bit thorny that refs here stay around forever but unclear what is safe.
private struct DynamicFunctionRuntime {
    let mutex = NSLock()
    var idCounter = UInt32(2000)
    var functions = [UInt32 : SassDynamicFunction]()

    var nextID: UInt32 {
        mutex.lock()
        defer { mutex.unlock() }
        return idCounter + 1
    }

    mutating func register(_ fn: SassDynamicFunction) {
        mutex.lock()
        defer { mutex.unlock() }
        functions[fn.id] = fn
    }

    func lookUp(id: UInt32) -> SassDynamicFunction? {
        mutex.lock()
        defer { mutex.unlock() }
        return functions[id]
    }
}

private var runtime = DynamicFunctionRuntime()

/// API from a compiler implementation to understand how to handle a request for a host function
/// received from the compiler.  :nodoc:
public func _lookUpDynamicFunction(id: UInt32) -> SassDynamicFunction? {
    runtime.lookUp(id: id)
}

/// A dynamic Sass function.
///
/// These are Sass functions, written in Swift, that are not declared up-front to the compiler when
/// starting compilation.  Instead they are returned as `SassValue`s from other (up-front declared!)
/// `SassFunction`s so the compiler can call them later on.
open class SassDynamicFunction: SassValue {
    /// The Sass signature of the function.
    public let signature: String
    /// The actual function.
    public let function: SassFunction
    /// The ID of the function, used by the compiler to refer to it.
    public let id: UInt32

    /// Create a new dynamic function.
    /// - parameter signature: The Sass function signature.  This is some text that can appear
    ///   after `@function` in a Sass stylesheet, such as `mix($color1, $color2, $weight: 50%)`.
    /// - parameter function: The callback implementing the function.
    public init(signature: String, function: @escaping SassFunction) {
        self.signature = signature
        self.function = function
        self.id = runtime.nextID
        super.init()
        runtime.register(self)
    }

    /// Take part in the `SassValueVisitor` protocol.
    public override func accept<V, R>(visitor: V) throws -> R where V : SassValueVisitor, R == V.ReturnType {
        try visitor.visit(dynamicFunction: self)
    }

    public override var description: String {
        "DynamicFunction(\(id) \(signature))"
    }

    /// Compiler functions are equal if they have the same ID and apply to the same compilation.
    /// We only test the first part of that so watch out.
    public static func == (lhs: SassDynamicFunction, rhs: SassDynamicFunction) -> Bool {
        lhs.id == rhs.id
    }

    /// Hash the compiler function
    public override func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension SassValue {
    /// Reinterpret the value as a compiler function.
    /// - throws: `SassTypeError` if it isn't a compiler function.
    public func asDynamicFunction() throws -> SassDynamicFunction {
        guard let selfDynamicFunction = self as? SassDynamicFunction else {
            throw SassValueError.wrongType(expected: "SassDynamicFunction", actual: self)
        }
        return selfDynamicFunction
    }
}
