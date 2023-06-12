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

/// A message we want to send to the Sass compiler.
/// It has two parts: an ID and a protobuf object.
struct OutboundMessage {
    let id: UInt32
    let msg: Sass_EmbeddedProtocol_InboundMessage // inbound from compiler's POV

    static func with(_ builder: (inout Sass_EmbeddedProtocol_InboundMessage) -> UInt32) -> OutboundMessage {
        var msg = Sass_EmbeddedProtocol_InboundMessage()
        let id = builder(&msg)
        return .init(id: id, msg: msg)
    }
}

/// A message we've decoded from the Sass compiler.
/// It has two parts: an ID and a protobuf object.
struct InboundMessage {
    let id: UInt32
    let msg: Sass_EmbeddedProtocol_OutboundMessage // outbound from compiler's POV

    init(id: UInt32 = 0, msg: Sass_EmbeddedProtocol_OutboundMessage = .init()) {
        self.id = id
        self.msg = msg
    }
}

/// Serialize Sass protocol messages down to NIO.
final class ProtocolWriter: MessageToByteEncoder {
    typealias OutboundIn = OutboundMessage

    /// Send a message to the embedded Sass compiler.
    ///
    /// - parameter message: The message to send to the compiler ('inbound' from their perspective...).
    /// - throws: Something from protobuf if it can't understand its own types.
    func encode(data: OutboundMessage, out: inout ByteBuffer) throws {
        let buffer = try data.msg.serializedData()
        let idLength = Varint.encodedLength(of: data.id)
        out.writeVarint(UInt64(buffer.count + idLength))
        out.writeVarint(UInt64(data.id))
        out.writeData(buffer)
    }

    /// Add a channel handler matching the protocol writer.
    static func addHandler(to channel: Channel) -> EventLoopFuture<Void> {
        channel.pipeline.addHandler(MessageToByteHandler(ProtocolWriter()))
    }
}

/// Logic to parse and decode Sass protocol messages
final class ProtocolReader: ByteToMessageDecoder {
    typealias InboundOut = InboundMessage

    enum State {
        /// Waiting for a new message
        case waitHeader
        /// Reading the length header
        case header(Varint)
        /// Reading the ID
        case compilationID(UInt64, Varint)
        /// Read the length header, read the compilationID, waiting for the body
        case waitBody(compilationID: UInt32, bodyLength: UInt64)
    }
    var state = State.waitHeader

    /// Read and deserialize a message from the embedded sass compiler.
    /// - throws: `SwiftProtobuf.BinaryDecodingError` if it can't make sense of the bytes.
    ///           `ProtocolError` if we get a corrupt varint or a varint longer than permitted for context.
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        switch state {
        case .waitHeader:
            state = .header(Varint())
            return .continue

        case .header(let lenVarint):
            let byte = buffer.readInteger(as: UInt8.self)!
            if let length = try lenVarint.decode(byte: byte) {
                state = .compilationID(length, Varint())
            }
            return .continue

        case .compilationID(let lenBuffer, let compilationIDVarint):
            let byte = buffer.readInteger(as: UInt8.self)!
            guard let compilationID = try compilationIDVarint.decode(byte: byte) else {
                return .continue
            }

            // wire-level rule that the compilationID varint must be uint32...
            guard let compilationID32 = UInt32(exactly: compilationID) else {
                // throw something i guess
                preconditionFailure("Overflowing wire ID")
            }

            let lenProtobuf = lenBuffer - UInt64(compilationIDVarint.byteLength)
            state = .waitBody(compilationID: compilationID32, bodyLength: lenProtobuf)

            return .continue

        case .waitBody(let compilationID, let bodyLen):
            guard buffer.readableBytes >= bodyLen else {
                return .needMoreData
            }

            var payload = Sass_EmbeddedProtocol_OutboundMessage()
            try payload.merge(serializedData: buffer.readData(length: Int(bodyLen))!)
            state = .waitHeader

            let message = InboundMessage(id: compilationID, msg: payload)
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

    /// Probably....
    var byteLength: Int {
        (curShift / 7) + 1
    }

    /// Say how many bytes are required to store a numeric value
    static func encodedLength(of value: UInt32) -> Int {
        max(1, ((value.bitWidth - value.leadingZeroBitCount) + 6) / 7)
    }
}
