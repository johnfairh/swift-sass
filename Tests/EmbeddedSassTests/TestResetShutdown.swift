//
//  TestResetShutdown.swift
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
class TestResetShutdown: EmbeddedSassTestCase {
    // Clean restart case
    func testCleanRestart() throws {
        let compiler = try newCompiler()
        XCTAssertEqual(1, compiler.startCount)

        XCTAssertNoThrow(try compiler.reinit().wait())
        XCTAssertEqual(2, compiler.startCount)
    }

    // Deal with missing child & SIGPIPE-avoidance measures
    func testChildTermination() throws {
        let compiler = try newCompiler()
        let rc = kill(try compiler.compilerProcessIdentifier.wait()!, SIGTERM)
        XCTAssertEqual(0, rc)
        print("XCKilled compiler process")
        checkProtocolError(compiler)

        // check recovered
        try checkCompilerWorking(compiler)
    }

    // Check we detect stuck requests
    func testTimeout() throws {
        let badCompiler = try newBadCompiler()

        checkProtocolError(badCompiler, "Timeout")

        try badCompiler.shutdownGracefully().wait()
    }

    // Test disabling the timeout works
    func testTimeoutDisabled() throws {
        let badCompiler = try newBadCompiler(timeout: -1)

        var compilationComplete = false

        let compileResult = badCompiler.compileAsync(text: "")
        compileResult.whenComplete { _ in compilationComplete = true }

        let eventLoop = eventLoopGroup.next()
        try eventLoop.flatScheduleTask(in: .seconds(1)) { () -> EventLoopFuture<Void> in
            XCTAssertFalse(compilationComplete)
            return badCompiler.reinit()
        }.futureResult.wait()

        do {
            let results = try compileResult.wait()
            XCTFail("Shouldn't have compiled! \(results)")
        } catch let error as ProtocolError {
            XCTAssertTrue(error.description.contains("User requested"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Test the 'compiler will not restart' corner
    func testUnrestartableCompiler() throws {
        let tmpDir = try FileManager.default.createTemporaryDirectory()
        let realHeadURL = URL(fileURLWithPath: "/usr/bin/tail")
        let tmpHeadURL = tmpDir.appendingPathComponent("tail")
        try FileManager.default.copyItem(at: realHeadURL, to: tmpHeadURL)

        Compiler.logger.logLevel = .debug
        let badCompiler = try Compiler(eventLoopGroup: eventLoopGroup,
                                       embeddedCompilerURL: tmpHeadURL,
                                       timeout: 1)

        // it's now running using the copied program
        try FileManager.default.removeItem(at: tmpHeadURL)

        // Use the instance we have up, will timeout & be killed
        // ho hum, on GitHub Actions sometimes we get a pipe error instead
        // either is fine, as long as it fails somehow.
        checkProtocolError(badCompiler)

        // Should be in idle_broken, restart not possible
        checkProtocolError(badCompiler, "failed to restart")

        // Try to recover - no dice
        do {
            try badCompiler.reinit().wait()
            XCTFail("Managed to reinit somehow")
        } catch let error as NSError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGracefulShutdown() throws {
        let compiler = try newCompiler()
        XCTAssertNoThrow(try compiler.shutdownGracefully().wait())

        // No child process
        XCTAssertNil(try compiler.compilerProcessIdentifier.wait())

        // Shutdown again is OK
        XCTAssertNoThrow(try compiler.shutdownGracefully().wait())

        // Reinit is not OK
        XCTAssertThrowsError(try compiler.reinit().wait())

        // Compilation is not OK
        XCTAssertThrowsError(try checkCompilerWorking(compiler))

    }

    func testStuckShutdown() throws {
        let badCompiler = try newBadCompiler()

        // job hangs
        let compileResult = badCompiler.compileAsync(text: "")
        // shutdown hangs waiting for job
        let shutdownResult1 = badCompiler.shutdownGracefully()
        // second chaser shutdown doesn't mess anything up
        let shutdownResult2 = badCompiler.shutdownGracefully()

        // shutdowns both complete OK after the timeout
        XCTAssertNoThrow(try shutdownResult1.wait())
        XCTAssertNoThrow(try shutdownResult2.wait())
        // job fails with timeout
        XCTAssertThrowsError(try compileResult.wait())
    }

    // TODO: restart delayed by client-side quiesce
    //       restart delayed by client-side quiesce, further error occurs
}
