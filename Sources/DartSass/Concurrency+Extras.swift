//
//  Concurrency+Extras.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

actor ContinuationQueue2 {
    typealias Element = CheckedContinuation<Void, Never>
    private var waiting: [Element] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    func kick() {
        let kicked = waiting
        waiting = []
        kicked.forEach { $0.resume() }
    }
}
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

// MARK: weird things probably meaning I don't understand something

func preconditionFailure(_ msg: String) -> Never {
    Swift.preconditionFailure(msg)
}

func precondition(_ cond: Bool) {
    Swift.precondition(cond)
}
