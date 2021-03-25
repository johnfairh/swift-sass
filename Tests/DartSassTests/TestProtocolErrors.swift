//
//  TestProtocolErrors.swift
//  DartSassTests
//
//  Copyright 2020-2021 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import NIO
@testable import DartSass

///
/// Tests around duff message content to & from the compiler
///
class TestProtocolErrors: DartSassTestCase {

    // Deal with in-band reported protocol error, compiler reports it to us.
    func testOutboundProtocolError() throws {
        let compiler = try newCompiler()
        let msg = Sass_EmbeddedProtocol_InboundMessage.with { msg in
            msg.importResponse = .with { rsp in
                rsp.id = 108
            }
        }
        XCTAssertNil(compiler.state.child)
        compiler.sync()
        try compiler.eventLoop.flatSubmit {
            try! compiler.child().send(message: msg)
        }.wait()

        checkProtocolError(compiler, "108")

        try checkCompilerWorking(compiler)
        XCTAssertEqual(2, compiler.startCount)
    }

    // Misc general bad inbound messages
    func testGeneralInboundProtocol() throws {
        let compiler = try newCompiler()

        // no message at all
        let badMsg = Sass_EmbeddedProtocol_OutboundMessage()
        compiler.receive(message: badMsg)

        try checkCompilerWorking(compiler)
        XCTAssertEqual(2, compiler.startCount)

        // reponse to a job we don't have active
        let badMsg1 = Sass_EmbeddedProtocol_OutboundMessage.with { msg in
            msg.compileResponse = .with { rsp in
                rsp.id = 42
            }
        }
        compiler.receive(message: badMsg1)

        try checkCompilerWorking(compiler)
        XCTAssertEqual(3, compiler.startCount)

        // response to a job when we're not interested [legacy, refactored away!]
        try compiler.syncShutdownGracefully()
        XCTAssertNil(try compiler.compilerProcessIdentifier.wait())
        XCTAssertEqual(3, compiler.startCount) // no more resets
    }

    // Bad response to compile-req
    func testBadCompileRsp() throws {
        let compiler = try newBadCompiler()

        // Expected message, bad content

        let msg = Sass_EmbeddedProtocol_OutboundMessage.with { msg in
            msg.compileResponse = .with { rsp in
                rsp.id = CompilationRequest.peekNextCompilationID
                rsp.result = nil // missing 'result'
            }
        }

        let compileResult = compiler.compileAsync(string: "")

        compiler.receive(message: msg)

        do {
            let results = try compileResult.wait()
            XCTFail("Managed to compile: \(results)")
        } catch let error as ProtocolError {
            print(error)
            XCTAssertTrue(error.description.contains("missing `result`"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNoThrow(try compiler.reinit().wait()) // sync with event loop
        XCTAssertEqual(2, compiler.startCount)

        // Peculiar error
        let compileResult2 = compiler.compileAsync(string: "")
        compiler.eventLoop.execute {
            try! compiler.child().channel.pipeline.fireErrorCaught(ProtocolError("Injected channel error"))
        }
        do {
            let results = try compileResult2.wait()
            XCTFail("Managed to compile: \(results)")
        } catch let error as ProtocolError {
            print(error)
            XCTAssertTrue(error.description.contains("Injected channel error"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNoThrow(try compiler.reinit().wait()) // sync with event loop
        XCTAssertEqual(3, compiler.startCount)
    }

    // Importer request tests.  A bit grim:
    // Get us into the state of allowing one by starting up and hanging a custom importer.
    // Then inject a second import request -- probably impossible in practice but close
    // enough, protocol under-specified!
    // The error will start cancellation, but that won't be possible until the hung custom
    // import completes.
    func checkBadImportMessage(_ msg: Sass_EmbeddedProtocol_OutboundMessage.ImportRequest, _ errStr: String) throws {
        try checkBadMessage(.with { $0.importRequest = msg }, errStr)
    }

    func checkBadFnCallMessage(_ msg: Sass_EmbeddedProtocol_OutboundMessage.FunctionCallRequest, _ errStr: String) throws {
        try checkBadMessage(.with { $0.functionCallRequest = msg }, errStr)
    }

    func checkBadFileImport(_ msg: Sass_EmbeddedProtocol_OutboundMessage.FileImportRequest, _ errStr: String) throws {
        try checkBadMessage(.with { $0.fileImportRequest = msg }, errStr)
    }

    func checkBadMessage(_ msg: Sass_EmbeddedProtocol_OutboundMessage, _ errStr: String) throws {
        let importer = HangingAsyncImporter()
        let compiler = try newCompiler(importers: [
            .importer(importer),
            .loadPath(URL(fileURLWithPath: "/tmp"))
        ])
        let hangDone = importer.hangLoad(eventLoop: compiler.eventLoop)

        let compilerResults = compiler.compileAsync(string: "@import 'something';")
        _ = try hangDone.wait()

        compiler.receive(message: msg)
        try importer.resumeLoad()
        do {
            let results = try compilerResults.wait()
            XCTFail("Managed to compile: \(results)")
        } catch let error as ProtocolError {
            print(error)
            XCTAssertTrue(error.description.contains(errStr))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// importer ID is completely wrong
    func testImporterBadID() throws {
        try checkBadImportMessage(.with {
            $0.compilationID = CompilationRequest.peekNextCompilationID
            $0.id = 42
            $0.importerID = 12
        }, "Bad importer ID")
    }

    /// Importer ID picks out a loadpath not an importer
    func testImporterBadImporterType() throws {
        try checkBadImportMessage(.with {
            $0.compilationID = CompilationRequest.peekNextCompilationID
            $0.id = 42
            $0.importerID = 4001
        }, "not an importer")
    }

    /// URL has gotten messed up
    func testImporterBadURL() throws {
        try checkBadImportMessage(.with {
            $0.compilationID = CompilationRequest.peekNextCompilationID
            $0.id = 42
            $0.importerID = 4000
        }, "Malformed import URL")
    }

    // FnCall requests
    // Reuse the importer stuff, same scenario really just different error.

    /// Missing fn identifier
    func testImporterNoIdentifier() throws {
        try checkBadFnCallMessage(.with {
            $0.compilationID = CompilationRequest.peekNextCompilationID
            $0.id = 42
        }, "Missing 'identifier'")
    }

    /// Bad ID
    func testImporterBadNumericID() throws {
        try checkBadFnCallMessage(.with {
            $0.compilationID = CompilationRequest.peekNextCompilationID
            $0.id = 42
            $0.functionID = 108
        }, "Host function ID")
    }

    /// Bad name
    func testImporterBadName() throws {
        try checkBadFnCallMessage(.with {
            $0.compilationID = CompilationRequest.peekNextCompilationID
            $0.id = 42
            $0.name = "mysterious"
        }, "Host function name")
    }

    /// File import is in the API but not implemented anywhere...
    func testUnexpectedFileImport() throws {
        try checkBadFileImport(.with {
            $0.compilationID = CompilationRequest.peekNextCompilationID
            $0.id = 108
            $0.importerID = 22
        }, "Unexpected FileImport-Req")
    }

    // Misc bits of unconvertible API

    func testBadLogEventKind() throws {
        let kind = Sass_EmbeddedProtocol_OutboundMessage.LogEvent.TypeEnum.UNRECOGNIZED(100)
        XCTAssertThrowsError(_ = try CompilerMessage.Kind(kind))
    }

    // MARK: Varint

    func decodeVarint(buffer: inout ByteBuffer) throws -> UInt64? {
        let decoder = Varint()
        while buffer.readableBytes > 0 {
            let byte = buffer.readInteger(as: UInt8.self)!
            if let decoded = try decoder.decode(byte: byte) {
                XCTAssertEqual(0, buffer.readableBytes)
                return decoded
            }
        }
        return nil
    }

    func testVarintConversion() throws {
        let values: [UInt64] = [0, 0x7f, 0x80, 0xffff, 0xffffffff, 0xffffffffffffffff]
        let allocator = ByteBufferAllocator()
        try values.forEach { value in
            var buffer = allocator.buffer(capacity: 20)
            buffer.writeVarint(value)

            if let decoded = try decodeVarint(buffer: &buffer) {
                XCTAssertEqual(value, decoded)
            } else {
                XCTFail("Couldn't decode buffer: \(buffer), expected \(value)")
            }
        }
    }

    func testVarintError() throws {
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(capacity: 20)
        buffer.writeInteger(UInt32(0xffffffff))
        buffer.writeInteger(UInt32(0xffffffff))
        buffer.writeInteger(UInt32(0xffffffff))

        XCTAssertThrowsError(try decodeVarint(buffer: &buffer))
    }
}

extension Compiler {
    func child() throws -> CompilerChild {
        guard let child = state.child else {
            throw ProtocolError("Wrong state for child")
        }
        return child
    }

    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) {
        sync()
        eventLoop.execute {
            try! self.child().receive(message: message)
        }
    }

    func sync() {
        let _ = try! compilerProcessIdentifier.wait()
        XCTAssertNil(state.future)
    }
}
