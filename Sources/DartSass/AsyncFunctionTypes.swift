//
//  AsyncFunctionTypes.swift
//  DartSass
//
//  Copyright 2020-2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Sass
import NIO

/// A version of the `SassFunction` type that allows async behavior.
public typealias SassAsyncFunction = (EventLoop, [SassValue]) -> EventLoopFuture<SassValue>

/// A set of `SassAsyncFunction`s and their signatures.
public typealias SassAsyncFunctionMap = [SassFunctionSignature : SassAsyncFunction]

/// A  dynamic Sass function that can run asynchronously.
///
/// Use instead of `SassDynamicFunction` with `DartSass.Compiler` if your dynamic function
/// needs to block or be asynchronous.
public class SassAsyncDynamicFunction: SassDynamicFunction {
    // MARK: Initializers

    /// Create a new asynchronous dynamic function.
    /// - parameter signature: The Sass function signature.
    /// - parameter function: The callback implementing the function.
    public init(signature: SassFunctionSignature, function: @escaping SassAsyncFunction) {
        self.asyncFunction = function
        super.init(signature: signature) { $0[0] }
    }

    // MARK: Properties

    /// The actual function.
    public let asyncFunction: SassAsyncFunction
}

// MARK: Function conversion

func SyncFunctionAdapter(_ fn: @escaping SassFunction) -> SassAsyncFunction {
    { eventLoop, args in
        eventLoop.submit { try fn(args) }
    }
}

extension SassAsyncFunctionMap {
    init(_ sync: SassFunctionMap) {
        self.init()
        sync.forEach { kv in
            self[kv.key] = SyncFunctionAdapter(kv.value)
        }
    }
}
