//
//  Concurrency+Extras.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

/// List of waiting tasks with defined/reentrant kicking order
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

// MARK: Sync - a dumb semaphore for testcase injection

actor Sync {
    private var waiting: CheckedContinuation<Void, Never>?

    func wait() async {
        precondition(waiting == nil)
        await withCheckedContinuation { waiting = $0 }
    }

    func resume() {
        precondition(waiting != nil)
        waiting?.resume()
        waiting = nil
    }
}

// MARK: weird things probably meaning I don't understand something

func preconditionFailure(_ msg: String) -> Never {
    Swift.preconditionFailure(msg)
}

func precondition(_ cond: Bool, _ msg: String = "") {
    Swift.precondition(cond, msg)
}
