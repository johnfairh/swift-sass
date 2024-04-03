//
//  TestResetShutdown.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import XCTest
import NIO
import NIOCore
@testable import DartSass

///
/// Tests around resets, timeouts, and shutdown.
///
class TestResetShutdown: DartSassTestCase {
    // Clean restart case
    func testCleanRestart() async throws {
        let compiler = try newCompiler()
        await compiler.waitForRunning()
        await XCTAssertEqualA(1, await compiler.startCount)

        try await compiler.reinit()
        await XCTAssertEqualA(2, await compiler.startCount)
    }

    // Early reset
    func testEarlyReset() async throws {
        await setSuspend(at: .initThunk)
        let compiler = try newCompiler()
        await testSuspend?.waitUntilSuspended(at: .initThunk)
        async let _ = compiler.shutdownGracefully()
        await testSuspend?.resume(from: .initThunk)
    }

    // Deal with missing child & SIGPIPE-avoidance measures
    func testChildTermination() async throws {
        let compiler = try newCompiler()
        let pid = await compiler.compilerProcessIdentifier!
        await compiler.waitForRunning()

        stopProcess(pid: pid)

        await checkProtocolError(compiler)

        // check recovered
        try await checkCompilerWorking(compiler)
    }

    // Check we detect stuck requests
    func testTimeout() async throws {
        let badCompiler = try await newBadCompiler()

        await checkProtocolError(badCompiler, "Timeout")
    }

    // Test disabling the timeout works

    final class VarBox<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    func testTimeoutDisabled() async throws {
        let badCompiler = try await newBadCompiler(timeout: -1)

        let compilationComplete = VarBox(false)

        let compileResult = Task {
            let result = try await badCompiler.compile(string: "")
            compilationComplete.value = true
            return result
        }

        try? await Task.sleep(for: .seconds(1))
        XCTAssertFalse(compilationComplete.value)
        try await badCompiler.reinit()

        do {
            let results = try await compileResult.value
            XCTFail("Shouldn't have compiled! \(results)")
        } catch let error as LifecycleError {
            XCTAssertTrue(error.description.contains("User requested"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Can't get the thing to acknowledge a write fail without injecting
    // a software thing here.  Furthermore if I run this test standalone
    // then the child dies - but it doesn't in a suite??  Try to bluster
    // through...
    func testWriteFailure() async throws {
        let badCompiler = try await newBadCompiler(timeout: -1)
        await badCompiler.waitForRunning()
        await setSuspend(at: .childTermination)
        await badCompiler.child.outbound.finish()
        do {
            let results = try await badCompiler.compile(string: "")
            XCTFail("Managed to compile: \(results)")
        } catch let error as ProtocolError {
            XCTAssertTrue(error.description.contains("alreadyFinished"))
        }
        await testSuspend?.resumeIf(from: .childTermination)
    }

    // Test the 'compiler will not restart' corner
    func testUnrestartableCompiler() async throws {
        let tmpDir = try FileManager.default.createTemporaryDirectory()
        let realHeadURL = URL(fileURLWithPath: "/usr/bin/tail")
        let tmpHeadURL = tmpDir.appendingPathComponent("tail")
        try FileManager.default.copyItem(at: realHeadURL, to: tmpHeadURL)

        let badCompiler = Compiler(embeddedCompilerFileURL: tmpHeadURL,
                                   timeout: 1)
        await badCompiler.setVersionsResponder(TestVersionsResponder())
        compilersToShutdown.append(badCompiler)
        await badCompiler.waitForRunning()

        // it's now running using the copied program
        try FileManager.default.removeItem(at: tmpHeadURL)

        // Use the instance we have up, will timeout & be killed
        // ho hum, on GitHub Actions sometimes we get a pipe error instead
        // either is fine, as long as it fails somehow.
        await checkProtocolError(badCompiler)
        await badCompiler.waitForBroken()

        // Should be in idle_broken, restart not possible
        await checkProtocolError(badCompiler, "failed to start", protocolNotLifecycle: false)

        // Try to recover - no dice
        do {
            try await badCompiler.reinit()
            XCTFail("Managed to reinit somehow")
        } catch let error as NSError {
            print(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGracefulShutdown() async throws {
        let compiler = try newCompiler()

        // Shutdown
        await compiler.shutdownGracefully()

        // No child process
        let pid = await compiler.compilerProcessIdentifier
        XCTAssertNil(pid)

        // Shutdown again is OK
        await compiler.shutdownGracefully()

        // Reinit is not OK
        await XCTAssertThrowsErrorA(try await compiler.reinit())

        // Compilation is not OK
        await XCTAssertThrowsErrorA(try await checkCompilerWorking(compiler))
    }

    /// Shutdown with outstanding I/O - not as interesting as in V1 which would quiesce first then cancel
    func testStuckShutdown() async throws {
        let badCompiler = try await newBadCompiler()
        await badCompiler.waitForRunning()

        // job hangs
        let compileResult = Task { try await badCompiler.compile(string: "") }

        try? await Task.sleep(for: .milliseconds(300))
        // shutdown hangs waiting for job
        async let shutdowner1: Void = badCompiler.shutdownGracefully()
        // second chaser shutdown doesn't mess anything up
        async let shutdowner2: Void = badCompiler.shutdownGracefully()

        // shutdowns both complete OK after the timeout
        await shutdowner1
        await shutdowner2
        // job fails with timeout
        await XCTAssertThrowsErrorA(try await compileResult.value)
    }

    // Quiesce delayed by client-side activity
    func testClientStuckReset() async throws {
        let importer = HangingAsyncImporter()
        let compiler = try newCompiler(importers: [.importer(importer)])

        importer.state.onLoadHang = {
            await withCheckedContinuation { continuation in
                Compiler.onStuckQuiesce = {
                    Compiler.onStuckQuiesce = nil
                    continuation.resume()
                }
                Task {
                    try await compiler.reinit()
                }
            }
        }

        do {
            let r = try await compiler.compile(string: "@import 'something';")
            XCTFail("It worked?! \(r)")
        } catch {
            // Don't normally check for text but so hard to see if this test has
            // actually worked otherwise.
            XCTAssertEqual("User requested Sass compiler be reinitialized", "\(error)")
        }

        try await checkCompilerWorking(compiler)
    }

    // Internal eventloopgroup
    func testInternalEventLoopGroup() async throws {
        let compiler = try Compiler()
        try await checkCompilerWorking(compiler)
        await compiler.shutdownGracefully()
    }
}
