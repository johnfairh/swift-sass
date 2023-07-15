//
//  Exec.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import Foundation

// Unix layer of running the child process

/// Create a pair of connected sockets in PF_LOCAL.
private struct SocketPipe {
    let reader: CInt
    let writer: CInt

    init() {
        var fds: [CInt] = [0, 0]
        #if os(Linux)
        let sockStream = CInt(SOCK_STREAM.rawValue)
        #else
        let sockStream = SOCK_STREAM
        #endif // such anger
        let rc = socketpair(PF_LOCAL, sockStream, 0, &fds)
        precondition(rc == 0, "socketpair(2) failed errno=\(errno)")
        reader = fds[0]
        writer = fds[1]
    }
}

/// Namespace for utilities to execute a child process.
enum Exec {
    /// Start an asynchrous child process with NIO connections.
    ///
    /// Doesn't work on an event loop:
    /// * Forking the child process is technically blocking and could do so seriously
    /// * Old version of NIO used to insist `NIOPipeBootstrap` wasn't done on an event loop,
    ///   and although this doesn't apply since 2.34.0, some pieces of state machine have ended
    ///   up leaning into the thread structure and unpicking them is work.
    ///
    /// - parameter command: Path of the command to run
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

        process.standardOutput = FileHandle(fileDescriptor: stdoutPipe.writer)
        process.standardInput = FileHandle(fileDescriptor: stdinPipe.reader)
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")!

        process.executableURL = command
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        try process.run()

        // Close our copy of the FDs that the child is using.
        close(stdoutPipe.writer)
        close(stdinPipe.reader)
        return Child(process: process, stdoutFD: stdoutPipe.reader, stdinFD: stdinPipe.writer)
    }

    /// A running child process with NIO connections.
    ///
    /// Nothing happens at deinit - client needs to close the stream / kill the process
    /// as required.
    final class Child {
        /// The `Process` object for the child
        let process: Process
        /// The child's readable output FD
        let stdoutFD: CInt
        /// The child's writable input FD
        let stdinFD: CInt

        init(process: Process, stdoutFD: CInt, stdinFD: CInt) {
            self.process = process
            self.stdoutFD = stdoutFD
            self.stdinFD = stdinFD
        }

        func terminate() {
            process.terminate()
            // this cascades closes to the FDs
        }
    }
}
