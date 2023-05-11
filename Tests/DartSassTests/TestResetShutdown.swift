//
//  TestResetShutdown.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

//import XCTest
//import NIO
//@testable import DartSass
//
/////
///// Tests around resets, timeouts, and shutdown.
/////
//class TestResetShutdown: DartSassTestCase {
//    // Clean restart case
//    func testCleanRestart() throws {
//        try asyncTest(asyncTestCleanRestart)
//    }
//
//    func asyncTestCleanRestart() async throws {
//        let compiler = try newCompiler()
//        await compiler.sync()
//        XCTAssertEqual(1, compiler.startCount)
//
//        await XCTAssertNoThrowA(try await compiler.reinit())
//        XCTAssertEqual(2, compiler.startCount)
//    }
//
//    // Deal with missing child & SIGPIPE-avoidance measures
//    func testChildTermination() throws {
//        try asyncTest(asyncTestChildTermination)
//    }
//
//    func asyncTestChildTermination() async throws {
//        let compiler = try newCompiler()
//        let pid = await compiler.compilerProcessIdentifier!
//        // This seems super flakey on Linux in particular, have upgraded from SIGTERM to SIGKILL
//        // but still sometimes the process doesn't die and happily services the compilation...
//        let rc = kill(pid, SIGKILL)
//        XCTAssertEqual(0, rc)
//        print("XCKilled compiler process \(pid)")
//        checkProtocolError(compiler)
//
//        // check recovered
//        try checkCompilerWorking(compiler)
//    }
//
//    // Check we detect stuck requests
//    func testTimeout() throws {
//        let badCompiler = try newBadCompiler()
//
//        checkProtocolError(badCompiler, "Timeout")
//    }
//
//    // Test disabling the timeout works
//    func testTimeoutDisabled() throws {
//        try asyncTest(asyncTestTimeoutDisabled)
//    }
//
//    final class VarBox<T>: @unchecked Sendable {
//        var value: T
//        init(_ value: T) { self.value = value }
//    }
//
//    func asyncTestTimeoutDisabled() async throws {
//        let badCompiler = try newBadCompiler(timeout: -1)
//
//        let compilationComplete = VarBox(false)
//
//        let compileResult = Task<CompilerResults, Error> {
//            let result = try await badCompiler.compile(string: "")
//            compilationComplete.value = true
//            return result
//        }
//
//        _ = try await Task {
//            try? await Task.sleep(nanoseconds: 1000 * 1000 * 1000)
//            XCTAssertFalse(compilationComplete.value)
//            try await badCompiler.reinit()
//        }.value
//
//        do {
//            let results = try await compileResult.value
//            XCTFail("Shouldn't have compiled! \(results)")
//        } catch let error as LifecycleError {
//            XCTAssertTrue(error.description.contains("User requested"))
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//
//    // Test the 'compiler will not restart' corner
//    func testUnrestartableCompiler() throws {
//        try asyncTest(asyncTestUnrestartableCompiler)
//    }
//
//    func asyncTestUnrestartableCompiler() async throws {
//        let tmpDir = try FileManager.default.createTemporaryDirectory()
//        let realHeadURL = URL(fileURLWithPath: "/usr/bin/tail")
//        let tmpHeadURL = tmpDir.appendingPathComponent("tail")
//        try FileManager.default.copyItem(at: realHeadURL, to: tmpHeadURL)
//
//        let badCompiler = Compiler(eventLoopGroupProvider: .shared(eventLoopGroup),
//                                   embeddedCompilerFileURL: tmpHeadURL,
//                                   timeout: 1)
//        badCompiler.versionsResponder = TestVersionsResponder()
//        compilersToShutdown.append(badCompiler)
//        await badCompiler.sync()
//
//        // it's now running using the copied program
//        try FileManager.default.removeItem(at: tmpHeadURL)
//
//        // Use the instance we have up, will timeout & be killed
//        // ho hum, on GitHub Actions sometimes we get a pipe error instead
//        // either is fine, as long as it fails somehow.
//        checkProtocolError(badCompiler)
//
//        // Should be in idle_broken, restart not possible
//        checkProtocolError(badCompiler, "failed to restart", protocolNotLifecycle: false)
//
//        // Try to recover - no dice
//        do {
//            try await badCompiler.reinit()
//            XCTFail("Managed to reinit somehow")
//        } catch let error as NSError {
//            print(error)
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//
//    func testGracefulShutdown() throws {
//        try asyncTest(asyncTestGracefulShutdown)
//    }
//
//    func asyncTestGracefulShutdown() async throws {
//        let compiler = try newCompiler()
//
//        // Async shutdown
//        try await compiler.shutdownGracefully()
//
//        // No child process
//        let pid = await compiler.compilerProcessIdentifier
//        XCTAssertNil(pid)
//
//        // Shutdown again is OK
//        try await compiler.shutdownGracefully()
//
//        // Reinit is not OK
//        await XCTAssertThrowsErrorA(try await compiler.reinit())
//
//        // Compilation is not OK
//        XCTAssertThrowsError(try checkCompilerWorking(compiler))
//    }
//
//    func testStuckShutdown() throws {
//        try asyncTest(asyncTestStuckShutdown)
//    }
//
//    func asyncTestStuckShutdown() async throws {
//        let badCompiler = try newBadCompiler()
//
//        // job hangs
//        let compileResult = Task { try await badCompiler.compile(string: "") }
//        // shutdown hangs waiting for job
//        let shutdowner1 = Task { try await badCompiler.shutdownGracefully() }
//        // second chaser shutdown doesn't mess anything up
//        let shutdowner2 = Task { try await badCompiler.shutdownGracefully() }
//
//        // shutdowns both complete OK after the timeout
//        try await shutdowner1.value
//        try await shutdowner2.value
//        // job fails with timeout
//        await XCTAssertThrowsErrorA(try await compileResult.value)
//    }
//
//    // Quiesce delayed by client-side activity
//    func testClientStuckReset() throws {
//        try asyncTest(asyncTestClientStuckReset)
//    }
//
//    func asyncTestClientStuckReset() async throws {
//        let importer = HangingAsyncImporter()
//        let compiler = try newCompiler(importers: [.importer(importer)])
//
//        importer.state.onLoadHang = {
//            await withCheckedContinuation { continuation in
//                CompilerWork.onStuckQuiesce = {
//                    CompilerWork.onStuckQuiesce = nil
//                    continuation.resume()
//                }
//                Task {
//                    try await compiler.reinit()
//                }
//            }
//        }
//
//        do {
//            let r = try await compiler.compile(string: "@import 'something';")
//            XCTFail("It worked?! \(r)")
//        } catch {
//            // Don't normally check for text but so hard to see if this test has
//            // actually worked otherwise.
//            XCTAssertEqual("User requested Sass compiler be reinitialized", "\(error)")
//        }
//
//        try checkCompilerWorking(compiler)
//    }
//
//    // Internal eventloopgroup
//    func testInternalEventLoopGroup() throws {
//        let compiler = try Compiler(eventLoopGroupProvider: .createNew)
//        let results = try compiler.compile(string: "")
//        XCTAssertEqual("", results.css)
//        try compiler.syncShutdownGracefully()
//    }
//
//    // Internal eventloopgroup, async shutdown
//    func testInternalEventLoopGroupAsync() throws {
//        try asyncTest(asyncTestInternalEventLoopGroupAsync)
//    }
//
//    func asyncTestInternalEventLoopGroupAsync() async throws {
//        let compiler = try Compiler(eventLoopGroupProvider: .createNew)
//        let results = try await compiler.compile(string: "")
//        XCTAssertEqual("", results.css)
//        try await compiler.shutdownGracefully()
//    }
//}
