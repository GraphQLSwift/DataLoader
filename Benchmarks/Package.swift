// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "DataLoader", path: "../"),
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.84.0"),
    ],
    targets: [
        .executableTarget(
            name: "Benchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "AsyncDataLoader", package: "DataLoader"),
                .product(name: "DataLoader", package: "DataLoader"),
                .product(name: "NIO", package: "swift-nio"),
            ],
            path: "Benchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    ]
)
