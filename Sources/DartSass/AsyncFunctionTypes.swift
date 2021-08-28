//
//  AsyncFunctionTypes.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Sass
import NIO

/// A version of the `SassFunction` type that allows async behavior.
public typealias SassAsyncFunction = @Sendable ([SassValue]) async throws -> SassValue

/// A set of `SassAsyncFunction`s and their signatures.
public typealias SassAsyncFunctionMap = [SassFunctionSignature : SassAsyncFunction]

/// A version of the `SassFunction` type that allows async behavior using NIO.
public typealias SassAsyncFunctionNIO = @Sendable (EventLoop, [SassValue]) -> EventLoopFuture<SassValue>

/// A set of `SassAsyncFunctionNIO`s and their signatures.
public typealias SassAsyncFunctionNIOMap = [SassFunctionSignature : SassAsyncFunctionNIO]

/// Wrapper for various types of functions
/// @unchecked because SwiftLang  #38669 is not landed yet
public enum SassFunctions: @unchecked Sendable {
    /// Functions that run synchronously
    case sync(SassFunctionMap)
    /// Functions defined using async-await
    case async(SassAsyncFunctionMap)
    /// Functions using NIO
    case asyncNIO(SassAsyncFunctionNIOMap)
}

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

/// A  dynamic Sass function that can run asynchronously using NIO.
///
/// Use instead of `SassDynamicFunction` with `DartSass.Compiler` if your dynamic function
/// needs to block or be asynchronous using NIO.
public class SassAsyncDynamicFunctionNIO: SassDynamicFunction {
    // MARK: Initializers

    /// Create a new asynchronous dynamic function.
    /// - parameter signature: The Sass function signature.
    /// - parameter function: The callback implementing the function.
    public init(signature: SassFunctionSignature, function: @escaping SassAsyncFunctionNIO) {
        self.asyncFunction = function
        super.init(signature: signature) { $0[0] }
    }

    // MARK: Properties

    /// The actual function.
    public let asyncFunction: SassAsyncFunctionNIO
}


// MARK: Function conversion

func SyncFunctionAdapter(_ fn: @escaping SassFunction) -> SassAsyncFunctionNIO {
    { eventLoop, args in
        eventLoop.submit { try fn(args) }
    }
}

@available(macOS 12, *)
func AsyncFunctionAdapter(_ fn: @escaping SassAsyncFunction) -> SassAsyncFunctionNIO {
    { eventLoop, args in
        let promise = eventLoop.makePromise(of: SassValue.self)
        promise.completeWithAsync {
            try await fn(args)
        }
        return promise.futureResult
    }
}

extension SassAsyncFunctionNIOMap {
    init(_ sync: SassFunctionMap) {
        self = sync.mapValues { SyncFunctionAdapter($0) }
    }

    @available(macOS 12, *)
    init(_ sync: SassAsyncFunctionMap) {
        self = sync.mapValues { AsyncFunctionAdapter($0) }
    }

    init(_ bundle: SassFunctions) {
        self = [:]
        switch bundle {
        case .sync(let map):
            self.init(map)
        case .async(let map):
            if #available(macOS 12, *) {
                self.init(map)
            }
        case .asyncNIO(let map):
            self = map
        }
    }
}
