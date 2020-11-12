//
//  SassCompiler.swift
//  DartSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

import Foundation

public final class Compiler {
    let child: Exec.Child
    public init(embeddedDartSass: URL) throws {
        child = try Exec.spawn(embeddedDartSass)
    }

    deinit {
        child.process.terminate()
    }

//    public func hello() throws {
//        let compileMsg = Sass_EmbeddedProtocol_InboundMessage.with { thiz in
//            thiz.message = .compileRequest(.with { msg in
//                msg.id = 42
//                msg.input = .string(.init())
//            })
//        }
//        try child.send(message: compileMsg)
//        let response = try child.receive()
//        switch response.message {
//        case .compileResponse(let rsp):
//            assert(rsp.id == 42)
//            switch rsp.result {
//            case .success(let success):
//                assert(success.css == "")
//            default:
//                break
//            }
//            print(rsp)
//        default:
//            break
//        }
//    }
}
