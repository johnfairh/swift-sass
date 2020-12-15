//
//  TestResetShutdown.swift
//  SassEmbeddedTests
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import NIO
@testable import SassEmbedded

///
/// Tests around resets, timeouts, and shutdown.
///
class TestResetShutdown: SassEmbeddedTestCase {
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
        } catch let error as LifecycleError {
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

        let badCompiler = try Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
                                       embeddedCompilerURL: tmpHeadURL,
                                       timeout: 1)
        compilersToShutdown.append(badCompiler)

        // it's now running using the copied program
        try FileManager.default.removeItem(at: tmpHeadURL)

        // Use the instance we have up, will timeout & be killed
        // ho hum, on GitHub Actions sometimes we get a pipe error instead
        // either is fine, as long as it fails somehow.
        checkProtocolError(badCompiler)

        // Should be in idle_broken, restart not possible
        checkProtocolError(badCompiler, "failed to restart", protocolNotLifecycle: false)

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

    final class CompilerShutdowner {
        let compiler: Compiler
        var callbackMade: Bool
        let sem: DispatchSemaphore

        init(_ compiler: Compiler) {
            self.compiler = compiler
            self.callbackMade = false
            self.sem = DispatchSemaphore(value: 0)
        }

        @discardableResult
        func start() -> Self {
            compiler.shutdownGracefully() { error in
                XCTAssertNil(error)
                self.callbackMade = true
                self.sem.signal()
            }
            return self
        }

        func wait() {
            sem.wait()
            XCTAssertTrue(callbackMade)
        }
    }

    func testGracefulShutdown() throws {
        let compiler = try newCompiler()

        // Regular async shutdown
        CompilerShutdowner(compiler).start().wait()

        // No child process
        XCTAssertNil(try compiler.compilerProcessIdentifier.wait())

        // Shutdown again is OK
        CompilerShutdowner(compiler).start().wait()

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
        let shutdowner1 = CompilerShutdowner(badCompiler)
        shutdowner1.start()
        // second chaser shutdown doesn't mess anything up
        let shutdowner2 = CompilerShutdowner(badCompiler)
        shutdowner2.start()

        // shutdowns both complete OK after the timeout
        shutdowner1.wait()
        shutdowner2.wait()
        // job fails with timeout
        XCTAssertThrowsError(try compileResult.wait())
    }

    // Quiesce delayed by client-side activity
    func testClientStuckReset() throws {
        let importer = HangingAsyncImporter()
        let compiler = try newCompiler(importers: [.importer(importer)])
        let hangDone = importer.hangLoad(eventLoop: compiler.eventLoop)
        let compilerResults = compiler.compileAsync(text: "@import 'something';")
        _ = try hangDone.wait()
        XCTAssertNotNil(importer.loadPromise)
        // now we're all stuck waiting for the client
        let resetDone = compiler.reinit()
        XCTAssertNil(try compiler.compilerProcessIdentifier.wait())
        try importer.resumeLoad()
        try resetDone.wait()
        XCTAssertThrowsError(try compilerResults.wait())
    }

    // Internal eventloopgroup
    func testInternalEventLoopGroup() throws {
        let compiler = try Compiler(eventLoopGroupProvider: .createNew,
                                    embeddedCompilerURL: SassEmbeddedTestCase.dartSassEmbeddedURL)
        let results = try compiler.compile(text: "")
        XCTAssertEqual("", results.css)
        try compiler.syncShutdownGracefully()
    }

    // Internal eventloopgroup, async shutdown
    func testInternalEventLoopGroupAsync() throws {
        let compiler = try Compiler(eventLoopGroupProvider: .createNew,
                                    embeddedCompilerURL: SassEmbeddedTestCase.dartSassEmbeddedURL)
        let results = try compiler.compile(text: "")
        XCTAssertEqual("", results.css)
        CompilerShutdowner(compiler).start().wait()
    }
}
