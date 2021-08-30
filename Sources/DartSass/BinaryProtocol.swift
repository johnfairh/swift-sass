//
//  BinaryProtocol.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE)
//

import SwiftProtobuf
import NIOCore
import NIOFoundationCompat

// Routines to send and receive messages to the embedded Sass compiler.
// Theoretically broken with payloads over 2^63 bytes in size because of signed
// 64-bit sizes in Foundation.Data.

/// Serialize Sass protocol messages down to NIO.
final class ProtocolWriter: MessageToByteEncoder {
    typealias OutboundIn = Sass_EmbeddedProtocol_InboundMessage

    /// Send a message to the embedded Sass compiler.
    ///
    /// - parameter message: The message to send to the compiler ('inbound' from their perspective...).
    /// - throws: Something from protobuf if it can't understand its own types.
    func encode(data: Sass_EmbeddedProtocol_InboundMessage, out: inout ByteBuffer) throws {
        let buffer = try data.serializedData()
        out.writeVarint(UInt64(buffer.count))
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
        case waitHeader
        /// Reading the length header
        case header(Varint)
        /// Read the length header, waiting for the body
        case waitBody(UInt64)
    }
    var state = State.waitHeader

    /// Read and deserialize a message from the embedded sass compiler.
    /// - throws: `SwiftProtobuf.BinaryDecodingError` if it can't make sense of the bytes.
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        switch state {
        case .waitHeader:
            state = .header(Varint())
            return .continue

        case .header(let lenVarint):
            let byte = buffer.readInteger(as: UInt8.self)!
            if let length = try lenVarint.decode(byte: byte) {
                state = .waitBody(length)
            }
            return .continue

        case .waitBody(let msgLen):
            guard buffer.readableBytes >= msgLen else {
                return .needMoreData
            }

            var message = Sass_EmbeddedProtocol_OutboundMessage()
            try message.merge(serializedData: buffer.readData(length: Int(msgLen))!)
            state = .waitHeader

            context.fireChannelRead(wrapInboundOut(message))
            return .continue
        }
    }

    /// Just stop when we're dying off.
    func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        .needMoreData
    }

    /// Add a channel handler matching the protocol reader.
    static func addHandler(to channel: Channel) -> EventLoopFuture<Void> {
        channel.pipeline.addHandler(ByteToMessageHandler(ProtocolReader()))
    }
}

// MARK: Varint helpers

extension ByteBuffer {
    /// Append a value to the buffer in varint format
    mutating func writeVarint(_ value: UInt64) {
        var v = value
        while v > 127 {
            writeInteger(UInt8(v & 0x7f | 0x80))
            v >>= 7
        }
        writeInteger(UInt8(v))
    }
}

/// Progressively decode a varint from a byte stream
final class Varint {
    private var curValue = UInt64(0)
    private var curShift = 0

    /// Decode a new byte.
    /// * Returns nil -> more bytes required
    /// * Returns a value -> that's the value
    /// * Throws an error -> this isn't a varint
    func decode(byte: UInt8) throws -> UInt64? {
        curValue |= UInt64(byte & 0x7f) << curShift
        if byte & 0x80 == 0 {
            return curValue
        }
        curShift += 7
        if curShift > 63 {
            throw ProtocolError("Can't decode varint holding a value wider than 64 bits, so far: \(curValue)")
        }
        return nil
    }
}
