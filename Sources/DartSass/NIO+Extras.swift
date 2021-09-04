//
//  NIO+Extras.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIO
import Dispatch

extension NIOThreadPool {
    /// I'm probably doing something wrong by having a thread in service to my event loop but oh well.
    /// Provide a event-loop friendly shutdown API.
    func shutdownGracefully(eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        shutdownGracefully { error in
            if let error = error {
                promise.fail(error) // this is in fact unreachable in current NIO...
            } else {
                promise.succeed(())
            }
        }
        return promise.futureResult
    }
}

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

    func shutdownGracefully(queue: DispatchQueue, _ callback: @escaping (Error?) -> Void) {
        switch provider {
        case .shared:
            queue.async {
                callback(nil)
            }
        case .createNew:
            eventLoopGroup.shutdownGracefully(queue: queue, callback)
        }
    }

    func syncShutdownGracefully() throws {
        switch provider {
        case .shared:
            break
        case .createNew:
            try eventLoopGroup.syncShutdownGracefully()
        }
    }

    func next() -> EventLoop {
        eventLoopGroup.next()
    }
}

extension Result {
    var error: Error? {
        switch self {
        case .failure(let e): return e
        case .success: return nil
        }
    }
}
