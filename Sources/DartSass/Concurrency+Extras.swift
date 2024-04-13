//
//  Concurrency+Extras.swift
//  DartSass
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

// MARK: Lock

import class Dispatch.DispatchSemaphore

/// Quick non-async lock
struct Lock {
    private let dsem: DispatchSemaphore

    init() {
        dsem = DispatchSemaphore(value: 1)
    }

    func locked<T>(_ call: () throws -> T) rethrows -> T {
        dsem.wait()
        defer { dsem.signal() }
        return try call()
    }
}

// MARK: ContinuationQueue

/// List of waiting tasks with defined/reentrant kicking order
actor ContinuationQueue {
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

// MARK: TestSuspend

enum TestSuspendPoint {
    case initThunk
    case endOfInitializing
    case sendVersionRequest
    case childTermination
}

protocol TestSuspendHook: Sendable {
    func suspend(for point: TestSuspendPoint) async
}

nonisolated(unsafe) var TestSuspend: (any TestSuspendHook)?

// MARK: weird things probably meaning I don't understand something

func precondition(_ cond: Bool, _ msg: String = "") {
    Swift.precondition(cond, msg)
}
