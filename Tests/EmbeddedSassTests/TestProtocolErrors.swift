//
//  TestProtocolErrors.swift
//  EmbeddedSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import NIO
@testable import EmbeddedSass

///
/// Tests around resets, timeouts, and shutdown.
///
class TestProtocolErrors: EmbeddedSassTestCase {

    // Deal with in-band reported protocol error, compiler reports it to us.
    func testOutboundProtocolError() throws {
        let compiler = try newCompiler()
        let msg = Sass_EmbeddedProtocol_InboundMessage.with { msg in
            msg.importResponse = .with { rsp in
                rsp.id = 108
            }
        }
        try compiler.eventLoop.submit {
            try compiler.child().send(message: msg)
        }.wait().wait() // !! what have I done

        checkProtocolError(compiler, "108")

        try checkCompilerWorking(compiler)
        XCTAssertEqual(2, compiler.startCount)
    }

    // Misc general bad inbound messages
    func testGeneralInboundProtocol() throws {
        let compiler = try newCompiler()

        // no message at all
        compiler.eventLoop.execute {
            let badMsg = Sass_EmbeddedProtocol_OutboundMessage()
            compiler.receive(message: badMsg)
        }

        try checkCompilerWorking(compiler)
        XCTAssertEqual(2, compiler.startCount)

        // reponse to a job we don't have active
        compiler.eventLoop.execute {
            let badMsg = Sass_EmbeddedProtocol_OutboundMessage.with { msg in
                msg.compileResponse = .with { rsp in
                    rsp.id = 42
                }
            }
            compiler.receive(message: badMsg)
        }

        try checkCompilerWorking(compiler)
        XCTAssertEqual(3, compiler.startCount)

        // response to a job when we're not interested [legacy, refactored away!]
        try compiler.shutdownGracefully().wait()
        XCTAssertNil(try compiler.compilerProcessIdentifier.wait())
        XCTAssertEqual(3, compiler.startCount) // no more resets
    }

    // Bad response to compile-req
    func testBadCompileRsp() throws {
        let compiler = try newBadCompiler()

        // Expected message, bad content

        let msg = Sass_EmbeddedProtocol_OutboundMessage.with { msg in
            msg.compileResponse = .with { rsp in
                rsp.id = Int32(Compilation.peekNextCompilationID)
                rsp.result = nil // missing 'result'
            }
        }

        let compileResult = compiler.compileAsync(text: "")

        compiler.eventLoop.execute {
            compiler.receive(message: msg)
        }
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
        let compileResult2 = compiler.compileAsync(text: "")
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
}

extension Compiler {
    func child() throws -> CompilerChild {
        guard let child = state.child else {
            throw ProtocolError("Wrong state for child")
        }
        return child
    }

    func receive(message: Sass_EmbeddedProtocol_OutboundMessage) {
        try! child().receive(message: message)
    }
}
