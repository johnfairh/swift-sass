//
//  BinaryProtocol.swift
//  swift-sass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

//
// Routines to send and receive messages to the embedded Sass compiler.
//
// Two horror stories in standards compliance and interop here:
//
// 1) SwiftProtobuf has `BinaryDelimited` helpers to make this stuff trivial.
//    Unfortunately they require `InputStream`/`OutputStream` whereas we have
//    `FileHandle`s and I'm too dumb to find a standard gadget for matching
//    these up.
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
// Still left with having to do I/O to Foundation's crufty `FileHandle` objects
// with dubious Objective-C-era error handling.  This looks to be being fixed
// right now, bizarrely, so I've left them being used instead of just falling
// back to read(2)/write(2).
//

import Foundation
import SwiftProtobuf

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension Exec.Child {
    /// Send a message to the embedded sass compiler.
    ///
    /// - parameter message: The message to send to the compiler ('inbound' from their perspective...).
    /// - throws: `SassError.protocolError()` if we can't squeeze the bytes out.
    /// - note: Uses the embedded Sass binary delimiter protocol, not the regular protobuf one.
    func send(message: Sass_EmbeddedProtocol_InboundMessage) throws {
        let data = try message.serializedData()
        var networkMessageLen = Int32(data.count).littleEndian
        let rc = write(standardInput.fileDescriptor, &networkMessageLen, MemoryLayout<Int32>.size)
        if rc == -1 {
            throw ProtocolError("Write of message length failed, errno=\(errno)")
        } else if rc != MemoryLayout<Int32>.size {
            throw ProtocolError("Write of message length underran, only \(rc) bytes")
        }
        /// XXX Move to `write(contentsOf:)` when macOS 10.16 is reasonable deploy target
        /// XXX This current version will crash the process on underrun or I/O error
        standardInput.write(data)
    }

    /// Read and deserialize a message from the embedded sass compiler.
    ///
    /// - throws: `ProtocolError()` if we can't get the bytes out of the compiler.
    ///           `SwiftProtobuf.BinaryDecodingError` if we can't make sense of the bytes.
    /// - note: Uses the embedded Sass binary delimiter protocol, not the regular protobuf one.
    func receive() throws -> Sass_EmbeddedProtocol_OutboundMessage {
        var networkMsgLen = Int32(0)
        let rc = read(standardOutput.fileDescriptor, &networkMsgLen, MemoryLayout<Int32>.size)
        if rc == -1 {
            throw ProtocolError("Read of message length failed, errno=\(errno)")
        } else if rc != MemoryLayout<Int32>.size {
            throw ProtocolError("Read of message length underran, only \(rc) bytes")
        }
        let msgLen = Int(Int32(littleEndian: networkMsgLen))

        /// XXX Move to `read(upToCount:)` when macOS 10.16 is reasonable deploy target
        /// XXX This current version will crash the process on I/O errors.
        let data = standardOutput.readData(ofLength: msgLen)
        if data.count != msgLen {
            throw ProtocolError("Read of message underran, only \(data.count) bytes of \(msgLen)")
        }
        var message = Sass_EmbeddedProtocol_OutboundMessage()
        try message.merge(serializedData: data)
        return message
    }
}
