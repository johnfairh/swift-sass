//
//  TestProtocolErrors.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

//import XCTest
//import NIO
//@testable import DartSass
//
/////
///// Tests around duff message content to & from the compiler
/////
//class TestProtocolErrors: DartSassTestCase {
//
//    // Deal with in-band reported protocol error, compiler reports it to us.
//    func testOutboundProtocolError() throws {
//        try asyncTest(asyncTestOutboundProtocolError)
//    }
//
//    func asyncTestOutboundProtocolError() async throws {
//        let compiler = try newCompiler()
//        let msg = Sass_EmbeddedProtocol_InboundMessage.with { msg in
//            msg.importResponse = .with { rsp in
//                rsp.id = 108
//            }
//        }
//        XCTAssertNil(compiler.state.child)
//        await compiler.sync()
//        let f = compiler.eventLoop.flatSubmit {
//            try! compiler.child().send(message: msg)
//        }
//
//        checkProtocolError(compiler, "108")
//        _ = try? await f.get()
//
//        try checkCompilerWorking(compiler)
//        XCTAssertEqual(2, compiler.startCount)
//    }
//
//    // Misc general bad inbound messages
//    func testGeneralInboundProtocol() throws {
//        try asyncTest(asyncTestGeneralInboundProtocol)
//    }
//
//    func asyncTestGeneralInboundProtocol() async throws {
//        let compiler = try newCompiler()
//
//        // no message at all
//        let badMsg = Sass_EmbeddedProtocol_OutboundMessage()
//        await compiler.receive(message: badMsg)
//
//        try checkCompilerWorking(compiler)
//        XCTAssertEqual(2, compiler.startCount)
//
//        // reponse to a job we don't have active
//        let badMsg1 = Sass_EmbeddedProtocol_OutboundMessage.with { msg in
//            msg.compileResponse = .with { rsp in
//                rsp.id = 42
//            }
//        }
//        await compiler.receive(message: badMsg1)
//
//        try checkCompilerWorking(compiler)
//        XCTAssertEqual(3, compiler.startCount)
//
//        // response to a job when we're not interested [legacy, refactored away!]
//        try compiler.syncShutdownGracefully()
//        let pid = await compiler.compilerProcessIdentifier
//        XCTAssertNil(pid)
//        XCTAssertEqual(3, compiler.startCount) // no more resets
//    }
//
//    // Bad response to compile-req
//    func testBadCompileRsp() throws {
//        try asyncTest(asyncTestBadCompileRsp)
//    }
//
//    func asyncTestBadCompileRsp() async throws {
//        let compiler = try newBadCompiler()
//
//        // Expected message, bad content
//
//        let msg = Sass_EmbeddedProtocol_OutboundMessage.with { msg in
//            msg.compileResponse = .with { rsp in
//                rsp.id = RequestID.peekNext
//                rsp.result = nil // missing 'result'
//            }
//        }
//
//        let compileResult = Task { try await compiler.compile(string: "") }
//        try? await Task.sleep(nanoseconds: 1000 * 1000 * 500)
//
//        await compiler.receive(message: msg)
//
//        do {
//            let results = try await compileResult.value
//            XCTFail("Managed to compile: \(results)")
//        } catch let error as ProtocolError {
//            print(error)
//            XCTAssertTrue(error.description.contains("missing `result`"))
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//
//        await XCTAssertNoThrowA(try await compiler.reinit()) // sync with event loop
//        XCTAssertEqual(2, compiler.startCount)
//
//        // Peculiar error
//        let compileResult2 = Task { try await compiler.compile(string: "") }
//        try? await Task.sleep(nanoseconds: 1000 * 1000 * 500)
//        compiler.eventLoop.execute {
//            try! compiler.child().channel.pipeline.fireErrorCaught(ProtocolError("Injected channel error"))
//        }
//        do {
//            let results = try await compileResult2.value
//            XCTFail("Managed to compile: \(results)")
//        } catch let error as ProtocolError {
//            print(error)
//            XCTAssertTrue(error.description.contains("Injected channel error"))
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//
//        await XCTAssertNoThrowA(try await compiler.reinit()) // sync with event loop
//        XCTAssertEqual(3, compiler.startCount)
//    }
//
//    // Importer request tests.  A bit grim:
//    // Get us into the state of allowing one by starting up and hanging a custom importer.
//    // Then inject a second import request -- probably impossible in practice but close
//    // enough, protocol under-specified!
//    // The error will start cancellation, but that won't be possible until the hung custom
//    // import completes.
//    func checkBadImportMessage(_ msg: Sass_EmbeddedProtocol_OutboundMessage.ImportRequest, _ errStr: String) async throws {
//        try await checkBadMessage(.with { $0.importRequest = msg }, errStr)
//    }
//
//    func checkBadFnCallMessage(_ msg: Sass_EmbeddedProtocol_OutboundMessage.FunctionCallRequest, _ errStr: String) async throws {
//        try await checkBadMessage(.with { $0.functionCallRequest = msg }, errStr)
//    }
//
//    func checkBadFileImport(_ msg: Sass_EmbeddedProtocol_OutboundMessage.FileImportRequest, _ errStr: String) async throws {
//        try await checkBadMessage(.with { $0.fileImportRequest = msg }, errStr)
//    }
//
//    func checkBadMessage(_ msg: Sass_EmbeddedProtocol_OutboundMessage, _ errStr: String) async throws {
//        let importer = HangingAsyncImporter()
//
//        struct DummyFilesystemImporter: FilesystemImporter {
//            func resolve(ruleURL: String, fromImport: Bool) async throws -> URL? {
//                nil
//            }
//        }
//
//        let compiler = try newCompiler(importers: [
//            .importer(importer),
//            .loadPath(URL(fileURLWithPath: "/tmp")),
//            .filesystemImporter(DummyFilesystemImporter())
//        ])
//
//        importer.state.onLoadHang = {
//            await compiler.receive(message: msg)
//        }
//
//        do {
//            let results = try await compiler.compile(string: "@import 'something';")
//            XCTFail("Managed to compile: \(results)")
//        } catch let error as ProtocolError {
//            print(error)
//            XCTAssertTrue(error.description.contains(errStr))
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//
//    /// importer ID is completely wrong
//    func testImporterBadID() throws {
//        try asyncTest(asyncTestImporterBadID)
//    }
//
//    func asyncTestImporterBadID() async throws {
//        try await checkBadImportMessage(.with {
//            $0.compilationID = RequestID.peekNext
//            $0.id = 42
//            $0.importerID = 12
//        }, "Bad importer ID")
//    }
//
//    /// Importer ID picks out a loadpath not an importer
//    func testImporterBadImporterType1() throws {
//        try asyncTest(asyncTestImporterBadImporterType1)
//    }
//
//    func asyncTestImporterBadImporterType1() async throws {
//        try await checkBadImportMessage(.with {
//            $0.compilationID = RequestID.peekNext
//            $0.id = 42
//            $0.importerID = 4001
//        }, "not an importer")
//    }
//
//    /// Importer ID picks out a fileimporter not an importer
//    func testImporterBadImporterType2() throws {
//        try asyncTest(asyncTestImporterBadImporterType2)
//    }
//
//    func asyncTestImporterBadImporterType2() async throws {
//        try await checkBadImportMessage(.with {
//            $0.compilationID = RequestID.peekNext
//            $0.id = 42
//            $0.importerID = 4002
//        }, "not an importer")
//    }
//
//    /// URL has gotten messed up
//    func testImporterBadURL() throws {
//        try asyncTest(asyncTestImporterBadURL)
//    }
//
//    func asyncTestImporterBadURL() async throws {
//        try await checkBadImportMessage(.with {
//            $0.compilationID = RequestID.peekNext
//            $0.id = 42
//            $0.importerID = 4000
//        }, "Malformed import URL")
//    }
//
//    /// FileImporter
//    func testFileImporterBadID() throws {
//        try asyncTest(asyncTestFileImporterBadID)
//    }
//
//    func asyncTestFileImporterBadID() async throws {
//        try await checkBadFileImport(.with {
//            $0.compilationID = RequestID.peekNext
//            $0.id = 42
//            $0.importerID = 4000
//        }, "Bad importer ID 4000")
//    }
//
//    // FnCall requests
//    // Reuse the importer stuff, same scenario really just different error.
//
//    /// Missing fn identifier
//    func testImporterNoIdentifier() throws {
//        try asyncTest(asyncTestImporterNoIdentifier)
//    }
//
//    func asyncTestImporterNoIdentifier() async throws {
//        try await checkBadFnCallMessage(.with {
//            $0.compilationID = RequestID.peekNext
//            $0.id = 42
//        }, "Missing 'identifier'")
//    }
//
//    /// Bad ID
//    func testImporterBadNumericID() throws {
//        try asyncTest(asyncTestImporterBadNumericID)
//    }
//
//    func asyncTestImporterBadNumericID() async throws {
//        try await checkBadFnCallMessage(.with {
//            $0.compilationID = RequestID.peekNext
//            $0.id = 42
//            $0.functionID = 108
//        }, "Host function ID")
//    }
//
//    /// Bad name
//    func testImporterBadName() throws {
//        try asyncTest(asyncTestImporterBadName)
//    }
//
//    func asyncTestImporterBadName() async throws {
//        try await checkBadFnCallMessage(.with {
//            $0.compilationID = RequestID.peekNext
//            $0.id = 42
//            $0.name = "mysterious"
//        }, "Host function name")
//    }
//
//    // Misc bits of unconvertible API
//
//    func testBadLogEventKind() throws {
//        let kind = Sass_EmbeddedProtocol_LogEventType.UNRECOGNIZED(100)
//        XCTAssertThrowsError(_ = try CompilerMessage.Kind(kind))
//    }
//
//    /// Misc test for a message variant that the protocol supports but I can't make dart sass create
//    func testSpanNoEnd() throws {
//        let msg = Sass_EmbeddedProtocol_SourceSpan()
//        let span = Span(msg)
//        XCTAssertEqual("[input] 1:1", span.description)
//    }
//
//    // MARK: Varint
//
//    func decodeVarint(buffer: inout ByteBuffer) throws -> UInt64? {
//        let decoder = Varint()
//        while buffer.readableBytes > 0 {
//            let byte = buffer.readInteger(as: UInt8.self)!
//            if let decoded = try decoder.decode(byte: byte) {
//                XCTAssertEqual(0, buffer.readableBytes)
//                return decoded
//            }
//        }
//        return nil
//    }
//
//    func testVarintConversion() throws {
//        let values: [UInt64] = [0, 0x7f, 0x80, 0xffff, 0xffffffff, 0xffffffffffffffff]
//        let allocator = ByteBufferAllocator()
//        try values.forEach { value in
//            var buffer = allocator.buffer(capacity: 20)
//            buffer.writeVarint(value)
//
//            if let decoded = try decodeVarint(buffer: &buffer) {
//                XCTAssertEqual(value, decoded)
//            } else {
//                XCTFail("Couldn't decode buffer: \(buffer), expected \(value)")
//            }
//        }
//    }
//
//    func testVarintError() throws {
//        let allocator = ByteBufferAllocator()
//        var buffer = allocator.buffer(capacity: 20)
//        buffer.writeInteger(UInt32(0xffffffff))
//        buffer.writeInteger(UInt32(0xffffffff))
//        buffer.writeInteger(UInt32(0xffffffff))
//
//        XCTAssertThrowsError(try decodeVarint(buffer: &buffer))
//    }
//}
//
//extension Compiler {
//    func child() throws -> CompilerChild {
//        guard let child = state.child else {
//            throw ProtocolError("Wrong state for child")
//        }
//        return child
//    }
//
//    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) async {
//        await sync()
//        eventLoop.execute {
//            try! self.child().receive(message: message)
//        }
//        await sync()
//        try? await Task.sleep(nanoseconds: 10000) // i'm sorry this whole thing needs a redesign
//                                                  // for async-await, can't get my head around how
//                                                  // to inject errors in a controlled way.
//    }
//
//    func sync() async {
//        let _ = await compilerProcessIdentifier
//        XCTAssertNil(state.future)
//    }
//}
