//
//  Concurrency+Extras.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// List of waiting tasks with defined/reentrant kicking order
struct ContinuationQueue {
    typealias Element = CheckedContinuation<Void, Never>
    private var waiting: [Element] = []

    mutating func wait(_ cont: Element) {
        waiting.append(cont)
    }

    mutating func kick() {
        let kicked = waiting
        waiting = []
        kicked.forEach { $0.resume() }
    }
}

/// This works around Swift's maddening Actor composition restrictions.  Tough if you need separate queues...
protocol WithContinuationQueue: Actor {
    var continuationQueue: ContinuationQueue { get set }
}

extension WithContinuationQueue {
    func suspendTask() async {
        await withCheckedContinuation { continuation in
            continuationQueue.wait(continuation)
        }
    }

    func kickWaitingTasks() {
        continuationQueue.kick()
    }
}
