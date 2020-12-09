//
//  AsyncCompilerTypes.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Sass
import NIO
import Foundation

/// A version of the `Importer` protocol that allows async behavior.
///
/// You can use a straight `Importer` with `EmbeddedSass.Compiler` only if the method implementations
/// are synchronous and non-blocking.  If they need to block or go async then use this protocol instead.
///
public protocol AsyncImporter: Importer {
    /// Async version of `Importer.canonicalize(importURL:)`.
    func canonicalize(eventLoop: EventLoop, importURL: String) -> EventLoopFuture<URL?>

    /// Async version of `Importer.load(canonicalURL:)`.
    func load(eventLoop: EventLoop, canonicalURL: URL) -> EventLoopFuture<ImporterResults>
}

extension AsyncImporter {
    /// Default no-op implementation of the sync version so clients don't have to write it.
    func canonicalize(importURL: String) throws -> URL? {
        preconditionFailure("Use canonicalize(eventLoop:importURL:) instead")
    }

    /// Default no-op implementation of the sync version so clients don't have to write it.
    func load(canonicalURL: URL) throws -> ImporterResults {
        preconditionFailure("Use load(eventLoop:canonicalURL:) instead")
    }
}

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
