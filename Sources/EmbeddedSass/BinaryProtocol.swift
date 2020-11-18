//
//  BinaryProtocol.swift
//  swift-sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

//
// Routines to send and receive messages to the embedded Sass compiler.
//
// Two horror stories in standards compliance and interop here:
//
// 1) SwiftProtobuf has `BinaryDelimited` helpers to make this stuff trivial.
//    Unfortunately they require `InputStream`/`OutputStream` whereas we have
//    `FileHandle`s and I'm too dumb to find a standard gadget for matching
//    these up, never mind with the requisite anti-SIGPIPE measures.
//
// 2) Protobuf's written docs are vague about how binary delimiters should work.
//    The code is unambiguous though: use a varint32 to hold the length.
//    The Sass team interpreted this differently though and require a
//    straight 32-bit number (in reverse network byte order).
//
// Now, these two things sort of cancel each other out!  Because of (2) we don't
// actually need the `Varint` stuff that is private inside SwiftProtobuf, and so
// we can manually do its fixed-header format, bypassing `BinaryDelimited`
// entirely.
//

import Foundation
import SwiftProtobuf

extension Exec.Child {
    /// Send a message to the embedded sass compiler.
    ///
    /// - parameter message: The message to send to the compiler ('inbound' from their perspective...).
    /// - throws: `SassError.protocolError()` if we can't squeeze the bytes out.
    /// - note: Uses the embedded Sass binary delimiter protocol, not the regular protobuf one.
    func send(message: Sass_EmbeddedProtocol_InboundMessage) throws {
        func doSend(_ bytes: UnsafeRawPointer!, _ count: Int) throws {
            let rc = standardInput.sockSend(bytes, count: count)
            if rc == -1 {
                throw ProtocolError("Write of \(count) bytes failed, errno=\(errno)")
            } else if rc != count {
                throw ProtocolError("Write of \(count) bytes underran, only \(rc) bytes written")
            }
        }

        let data = try message.serializedData()

        var networkMessageLen = Int32(data.count).littleEndian
        try doSend(&networkMessageLen, MemoryLayout<Int32>.size)

        try data.withUnsafeBytes { bufferPointer in
            try doSend(bufferPointer.baseAddress, data.count)
        }
    }

    /// Read and deserialize a message from the embedded sass compiler.
    ///
    /// - parameter timeout: Max seconds to wait for a reply, -1 to disable.
    /// - throws: `ProtocolError()` if we can't get the bytes out of the compiler.
    ///           `SwiftProtobuf.BinaryDecodingError` if we can't make sense of the bytes.
    /// - note: Uses the embedded Sass binary delimiter protocol, not the regular protobuf one.
    func receive(timeout: Int) throws -> Sass_EmbeddedProtocol_OutboundMessage {
        func doRecv(_ bytes: UnsafeMutableRawPointer!, _ count: Int) throws {
            let rc = standardOutput.sockRecv(bytes, count: count)
            if rc == -1 {
                throw ProtocolError("Read of \(count) bytes failed, errno=\(errno)")
            } else if rc != count {
                throw ProtocolError("Read of \(count) bytes underran, only \(rc) bytes read")
            }
        }

        // A grotty (but cross-platform!) timeout-to-readable to detect a stuck compiler
        // process.  TODO-NIO.
        var pfd = pollfd(fd: standardOutput.fileDescriptor,
                         events: Int16(POLLIN),
                         revents: 0)
        let rc = poll(&pfd, 1, timeout == -1 ? -1 : Int32(timeout * 1000))
        if rc == 0 {
            throw ProtocolError("Timeout waiting for compiler to respond after \(timeout) seconds")
        }
        if rc == -1 {
            throw ProtocolError("poll(2) failed, errno=\(errno)")
        }

        var networkMsgLen = Int32(0)
        try doRecv(&networkMsgLen, MemoryLayout<Int32>.size)
        let msgLen = Int(Int32(littleEndian: networkMsgLen))

        var data = Data(count: msgLen)
        try data.withUnsafeMutableBytes { bufferPointer in
            try doRecv(bufferPointer.baseAddress, msgLen)
        }

        var message = Sass_EmbeddedProtocol_OutboundMessage()
        try message.merge(serializedData: data)
        return message
    }
}
