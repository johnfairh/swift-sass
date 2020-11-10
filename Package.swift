// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "swift-sass",
    products: [
        .library(
            name: "DartSass",
            targets: ["DartSass"]),
    ],
    dependencies: [
      .package(
        name: "SwiftProtobuf",
        url: "https://github.com/apple/swift-protobuf.git",
        from: "1.6.0"),
    ],
    targets: [
      .target(
        name: "DartSass",
        dependencies: ["SwiftProtobuf"]),
      .testTarget(
        name: "DartSassTests",
        dependencies: ["DartSass"],
        exclude: ["dart-sass-embedded"]),
    ]
)
