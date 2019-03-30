// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftDataLoader",
    products: [
        .library(
            name: "SwiftDataLoader",
            targets: ["SwiftDataLoader"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.13.2"),
    ],
    targets: [
        .target(
            name: "SwiftDataLoader",
            dependencies: ["NIO"]),
        .testTarget(
            name: "SwiftDataLoaderTests",
            dependencies: ["SwiftDataLoader"]),
    ]
)
