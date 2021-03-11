// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "swift-sass",
    platforms: [
      .macOS("11.0"),
    ],
    products: [
      .library(
        name: "SassEmbedded",
        targets: ["SassEmbedded"]),
      .executable(
        name: "ssassc",
        targets: ["Cli"]),
    ],
    dependencies: [
      .package(
        name: "SwiftProtobuf",
        url: "https://github.com/apple/swift-protobuf.git",
        from: "1.14.0"),
      .package(
        name: "swift-nio",
        url: "https://github.com/apple/swift-nio.git",
        from: "2.25.0"),
      .package(
        name: "swift-log",
        url: "https://github.com/apple/swift-log.git",
        from: "1.4.0"),
      .package(
        name: "Semver",
        url: "https://github.com/johnfairh/Semver.swift.git",
        from: "1.2.2"),
    ],
    targets: [
      .target(name: "Sass"),
      .target(
        name: "SassEmbedded",
        dependencies: [
          .target(name: "Sass"),
          .target(name: "DartSassEmbeddedMacOS",
              condition: .when(platforms: [.macOS])),
          .target(name: "DartSassEmbeddedLinux",
              condition: .when(platforms: [.linux])),
          .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
          .product(name: "NIO", package: "swift-nio"),
          .product(name: "NIOFoundationCompat", package: "swift-nio"),
          .product(name: "Logging", package: "swift-log"),
          .product(name: "Semver", package: "Semver"),
        ]),
      .target(
        name: "DartSassEmbeddedMacOS",
        resources: [.copy("sass_embedded")]),
      .target(
        name: "DartSassEmbeddedLinux",
        resources: [.copy("sass_embedded")]),
      .testTarget(
        name: "SassEmbeddedTests",
        dependencies: ["SassEmbedded"],
        exclude: ["dart-sass-embedded"]),
      .testTarget(
        name: "SassTests",
        dependencies: ["Sass"]),
      .target(
        name: "Cli",
        dependencies: ["SassEmbedded"]),
    ]
)
