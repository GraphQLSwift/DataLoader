// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DataLoader",
    products: [
        .library(name: "DataLoader", targets: ["DataLoader"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "DataLoader", dependencies: ["NIO", "NIOConcurrencyHelpers"]),
        .testTarget(name: "DataLoaderTests", dependencies: ["DataLoader"]),
    ],
    swiftLanguageVersions: [.v5]
)
