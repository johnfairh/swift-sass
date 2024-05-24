//
//  TestDartSassService.swift
//  DartSassTests
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import ServiceLifecycle
import ServiceLifecycleTestKit
import Logging
import DartSassService
import XCTest
@testable import DartSass

class TestDartSassService: XCTestCase {
    func testService() async throws {
        let compiler = try Compiler()

        let service = CompilerService(compiler: compiler)

        let serviceGroup = ServiceGroup(
            configuration: .init(
              services: [
                service
              ],
              logger: Logger(label: "ServiceGroup")
            )
        )

        try await testGracefulShutdown { trigger in
            async let grp: Void = serviceGroup.run()

            let results = try await service.compiler.compile(string: "")

            XCTAssertEqual("", results.css)
            print("TRIGGERING...")
            trigger.triggerGracefulShutdown()
            print("TRIGGERED")

            try await grp
        }

        let isShutdown = await compiler.state.isShutdown
        XCTAssertTrue(isShutdown)
    }
}
