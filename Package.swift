// swift-tools-version:5.7

import PackageDescription

// Not cross-compile correct but SPM doesn't expose?
var architectures = ["arm64", "x64"]
#if arch(arm64)
let arch = "arm64"
#else
let arch = "x64"
#endif
let excluded = architectures.filter { $0 != arch }

let package = Package(
    name: "swift-sass",
    platforms: [
      .macOS("13.0"),
    ],
    products: [
      .library(
        name: "DartSass",
        targets: ["DartSass"]),
      .executable(
        name: "ssassc",
        targets: ["SassCli"]),
    ],
    dependencies: [
      .package(
        url: "https://github.com/apple/swift-protobuf.git",
        from: "1.14.0"),
      .package(
        url: "https://github.com/apple/swift-nio.git",
        from: "2.60.0"),
      .package(
        url: "https://github.com/apple/swift-log.git",
        from: "1.4.0"),
      .package(
        url: "https://github.com/apple/swift-atomics.git",
        from: "1.0.2"),
      .package(
        url: "https://github.com/johnfairh/Semver.swift.git",
        from: "1.2.2"),
      .package(
        url: "https://github.com/johnfairh/SourceMapper.git",
        from: "2.0.0"),
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
          .product(name: "SwiftProtobuf", package: "swift-protobuf"),
          .product(name: "NIOCore", package: "swift-nio"),
          .product(name: "NIOPosix", package: "swift-nio"),
          .product(name: "NIOFoundationCompat", package: "swift-nio"),
          .product(name: "Atomics", package: "swift-atomics"),
          .product(name: "Logging", package: "swift-log"),
          .product(name: "Semver", package: "Semver.swift"),
        ]),
      .target(
        name: "DartSassEmbeddedMacOS",
        exclude: excluded,
        resources: [.copy(arch)]),
      .target(
        name: "DartSassEmbeddedLinux",
        exclude: excluded,
        resources: [.copy(arch)]),
      .testTarget(
        name: "DartSassTests",
        dependencies: ["DartSass"]),
      .testTarget(
        name: "SassTests",
        dependencies: ["Sass"]),
      .executableTarget(
        name: "SassCli",
        dependencies: ["DartSass"]),
    ]
)
