// swift-tools-version:5.10.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DataLoader",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "DataLoader", targets: ["DataLoader"]),
        .library(name: "AsyncDataLoader", targets: ["AsyncDataLoader"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/adam-fowler/async-collections", from: "0.0.1"),

        // TODO: SM: Revert before merging. Temporarily using PL nio to test fix for NIOCore.
        // .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/PassiveLogic/swift-nio.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "DataLoader",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ]
        ),
        .target(
            name: "AsyncDataLoader",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "AsyncCollections", package: "async-collections"),
            ]
        ),
        .testTarget(
            name: "DataLoaderTests",
            dependencies: [
                "DataLoader",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .testTarget(name: "AsyncDataLoaderTests", dependencies: ["AsyncDataLoader"]),
    ]
)
