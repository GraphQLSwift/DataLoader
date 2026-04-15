import NIOPosix
import Testing

@testable import DataLoader

actor Concurrent<T> {
    var wrappedValue: T

    func nonmutating<Returned>(_ action: (T) throws -> Returned) async rethrows -> Returned {
        try action(wrappedValue)
    }

    func mutating<Returned>(_ action: (inout T) throws -> Returned) async rethrows -> Returned {
        try action(&wrappedValue)
    }

    init(_ value: T) {
        wrappedValue = value
    }
}

/// Primary API
struct DataLoaderAsyncTests {
    /// Builds a really really simple data loader with async await
    @Test func reallyReallySimpleDataLoader() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<Int, Int>(
            on: eventLoopGroup.next(),
            options: DataLoaderOptions(batchingEnabled: false)
        ) { keys async in
            let task = Task {
                keys.map { DataLoaderFutureValue.success($0) }
            }
            return await task.value
        }

        let value = try await identityLoader.load(key: 1, on: eventLoopGroup)

        #expect(value == 1)
    }

    /// Supports loading multiple keys in one call
    @Test func loadingMultipleKeys() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<Int, Int>(on: eventLoopGroup.next()) { keys in
            let task = Task {
                keys.map { DataLoaderFutureValue.success($0) }
            }
            return await task.value
        }

        let values = try await identityLoader.loadMany(keys: [1, 2], on: eventLoopGroup)

        #expect(values == [1, 2])

        let empty = try await identityLoader.loadMany(keys: [], on: eventLoopGroup)

        #expect(empty.isEmpty)
    }

    /// Batches multiple requests
    @Test func multipleRequests() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let loadCalls = Concurrent<[[Int]]>([])

        let identityLoader = DataLoader<Int, Int>(
            on: eventLoopGroup.next(),
            options: DataLoaderOptions(
                batchingEnabled: true,
                executionPeriod: nil
            )
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }
            let task = Task {
                keys.map { DataLoaderFutureValue.success($0) }
            }
            return await task.value
        }

        async let value1 = identityLoader.load(key: 1, on: eventLoopGroup)
        async let value2 = identityLoader.load(key: 2, on: eventLoopGroup)

        // Have to wait for a split second because Tasks may not be executed before this
        // statement
        try await Task.sleep(nanoseconds: 500_000_000)

        try identityLoader.execute()

        let result1 = try await value1
        #expect(result1 == 1)
        let result2 = try await value2
        #expect(result2 == 2)

        let calls = await loadCalls.wrappedValue
        #expect(calls.count == 1)
        #expect(calls.map { $0.sorted() } == [[1, 2]])
    }
}
