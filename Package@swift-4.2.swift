// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftDataLoader",
    products: [
        .library(name: "SwiftDataLoader", targets: ["SwiftDataLoader"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.8.0"),
    ],
    targets: [
        .target(name: "SwiftDataLoader", dependencies: ["NIO"]),
        .testTarget(name: "SwiftDataLoaderTests", dependencies: ["SwiftDataLoader"]),
    ],
    swiftLanguageVersions: [.v3, .v4, .v4_2]
)
