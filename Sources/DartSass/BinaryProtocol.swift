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
struct OutboundMessage: Sendable {
    let compilationID: UInt32
    let sassInboundMessage: Sass_EmbeddedProtocol_InboundMessage // inbound from compiler's POV

    init(_ compilationID: UInt32 = 0, _ sassInboundMessage: Sass_EmbeddedProtocol_InboundMessage = .init()) {
        self.compilationID = compilationID
        self.sassInboundMessage = sassInboundMessage
    }

    // Factories

    static func compileRequest(_ id: UInt32, builder: (inout Sass_EmbeddedProtocol_InboundMessage.CompileRequest) -> Void) -> OutboundMessage {
        .init(id, .with { builder(&$0.compileRequest) })
    }

    static func versionRequest(builder: (inout Sass_EmbeddedProtocol_InboundMessage.VersionRequest) -> Void) -> OutboundMessage {
        .init(0, .with { builder(&$0.versionRequest) })
    }

    // Accessors

    var versionRequest: Sass_EmbeddedProtocol_InboundMessage.VersionRequest {
        sassInboundMessage.versionRequest
    }
}

/// A message we've decoded from the Sass compiler.
/// It has two parts: an ID and a protobuf object.
struct InboundMessage: Sendable {
    let compilationID: UInt32
    let sassOutboundMessage: Sass_EmbeddedProtocol_OutboundMessage // outbound from compiler's POV

    init(_ compilationID: UInt32 = 0, _ sassOutboundMessage: Sass_EmbeddedProtocol_OutboundMessage = .init()) {
        self.compilationID = compilationID
        self.sassOutboundMessage = sassOutboundMessage
    }
}

/// Serialize Sass protocol messages down to NIO.
final class ProtocolWriter: MessageToByteEncoder {
    typealias OutboundIn = OutboundMessage

    /// Send a message to the embedded Sass compiler.
    ///
    /// - parameter message: The message to send to the compiler.
    /// - throws: Something from protobuf if it can't understand its own types.
    func encode(data: OutboundMessage, out: inout ByteBuffer) throws {
        let buffer = try data.sassInboundMessage.serializedData()
        let idLength = Varint.encodedLength(of: data.compilationID)
        out.writeVarint(UInt64(buffer.count + idLength))
        out.writeVarint(UInt64(data.compilationID))
        out.writeData(buffer)
    }

    /// Add a channel handler matching the protocol writer.
    static func addHandlerSync(to channel: Channel) throws {
        try channel.pipeline.syncOperations.addHandler(MessageToByteHandler(ProtocolWriter()))
    }
}

/// Logic to parse and decode Sass protocol messages
final class ProtocolReader: ByteToMessageDecoder {
    typealias InboundOut = InboundMessage

    enum State {
        /// Waiting for a new message
        case waitHeader
        /// Reading the length header
        case readingLength(Varint)
        /// Reading the compilation ID header
        case readingCompilationID(UInt64, Varint)
        /// Read the length header, read the compilationID, waiting for the body to all arrive
        case waitBody(compilationID: UInt32, bodyLength: UInt64)
    }
    var state = State.waitHeader

    /// Read and deserialize a message from the embedded sass compiler.
    /// - throws: `SwiftProtobuf.BinaryDecodingError` if it can't make sense of the bytes.
    ///           `ProtocolError` if we get a corrupt varint or a varint longer than permitted for context.
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        switch state {
        case .waitHeader:
            state = .readingLength(Varint())
            return .continue

        case .readingLength(let lengthVarint):
            let byte = buffer.readInteger(as: UInt8.self)!
            if let length = try lengthVarint.decode(byte: byte) {
                state = .readingCompilationID(length, Varint())
            }
            return .continue

        case .readingCompilationID(let length, let compilationIDVarint):
            let byte = buffer.readInteger(as: UInt8.self)!
            guard let compilationID = try compilationIDVarint.decode(byte: byte) else {
                return .continue
            }

            // wire-level rule that the compilationID varint must be uint32...
            guard let compilationID32 = UInt32(exactly: compilationID) else {
                throw ProtocolError("Malformed byte stream from Sass compiler.  Got length \(length), then read compilation ID of \(compilationID) which does not fit into 32 bits.")
            }

            let bodyLength = length - UInt64(compilationIDVarint.byteLength)
            state = .waitBody(compilationID: compilationID32, bodyLength: bodyLength)

            return .continue

        case .waitBody(let compilationID, let bodyLength):
            guard buffer.readableBytes >= bodyLength else {
                return .needMoreData
            }

            var sassOutboundMessage = Sass_EmbeddedProtocol_OutboundMessage()
            try sassOutboundMessage.merge(serializedData: buffer.readData(length: Int(bodyLength))!)
            state = .waitHeader
            context.fireChannelRead(wrapInboundOut(InboundMessage(compilationID, sassOutboundMessage)))

            return .continue
        }
    }

    /// Just stop when we're dying off.
    func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        .needMoreData
    }

    static func addHandlerSync(to channel: Channel) throws {
        try channel.pipeline.syncOperations.addHandler(ByteToMessageHandler(ProtocolReader()))
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
