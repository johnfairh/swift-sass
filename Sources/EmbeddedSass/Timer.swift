//
//  Timer.swift
//  EmbeddedSass
//
//  Copyright 2020 swift-sass contributors
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/master/LICENSE)
//

import Foundation

/// Cross-platform monotonic timer
struct Timer {
    let start: time_t

    private static var seconds: time_t {
        var tv = timespec()
        let rc = clock_gettime(CLOCK_MONOTONIC, &tv)
        precondition(rc == 0)
        return tv.tv_sec
    }

    /// Start a timer
    init() {
        start = Timer.seconds
    }

    /// How many complete seconds have elapsed since the timer started
    var elapsed: Int {
        Timer.seconds - start
    }
}
