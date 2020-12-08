//
//  NIO+Extras.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import NIO

extension NIOThreadPool {
    /// I'm probably doing something wrong by having a thread in service to my event loop but oh well.
    /// Provide a event-loop friendly shutdown API.
    func shutdownGracefully(eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        shutdownGracefully { error in
            if let error = error {
                promise.fail(error)
            } else {
                promise.succeed(())
            }
        }
        return promise.futureResult
    }
}
