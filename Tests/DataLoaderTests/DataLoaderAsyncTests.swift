import NIOPosix
import XCTest

@testable import DataLoader

#if compiler(>=5.5) && canImport(_Concurrency)

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
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
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    final class DataLoaderAsyncTests: XCTestCase {
        /// Builds a really really simple data loader with async await
        func testReallyReallySimpleDataLoader() async throws {
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            defer {
                XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
            }

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

            XCTAssertEqual(value, 1)
        }

        /// Supports loading multiple keys in one call
        func testLoadingMultipleKeys() async throws {
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            defer {
                XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
            }

            let identityLoader = DataLoader<Int, Int>(on: eventLoopGroup.next()) { keys in
                let task = Task {
                    keys.map { DataLoaderFutureValue.success($0) }
                }
                return await task.value
            }

            let values = try await identityLoader.loadMany(keys: [1, 2], on: eventLoopGroup)

            XCTAssertEqual(values, [1, 2])

            let empty = try await identityLoader.loadMany(keys: [], on: eventLoopGroup)

            XCTAssertTrue(empty.isEmpty)
        }

        // Batches multiple requests
        func testMultipleRequests() async throws {
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            defer {
                XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
            }

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

            /// Have to wait for a split second because Tasks may not be executed before this
            /// statement
            try await Task.sleep(nanoseconds: 500_000_000)

            XCTAssertNoThrow(try identityLoader.execute())

            let result1 = try await value1
            XCTAssertEqual(result1, 1)
            let result2 = try await value2
            XCTAssertEqual(result2, 2)

            let calls = await loadCalls.wrappedValue
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.map { $0.sorted() }, [[1, 2]])
        }
    }

#endif
