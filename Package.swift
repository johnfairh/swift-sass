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
    ],
    targets: [
        .target(
            name: "DartSass",
            dependencies: []),
        .testTarget(
            name: "DartSassTests",
            dependencies: ["DartSass"]),
    ]
)
