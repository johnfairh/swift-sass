//
//  Exec.swift
//  TMLMisc -> SourceKittenFramework -> BebopLib -> EmbeddedSass
//
//  Copyright © 2019 SourceKitten. All rights reserved.
//  Copyright 2020 Bebop Authors
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

//
// Firstly some 'orrible gubbins to deal with SIGPIPE, which
// happens if the child process dies.
//
// We're a library so can't just mask it off globally.
//
// So available techniques are pthread_sigmask(3) and FD-centric options.
// I'm more confident about getting the FD approach working solidly on
// Darwin so we do that.
//
// Darwin: has SO_NOSIGPIPE on setsockopt(2)
// Linux: has MSG_NOSIGNAL on send(2)
//        Actually Darwin has MSG_NOSIGNAL in the header file under a weird
//        ifdef, but it's not in the man page: leave it out.
//
// Include socket FD reader and writer APIs -- the official ones that look
// like they might be safe require a Big Sur deployment target.  And probably
// won't understand MSG_NOSIGNAL.
//

import Foundation

/// Create a pair of connected sockets in PF_LOCAL.
///
/// Set `NO_SIGPIPE` on supported platforms.
///
/// The connection is bidirectional but the sockets are named `reader` and `writer` to
/// make it easier to reason about their use.
struct SocketPipe {
    let reader: FileHandle
    let writer: FileHandle

    init() {
        var fds: [Int32] = [0, 0]
        #if os(Linux)
        let sockStream = Int32(SOCK_STREAM.rawValue)
        #else
        let sockStream = SOCK_STREAM
        #endif // such anger
        let rc = socketpair(PF_LOCAL, sockStream, 0, &fds)
        precondition(rc == 0, "socketpair(2) failed errno=\(errno)")
        #if os(macOS)
        fds.forEach { fd in
            var opt = UInt32(1)
            let rc = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, UInt32(MemoryLayout<Int32>.size))
            precondition(rc == 0, "setsockopt(2) failed errno=\(errno)")
        }
        #endif
        reader = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
        writer = FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
        // Not obvious this `closeOnDealloc` works - see `Exec.spawn(...)`.
    }
}

extension FileHandle {
    /// Send data to a socket.  Set `MSG_NOSIGNAL` on supported platforms.
    func sockSend(_ bytes: UnsafeRawPointer, count: Int) -> Int {
        #if os(macOS)
        return send(fileDescriptor, bytes, count, 0)
        #elseif os(Linux)
        return send(fileDescriptor, bytes, count, Int32(MSG_NOSIGNAL))
        #endif
    }

    /// Read data from a socket.
    func sockRecv(_ bytes: UnsafeMutableRawPointer, count: Int) -> Int {
        recv(fileDescriptor, bytes, count, Int32(MSG_WAITALL))
    }
}

/// Namespace for utilities to execute a child process.
enum Exec {
    /// How to handle stderr output from the child process.
    enum Stderr {
        /// Treat stderr same as parent process.
        case inherit
        /// Send stderr to /dev/null.
        case discard
        /// Merge stderr with stdout.
        case merge
    }

    /// The result of running the child process.
    struct Results {
        /// The command that was run
        let command: String
        /// Its arguments
        let arguments: [String]
        /// The process's exit status.
        let terminationStatus: Int32
        /// The data from stdout and optionally stderr.
        let data: Data
        /// The `data` reinterpreted as a string with whitespace trimmed; `nil` for the empty string.
        var string: String? {
            let encoded = String(data: data, encoding: .utf8) ?? ""
            let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        /// The `data` reinterpreted as a string but intercepted to `nil` if the command actually failed
        var successString: String? {
            guard terminationStatus == 0 else {
                return nil
            }
            return string
        }
        /// Some text explaining a failure
        var failureReport: String {
            var report = """
            Command failed: \(command)
            Arguments: \(arguments)
            Exit status: \(terminationStatus)
            """
            if let output = string {
                report += ", output:\n\(output)"
            }
            return report
        }
    }

    /**
    Run a command with arguments and return its output and exit status.

    - parameter command: Absolute path of the command to run.
    - parameter arguments: Arguments to pass to the command.
    - parameter currentDirectory: Current directory for the command.  By default
                                  the parent process's current directory.
    - parameter stderr: What to do with stderr output from the command.  By default
                        whatever the parent process does.
    */
    static func run(_ command: String,
                    _ arguments: String...,
                    currentDirectory: String = FileManager.default.currentDirectoryPath,
                    stderr: Stderr = .inherit) -> Results {
        return run(command, arguments, currentDirectory: currentDirectory, stderr: stderr)
    }

    /**
     Run a command with arguments and return its output and exit status.

     - parameter command: Absolute path of the command to run.
     - parameter arguments: Arguments to pass to the command.
     - parameter currentDirectory: Current directory for the command.  By default
                                   the parent process's current directory.
     - parameter stderr: What to do with stderr output from the command.  By default
                         whatever the parent process does.
     */
     static func run(_ command: String,
                     _ arguments: [String] = [],
                     currentDirectory: String = FileManager.default.currentDirectoryPath,
                     stderr: Stderr = .inherit) -> Results {
        let process = Process()
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe

        switch stderr {
        case .discard:
            // FileHandle.nullDevice does not work here, as it consists of an invalid file descriptor,
            // causing process.launch() to abort with an EBADF.
            process.standardError = FileHandle(forWritingAtPath: "/dev/null")!
        case .merge:
            process.standardError = pipe
        case .inherit:
            break
        }

        do {
          process.executableURL = URL(fileURLWithPath: command)
          process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
          try process.run()
        } catch {
            return Results(command: command, arguments: arguments, terminationStatus: -1, data: Data())
        }

        let fd = pipe.fileHandleForReading
        return Child(process: process, stdin: fd, stdout: fd).await()
    }

    /// Start an asynchrous child process.
    ///
    /// - parameter command: Absolute path of the command to run
    /// - parameter arguments: Arguments to pass to the command
    /// - parameter currentDirectory: Current directory for the command.  By default
    ///                               the parent process's current directory.
    ///
    /// - throws: Whatever `Process.run()` does if the command is bad.
    /// - returns: `Exec.Child` for the child process.
    ///
    /// Stderr of the child process is discarded because I don't want it rn.
    static func spawn(_ command: URL,
                      _ arguments: [String] = [],
                      currentDirectory: String = FileManager.default.currentDirectoryPath) throws -> Child {
        let process = Process()
        process.arguments = arguments

        let stdoutPipe = SocketPipe()
        let stdinPipe = SocketPipe()

        process.standardOutput = stdoutPipe.writer
        process.standardInput = stdinPipe.reader
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")!

        process.executableURL = command
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        try process.run()
        // Close our copy of the child's FDs.
        // `FileHandle` claims to do this for us but it either doesn't work or is
        // too clever to be useful.
        try stdoutPipe.writer.close()
        try stdinPipe.reader.close()

        return Child(process: process, stdin: stdinPipe.writer, stdout: stdoutPipe.reader)
    }

    /// A running child process.
    ///
    /// When the last reference to this object is released the `await()` method is called
    /// to block for termination -- we take no action to ensure this termination though.
    final class Child {
        /// The `Process` object for the child
        let process: Process
        /// The child's `stdin`.  Write to it.
        let standardInput: FileHandle
        /// The child's `stdout`.  Read from it.
        let standardOutput: FileHandle

        init(process: Process, stdin: FileHandle, stdout: FileHandle) {
            self.process = process
            self.standardInput = stdin
            self.standardOutput = stdout
        }

        /// Block until the process terminates and report status.
        func await() -> Results {
            let data = standardOutput.readDataToEndOfFile()
            process.waitUntilExit()
            return Results(command: process.executableURL?.path ?? "",
                           arguments: process.arguments ?? [],
                           terminationStatus: process.terminationStatus,
                           data: data)
        }

        deinit {
            _ = await()
        }
    }
}
