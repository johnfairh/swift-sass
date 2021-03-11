// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "swift-sass",
    platforms: [
      .macOS("11.0"),
    ],
    products: [
      .library(
        name: "DartSass",
        targets: ["DartSass"]),
      .library(
        name: "SassLibSass",
        targets: ["SassLibSass"]),
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
        from: "2.36.0"),
      .package(
        name: "swift-log",
        url: "https://github.com/apple/swift-log.git",
        from: "1.4.0"),
      .package(
        name: "Semver",
        url: "https://github.com/johnfairh/Semver.swift.git",
        from: "1.2.2"),
      .package(
        name: "SourceMapper",
        url: "https://github.com/johnfairh/SourceMapper.git",
        from: "1.0.0"),
    ],
    targets: [
      .target(
        name: "Sass",
        dependencies: ["SourceMapper"]),
      .target(
        name: "DartSass",
        dependencies: [
          .target(name: "Sass"),
          .target(name: "DartSassEmbeddedMacOS",
              condition: .when(platforms: [.macOS])),
          .target(name: "DartSassEmbeddedLinux",
              condition: .when(platforms: [.linux])),
          .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
          .product(name: "NIOCore", package: "swift-nio"),
          .product(name: "NIOPosix", package: "swift-nio"),
          .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
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
      .target(
        name: "TestHelpers",
        path: "Tests/TestHelpers"),
      .testTarget(
        name: "DartSassTests",
        dependencies: ["DartSass"]),
      .testTarget(
        name: "SassTests",
        dependencies: ["Sass"]),
      .executableTarget(
        name: "Cli",
        dependencies: ["DartSass"]),
      .systemLibrary(
        name: "libsass4"),
      .target(
        name: "SassLibSass",
        dependencies: [
          .target(name: "Sass"),
          .target(name: "libsass4")
        ]),
      .testTarget(
        name: "SassLibSassTests",
        dependencies: ["SassLibSass", "TestHelpers"]),
    ]
)
