//
//  AsyncFunctionTypes.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Sass
import NIOCore

// Xcode 13.2 Swift 5.5 workarounds for macOS 11 concurrency ...

extension EventLoopFuture {
    /// Get the value/error from an `EventLoopFuture` in an `async` context.
    ///
    /// This function can be used to bridge an `EventLoopFuture` into the `async` world. Ie. if you're in an `async`
    /// function and want to get the result of this future.
    @available(macOS 11, *)
    @inlinable
    public func get() async throws -> Value {
        return try await withUnsafeThrowingContinuation { cont in
            self.whenComplete { result in
                switch result {
                case .success(let value):
                    cont.resume(returning: value)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

extension EventLoopGroup {
    /// Shuts down the event loop gracefully.
    @available(macOS 11, *)
    @inlinable
    public func shutdownGracefully() async throws {
        return try await withCheckedThrowingContinuation { cont in
            self.shutdownGracefully { error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }
}

extension EventLoopPromise {
    /// Complete a future with the result (or error) of the `async` function `body`.
    ///
    /// This function can be used to bridge the `async` world into an `EventLoopPromise`.
    ///
    /// - parameters:
    ///   - body: The `async` function to run.
    /// - returns: A `Task` which was created to `await` the `body`.
    @available(macOS 11, *)
    @discardableResult
    @inlinable
    public func completeWithTask(_ body: @escaping @Sendable () async throws -> Value) -> Task<Void, Never> {
        Task {
            do {
                let value = try await body()
                self.succeed(value)
            } catch {
                self.fail(error)
            }
        }
    }
}

// MARK: Content


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

func AsyncFunctionAdapter(_ fn: @escaping SassAsyncFunction) -> SassAsyncFunctionNIO {
    { eventLoop, args in
        let promise = eventLoop.makePromise(of: SassValue.self)
        promise.completeWithTask {
            try await fn(args)
        }
        return promise.futureResult
    }
}

extension SassAsyncFunctionNIOMap {
    init(_ sync: SassFunctionMap) {
        self = sync.mapValues { SyncFunctionAdapter($0) }
    }

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
