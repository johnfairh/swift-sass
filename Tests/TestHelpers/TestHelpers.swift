//
//  TestHelpers.swift
//  TestHelpers
//
//  Copyright 2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

// Misc stuff to help with file IO tests

extension String {
    public func write(to url: URL) throws {
        try write(toFile: url.path, atomically: false, encoding: .utf8)
    }
}

extension FileManager {
    public func createTempFile(filename: String, contents: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: url)
        return url
    }

    /// Create a new empty temporary directory.  Caller must delete.
    public func createTemporaryDirectory(inDirectory directory: URL? = nil, name: String? = nil) throws -> URL {
        let directoryName = name ?? UUID().uuidString
        let parentDirectoryURL = directory ?? temporaryDirectory
        let directoryURL = parentDirectoryURL.appendingPathComponent(directoryName)
        try createDirectory(at: directoryURL, withIntermediateDirectories: false)
        return directoryURL
    }

    public static func preservingCurrentDirectory<T>(_ code: () throws -> T) rethrows -> T {
        let fileManager = FileManager.default
        let cwd = fileManager.currentDirectoryPath
        defer {
            let rc = fileManager.changeCurrentDirectoryPath(cwd)
            precondition(rc)
        }
        return try code()
    }
}

extension URL {
    public func withCurrentDirectory<T>(code: () throws -> T) throws -> T {
        try FileManager.preservingCurrentDirectory {
            FileManager.default.changeCurrentDirectoryPath(path)
            return try code()
        }
    }
}
