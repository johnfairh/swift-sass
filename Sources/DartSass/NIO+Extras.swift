//
//  NIO+Extras.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIOCore
import NIOPosix

/// This eventloopgroupprovide thing is like, a hint at a reasonable API ... why does it have NIO in the name ...
/// Try to wrap it up into something less unwieldy.
final class ProvidedEventLoopGroup {
    private let provider: NIOEventLoopGroupProvider
    let eventLoopGroup: EventLoopGroup

    init(_ provider: NIOEventLoopGroupProvider) {
        self.provider = provider
        switch provider {
        case .shared(let elg):
            eventLoopGroup = elg
        case .createNew:
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        }
    }

    func shutdownGracefully() async throws {
        switch provider {
        case .shared:
            return
        case .createNew:
            try await eventLoopGroup.shutdownGracefully()
        }
    }

    func any() -> EventLoop {
        eventLoopGroup.any()
    }
}
