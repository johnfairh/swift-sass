//
//  AsyncFunctionTypes.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Sass

/// A version of the `SassFunction` type that allows async behavior.
public typealias SassAsyncFunction = @Sendable ([SassValue]) async throws -> SassValue

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
    { args in try await Task { try fn(args) }.value }
}
