import NIOCore
import NIOPosix
import XCTest

@testable import DataLoader

/// Primary API
final class DataLoaderTests: XCTestCase {
    /// Builds a really really simple data loader'
    func testReallyReallySimpleDataLoader() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { keys in
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value = try identityLoader.load(key: 1, on: eventLoopGroup).wait()

        XCTAssertEqual(value, 1)
    }

    /// Supports loading multiple keys in one call
    func testLoadingMultipleKeys() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>() { keys in
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let values = try identityLoader.loadMany(keys: [1, 2], on: eventLoopGroup).wait()

        XCTAssertEqual(values, [1, 2])

        let empty = try identityLoader.loadMany(keys: [], on: eventLoopGroup).wait()

        XCTAssertTrue(empty.isEmpty)
    }

    // Batches multiple requests
    func testMultipleRequests() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[Int]]()

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(
                batchingEnabled: true,
                executionPeriod: nil
            )
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: 1, on: eventLoopGroup)
        let value2 = try identityLoader.load(key: 2, on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertEqual(try value1.wait(), 1)
        XCTAssertEqual(try value2.wait(), 2)

        XCTAssertEqual(loadCalls, [[1, 2]])
    }

    /// Batches multiple requests with max batch sizes
    func testMultipleRequestsWithMaxBatchSize() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[Int]]()

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(
                batchingEnabled: true,
                maxBatchSize: 2,
                executionPeriod: nil
            )
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: 1, on: eventLoopGroup)
        let value2 = try identityLoader.load(key: 2, on: eventLoopGroup)
        let value3 = try identityLoader.load(key: 3, on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertEqual(try value1.wait(), 1)
        XCTAssertEqual(try value2.wait(), 2)
        XCTAssertEqual(try value3.wait(), 3)

        XCTAssertEqual(loadCalls, [[1, 2], [3]])
    }

    /// Coalesces identical requests
    func testCoalescesIdenticalRequests() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[Int]]()

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: 1, on: eventLoopGroup)
        let value2 = try identityLoader.load(key: 1, on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value1.map { $0 }.wait() == 1)
        XCTAssertTrue(try value2.map { $0 }.wait() == 1)

        XCTAssertTrue(loadCalls == [[1]])
    }

    // Caches repeated requests
    func testCachesRepeatedRequests() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[String]]()

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value2 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value1.wait() == "A")
        XCTAssertTrue(try value2.wait() == "B")
        XCTAssertTrue(loadCalls == [["A", "B"]])

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "C", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value3.wait() == "A")
        XCTAssertTrue(try value4.wait() == "C")
        XCTAssertTrue(loadCalls == [["A", "B"], ["C"]])

        let value5 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value6 = try identityLoader.load(key: "B", on: eventLoopGroup)
        let value7 = try identityLoader.load(key: "C", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value5.wait() == "A")
        XCTAssertTrue(try value6.wait() == "B")
        XCTAssertTrue(try value7.wait() == "C")
        XCTAssertTrue(loadCalls == [["A", "B"], ["C"]])
    }

    /// Clears single value in loader
    func testClearSingleValueLoader() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[String]]()

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value2 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value1.wait() == "A")
        XCTAssertTrue(try value2.wait() == "B")
        XCTAssertTrue(loadCalls == [["A", "B"]])

        _ = identityLoader.clear(key: "A")

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value3.wait() == "A")
        XCTAssertTrue(try value4.wait() == "B")
        XCTAssertTrue(loadCalls == [["A", "B"], ["A"]])
    }

    /// Clears all values in loader
    func testClearsAllValuesInLoader() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[String]]()

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value2 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value1.wait() == "A")
        XCTAssertTrue(try value2.wait() == "B")
        XCTAssertTrue(loadCalls == [["A", "B"]])

        _ = identityLoader.clearAll()

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value3.wait() == "A")
        XCTAssertTrue(try value4.wait() == "B")
        XCTAssertTrue(loadCalls == [["A", "B"], ["A", "B"]])
    }

    // Allows priming the cache
    func testAllowsPrimingTheCache() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[String]]()

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        _ = identityLoader.prime(key: "A", value: "A", on: eventLoopGroup)

        let value1 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value2 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value1.wait() == "A")
        XCTAssertTrue(try value2.wait() == "B")
        XCTAssertTrue(loadCalls == [["B"]])
    }

    /// Does not prime keys that already exist
    func testDoesNotPrimeKeysThatAlreadyExist() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[String]]()

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        _ = identityLoader.prime(key: "A", value: "X", on: eventLoopGroup)

        let value1 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value2 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value1.wait() == "X")
        XCTAssertTrue(try value2.wait() == "B")

        _ = identityLoader.prime(key: "A", value: "Y", on: eventLoopGroup)
        _ = identityLoader.prime(key: "B", value: "Y", on: eventLoopGroup)

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value3.wait() == "X")
        XCTAssertTrue(try value4.wait() == "B")

        XCTAssertTrue(loadCalls == [["B"]])
    }

    /// Allows forcefully priming the cache
    func testAllowsForcefullyPrimingTheCache() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        var loadCalls = [[String]]()

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            loadCalls.append(keys)
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        _ = identityLoader.prime(key: "A", value: "X", on: eventLoopGroup)

        let value1 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value2 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value1.wait() == "X")
        XCTAssertTrue(try value2.wait() == "B")

        _ = identityLoader.clear(key: "A").prime(key: "A", value: "Y", on: eventLoopGroup)
        _ = identityLoader.clear(key: "B").prime(key: "B", value: "Y", on: eventLoopGroup)

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "B", on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.execute())

        XCTAssertTrue(try value3.wait() == "Y")
        XCTAssertTrue(try value4.wait() == "Y")

        XCTAssertTrue(loadCalls == [["B"]])
    }

    // Caches repeated requests, even if initiated asyncronously
    func testCacheConcurrency() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<String, String>(options: DataLoaderOptions()) { keys in
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        // Populate values from two different dispatch queues, running asynchronously
        var value1: EventLoopFuture<String> = eventLoopGroup.next().makeSucceededFuture("")
        var value2: EventLoopFuture<String> = eventLoopGroup.next().makeSucceededFuture("")
        DispatchQueue(label: "").async {
            value1 = try! identityLoader.load(key: "A", on: eventLoopGroup)
        }
        DispatchQueue(label: "").async {
            value2 = try! identityLoader.load(key: "A", on: eventLoopGroup)
        }

        // Sleep for a few ms ensure that value1 & value2 are populated before continuing
        usleep(1000)

        XCTAssertNoThrow(try identityLoader.execute())

        // Test that the futures themselves are equal (not just the value).
        XCTAssertEqual(value1, value2)
    }

    func testAutoExecute() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: .milliseconds(2))
        ) { keys in
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        var value: String?
        _ = try identityLoader.load(key: "A", on: eventLoopGroup).map { result in
            value = result
        }

        // Don't manually call execute, but wait for more than 2ms
        usleep(3000)

        XCTAssertNotNil(value)
    }

    func testErrorResult() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let loaderErrorMessage = "TEST"

        // Test throwing loader without auto-executing
        let throwLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { _ in
            throw DataLoaderError.typeError(loaderErrorMessage)
        }

        let value = try throwLoader.load(key: 1, on: eventLoopGroup)
        XCTAssertNoThrow(try throwLoader.execute())
        XCTAssertThrowsError(
            try value.wait(),
            loaderErrorMessage
        )

        // Test throwing loader with auto-executing
        let throwLoaderAutoExecute = DataLoader<Int, Int>(
            options: DataLoaderOptions()
        ) { _ in
            throw DataLoaderError.typeError(loaderErrorMessage)
        }

        XCTAssertThrowsError(
            try throwLoaderAutoExecute.load(key: 1, on: eventLoopGroup).wait(),
            loaderErrorMessage
        )
    }
}
