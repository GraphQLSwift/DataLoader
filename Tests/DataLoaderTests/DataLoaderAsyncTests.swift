import XCTest
import NIO

@testable import DataLoader

#if compiler(>=5.5) && canImport(_Concurrency)

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

        XCTAssertEqual(values, [1,2])

        let empty = try await identityLoader.loadMany(keys: [], on: eventLoopGroup)

        XCTAssertTrue(empty.isEmpty)
    }

    // Batches multiple requests
    func testMultipleRequests() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        actor LoadCalls {
            var loadCalls = [[Int]]()

            func append(_ calls: [Int]) {
                loadCalls.append(calls)
            }

            static let shared: LoadCalls = .init()
        }

        let identityLoader = DataLoader<Int, Int>(
            on: eventLoopGroup.next(),
            options: DataLoaderOptions(
                batchingEnabled: true,
                executionPeriod: nil
            )
        ) { keys in
            await LoadCalls.shared.append(keys)
            let task = Task {
                keys.map { DataLoaderFutureValue.success($0) }
            }
            return await task.value
        }

        async let value1 = identityLoader.load(key: 1, on: eventLoopGroup)
        async let value2 = identityLoader.load(key: 2, on: eventLoopGroup)
        
        /// Have to wait for a split second because Tasks may not be executed before this statement
        try await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNoThrow(try identityLoader.execute())
        
        let result1 = try await value1
        XCTAssertEqual(result1, 1)
        let result2 = try await value2
        XCTAssertEqual(result2, 2)

        let loadCalls = await LoadCalls.shared.loadCalls
        XCTAssertEqual(loadCalls, [[1,2]])
    }
}

#endif