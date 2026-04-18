import Benchmark
import NIO
import AsyncDataLoader
import DataLoader

let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

let benchmarks: @Sendable () -> Void = {

    // MARK: Async

    let nonBatchingLoader = DataLoader<Int, Int>(
        options: .init(
            batchingEnabled: true,
            cachingEnabled: false,
        )
    ) { keys in
        keys.map { DataLoaderValue.success($0) }
    }

    let batchingLoader = DataLoader<Int, Int>(
        options: .init(
            batchingEnabled: true,
            cachingEnabled: false,
            maxBatchSize: 10
        )
    ) { keys in
        keys.map { DataLoaderValue.success($0) }
    }

    Benchmark("loadNonBatching") { _ in
        try await withThrowingTaskGroup { group in
            for i in (0..<1_000) {
                group.addTask {
                    try await nonBatchingLoader.load(key: i)
                }
            }
            try await group.waitForAll()
        }
    }

    Benchmark("loadBatching") { _ in
        try await withThrowingTaskGroup { group in
            for i in (0..<1_000) {
                group.addTask {
                    try await batchingLoader.load(key: i)
                }
            }
            try await group.waitForAll()
        }
    }

    Benchmark("loadBatchingMany") { _ in
        let result = try await batchingLoader.loadMany(keys: Array(0..<1_000))
    }

    // MARK: NIO

    let nioNonBatchingLoader = DataLoader<Int, Int>(
        options: .init(
            batchingEnabled: true,
            cachingEnabled: false,
        )
    ) { keys in
        return eventLoopGroup.next().makeSucceededFuture(
            keys.map { DataLoaderFutureValue.success($0) }
        )
    }

    let nioBatchingLoader = DataLoader<Int, Int>(
        options: .init(
            batchingEnabled: true,
            cachingEnabled: false,
            maxBatchSize: 10
        )
    ) { keys in
        return eventLoopGroup.next().makeSucceededFuture(
            keys.map { DataLoaderFutureValue.success($0) }
        )
    }

    Benchmark("nioLoadNonBatching") { _ in
        let futures = try (0..<1_000).map { i in
            try nioNonBatchingLoader.load(key: i, on: eventLoopGroup.next())
        }
        let result = try EventLoopFuture.whenAllSucceed(futures, on: eventLoopGroup.next()).wait()
    }

    Benchmark("nioLoadBatching") { _ in
        let futures = try (0..<1_000).map { i in
            try nioBatchingLoader.load(key: i, on: eventLoopGroup.next())
        }
        let result = try EventLoopFuture.whenAllSucceed(futures, on: eventLoopGroup.next()).wait()
    }

    Benchmark("nioLoadBatchingMany") { _ in
        let result = try nioBatchingLoader.loadMany(keys: Array(0..<1_000), on: eventLoopGroup.next()).wait()
    }
}
