// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DataLoader",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "DataLoader", targets: ["DataLoader"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0-beta.1"),
        .package(url: "https://github.com/adam-fowler/async-collections", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "DataLoader",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "AsyncCollections", package: "async-collections"),
            ]
        ),
        .testTarget(name: "DataLoaderTests", dependencies: ["DataLoader"]),
    ]
)
