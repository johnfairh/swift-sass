//
//  DartSassEmbeddedLinux.swift
//  DartSassEmbeddedLinux
//
//  Licensed under MIT (https://github.com/johnfairh/swift-sass/blob/main/LICENSE
//

import Foundation

// This is a wrapper around the Linux Dart Sass Embedded binary that, all being
// well, is linked and packaged only when building for a Linux destination.
//
// This file doesn't take part in the Xcode build so shouldn't belong to any
// target.

public final class DartSassEmbeddedBundle {
    public static var bundle: Bundle? {
        Bundle.module
    }
}
