//
//  DartSassTests.swift
//  DartSassTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

import XCTest
@testable import DartSass

final class DartSassTests: XCTestCase {
    func testBootstrap() throws {
        let compiler = try Compiler(embeddedDartSass: TestUtils.dartSassEmbeddedURL)

        let compileMsg = Sass_EmbeddedProtocol_InboundMessage.with { thiz in
            thiz.message = .compileRequest(.with { msg in
                msg.id = 42
                msg.input = .string(.init())
            })
        }
        try compiler.child.send(message: compileMsg)
        let response = try compiler.child.receive()
        switch response.message {
        case .compileResponse(let rsp):
            XCTAssertEqual(42, rsp.id)
            switch rsp.result {
            case .success(let success):
                XCTAssertEqual("", success.css)
            default:
                XCTFail("Unexpected compile result: \(String(describing: rsp.result))")
                break
            }
        default:
            XCTFail("Unexpected response: \(String(describing: response.message))")
            break
        }
    }
}
