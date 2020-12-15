//
//  AsyncCompilerTypes.swift
//  SassEmbedded
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Sass
import NIO
import Foundation

/// A version of the `Importer` protocol that allows async behavior.
///
/// You can use a straight `Importer` with `SassEmbedded.Compiler` only if the method implementations
/// are synchronous and non-blocking.  If they need to block or go async then use this protocol instead.
public protocol AsyncImporter: Importer {
    /// Async version of `Importer.canonicalize(importURL:)`.
    func canonicalize(eventLoop: EventLoop, importURL: String) -> EventLoopFuture<URL?>

    /// Async version of `Importer.load(canonicalURL:)`.
    func load(eventLoop: EventLoop, canonicalURL: URL) -> EventLoopFuture<ImporterResults>
}

public extension AsyncImporter {
    /// Default no-op implementation of the sync version so clients don't have to write it.
    func canonicalize(importURL: String) throws -> URL? {
        preconditionFailure("Use canonicalize(eventLoop:importURL:) instead")
    }

    /// Default no-op implementation of the sync version so clients don't have to write it.
    func load(canonicalURL: URL) throws -> ImporterResults {
        preconditionFailure("Use load(eventLoop:canonicalURL:) instead")
    }
}

/// A version of the`SassFunction` type that allows async behavior.
public typealias SassAsyncFunction = (EventLoop, [SassValue]) -> EventLoopFuture<SassValue>

/// A set of `SassAsyncFunction`s and their signatures.
public typealias SassAsyncFunctionMap = [SassFunctionSignature : SassAsyncFunction]

/// A  dynamic Sass function that can run asynchronously.
///
/// Use instead of `SassDynamicFunction` if your dynamic function needs to block or
/// be asynchronous.
public class SassAsyncDynamicFunction: SassDynamicFunction {
    /// The actual function.
    public let asyncFunction: SassAsyncFunction

    /// Create a new asynchronous dynamic function.
    /// - parameter signature: The Sass function signature.
    /// - parameter function: The callback implementing the function.
    public init(signature: SassFunctionSignature, function: @escaping SassAsyncFunction) {
        self.asyncFunction = function
        super.init(signature: signature) { $0[0] }
    }
}

// MARK: Importer conversion

private struct SyncImporterAdapter: AsyncImporter {
    let importer: Importer
    init(_ importer: Importer) {
        self.importer = importer
        precondition(!(importer is AsyncImporter))
    }

    func canonicalize(eventLoop: EventLoop, importURL: String) -> EventLoopFuture<URL?> {
        eventLoop.submit { try importer.canonicalize(importURL: importURL) }
    }

    func load(eventLoop: EventLoop, canonicalURL: URL) -> EventLoopFuture<ImporterResults> {
        eventLoop.submit { try importer.load(canonicalURL: canonicalURL) }
    }
}

enum AsyncImportResolver {
    case loadPath(URL)
    case importer(AsyncImporter)

    init(_ resolver: ImportResolver) {
        switch resolver {
        case .loadPath(let url):
            self = .loadPath(url)
        case .importer(let importer):
            if let asyncImporter = importer as? AsyncImporter {
                self = .importer(asyncImporter)
            } else {
                self = .importer(SyncImporterAdapter(importer))
            }
        }
    }
}

extension Array where Element == AsyncImportResolver {
    init(_ resolvers: [ImportResolver]) {
        self = resolvers.map { AsyncImportResolver($0) }
    }
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
