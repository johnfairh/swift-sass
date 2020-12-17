//
//  BinaryProtocol.swift
//  SassEmbedded
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
//    Unfortunately they require `InputStream`/`OutputStream` which doesn't match
//    anything in the Posix-y FD world let alone NIO.
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
// Switching to NIO means it gets to think about SIGPIPE -- amusingly on Linux
// it cops out and masks it off for the entire process.
//

import Foundation
import SwiftProtobuf
import NIO
import NIOFoundationCompat

/// Serialize Sass protocol messages down to NIO.
final class ProtocolWriter: MessageToByteEncoder {
    typealias OutboundIn = Sass_EmbeddedProtocol_InboundMessage

    /// Send a message to the embedded Sass compiler.
    ///
    /// - parameter message: The message to send to the compiler ('inbound' from their perspective...).
    /// - throws: Something from protobuf if it can't understand its own types.
    /// - note: Uses the embedded Sass binary delimiter protocol, not the regular protobuf one.
    func encode(data: Sass_EmbeddedProtocol_InboundMessage, out: inout ByteBuffer) throws {
        let buffer = try data.serializedData()
        out.writeInteger(UInt32(buffer.count), endianness: .little, as: UInt32.self)
        out.writeData(buffer)
    }

    /// Add a channel handler matching the protocol writer.
    static func addHandler(to channel: Channel) -> EventLoopFuture<Void> {
        channel.pipeline.addHandler(MessageToByteHandler(ProtocolWriter()))
    }
}

/// Logic to parse and decode Sass protocol messages
final class ProtocolReader: ByteToMessageDecoder {
    typealias InboundOut = Sass_EmbeddedProtocol_OutboundMessage

    enum State {
        /// Waiting for a new message
        case idle
        /// Read the length header, waiting for the body
        case reading(Int)
    }
    var state = State.idle

    /// Read and deserialize a message from the embedded sass compiler.
    ///
    /// - throws: `SwiftProtobuf.BinaryDecodingError` if it can't make sense of the bytes.
    /// - note: Uses the embedded Sass binary delimiter protocol, not the regular protobuf one.
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        switch state {
        case .idle:
            guard buffer.readableBytes >= MemoryLayout<UInt32>.size else {
                return .needMoreData
            }
            let msgLen = buffer.readInteger(endianness: .little, as: UInt32.self)!
            state = .reading(Int(msgLen))

            return .continue

        case .reading(let msgLen):
            guard buffer.readableBytes >= msgLen else {
                return .needMoreData
            }

            var message = Sass_EmbeddedProtocol_OutboundMessage()
            try message.merge(serializedData: buffer.readData(length: msgLen)!)
            state = .idle

            context.fireChannelRead(wrapInboundOut(message))
            return .continue
        }
    }

    /// Add a channel handler matching the protocol reader.
    static func addHandler(to channel: Channel) -> EventLoopFuture<Void> {
        channel.pipeline.addHandler(ByteToMessageHandler(ProtocolReader()))
    }
}
