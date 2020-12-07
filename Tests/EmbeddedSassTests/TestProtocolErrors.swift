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
    func testProtocolError() throws {
        let compiler = try newCompiler()
        let msg = Sass_EmbeddedProtocol_InboundMessage.with { msg in
            msg.importResponse = .with { rsp in
                rsp.id = 108
            }
        }
        try compiler.state.child!.standardInput.writeAndFlush(msg).wait()

        checkProtocolError(compiler, "108")

        // check compiler is now working OK
        let results = try compiler.compile(text: "")
        XCTAssertEqual("", results.css)
        XCTAssertEqual(2, compiler.startCount)
    }

    // TODO: weird messages coming in to us.
}
