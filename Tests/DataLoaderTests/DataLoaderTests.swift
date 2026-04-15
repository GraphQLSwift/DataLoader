import Dispatch
import NIOCore
import NIOPosix
import Testing

@testable import DataLoader

/// Primary API
struct DataLoaderTests {
    /// Builds a really really simple data loader'
    @Test func reallyReallySimpleDataLoader() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { keys in
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value = try identityLoader.load(key: 1, on: eventLoopGroup).wait()

        #expect(value == 1)
    }

    /// Supports loading multiple keys in one call
    @Test func loadingMultipleKeys() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<Int, Int> { keys in
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let values = try identityLoader.loadMany(keys: [1, 2], on: eventLoopGroup).wait()

        #expect(values == [1, 2])

        let empty = try identityLoader.loadMany(keys: [], on: eventLoopGroup).wait()

        #expect(empty.isEmpty)
    }

    /// Batches multiple requests
    @Test func multipleRequests() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.wait() == 1)
        #expect(try value2.wait() == 2)

        #expect(loadCalls == [[1, 2]])
    }

    /// Batches multiple requests with max batch sizes
    @Test func multipleRequestsWithMaxBatchSize() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.wait() == 1)
        #expect(try value2.wait() == 2)
        #expect(try value3.wait() == 3)

        #expect(loadCalls == [[1, 2], [3]])
    }

    /// Coalesces identical requests
    @Test func coalescesIdenticalRequests() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.map { $0 }.wait() == 1)
        #expect(try value2.map { $0 }.wait() == 1)

        #expect(loadCalls == [[1]])
    }

    /// Caches repeated requests
    @Test func cachesRepeatedRequests() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.wait() == "A")
        #expect(try value2.wait() == "B")
        #expect(loadCalls == [["A", "B"]])

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "C", on: eventLoopGroup)

        try identityLoader.execute()

        #expect(try value3.wait() == "A")
        #expect(try value4.wait() == "C")
        #expect(loadCalls == [["A", "B"], ["C"]])

        let value5 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value6 = try identityLoader.load(key: "B", on: eventLoopGroup)
        let value7 = try identityLoader.load(key: "C", on: eventLoopGroup)

        try identityLoader.execute()

        #expect(try value5.wait() == "A")
        #expect(try value6.wait() == "B")
        #expect(try value7.wait() == "C")
        #expect(loadCalls == [["A", "B"], ["C"]])
    }

    /// Clears single value in loader
    @Test func clearSingleValueLoader() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.wait() == "A")
        #expect(try value2.wait() == "B")
        #expect(loadCalls == [["A", "B"]])

        _ = identityLoader.clear(key: "A")

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "B", on: eventLoopGroup)

        try identityLoader.execute()

        #expect(try value3.wait() == "A")
        #expect(try value4.wait() == "B")
        #expect(loadCalls == [["A", "B"], ["A"]])
    }

    /// Clears all values in loader
    @Test func clearsAllValuesInLoader() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.wait() == "A")
        #expect(try value2.wait() == "B")
        #expect(loadCalls == [["A", "B"]])

        _ = identityLoader.clearAll()

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "B", on: eventLoopGroup)

        try identityLoader.execute()

        #expect(try value3.wait() == "A")
        #expect(try value4.wait() == "B")
        #expect(loadCalls == [["A", "B"], ["A", "B"]])
    }

    /// Allows priming the cache
    @Test func allowsPrimingTheCache() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.wait() == "A")
        #expect(try value2.wait() == "B")
        #expect(loadCalls == [["B"]])
    }

    /// Does not prime keys that already exist
    @Test func doesNotPrimeKeysThatAlreadyExist() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.wait() == "X")
        #expect(try value2.wait() == "B")

        _ = identityLoader.prime(key: "A", value: "Y", on: eventLoopGroup)
        _ = identityLoader.prime(key: "B", value: "Y", on: eventLoopGroup)

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "B", on: eventLoopGroup)

        try identityLoader.execute()

        #expect(try value3.wait() == "X")
        #expect(try value4.wait() == "B")

        #expect(loadCalls == [["B"]])
    }

    /// Allows forcefully priming the cache
    @Test func allowsForcefullyPrimingTheCache() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

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

        try identityLoader.execute()

        #expect(try value1.wait() == "X")
        #expect(try value2.wait() == "B")

        _ = identityLoader.clear(key: "A").prime(key: "A", value: "Y", on: eventLoopGroup)
        _ = identityLoader.clear(key: "B").prime(key: "B", value: "Y", on: eventLoopGroup)

        let value3 = try identityLoader.load(key: "A", on: eventLoopGroup)
        let value4 = try identityLoader.load(key: "B", on: eventLoopGroup)

        try identityLoader.execute()

        #expect(try value3.wait() == "Y")
        #expect(try value4.wait() == "Y")

        #expect(loadCalls == [["B"]])
    }

    /// Caches repeated requests, even if initiated asyncronously
    @Test func cacheConcurrency() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
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

        try identityLoader.execute()

        // Test that the futures themselves are equal (not just the value).
        #expect(value1 == value2)
    }

    @Test func autoExecute() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: .milliseconds(2))
        ) { keys in
            let results = keys.map { DataLoaderFutureValue.success($0) }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let promise = eventLoopGroup.next().makePromise(of: String.self)
        _ = try identityLoader.load(key: "A", on: eventLoopGroup).map { result in
            promise.succeed(result)
        }

        // Don't manually call execute, but wait for the result
        let value = try promise.futureResult.wait()
        #expect(value == "A")
    }

    @Test func errorResult() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let loaderErrorMessage = "TEST"

        // Test throwing loader without auto-executing
        let throwLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { _ in
            throw DataLoaderError.typeError(loaderErrorMessage)
        }

        let value = try throwLoader.load(key: 1, on: eventLoopGroup)
        try throwLoader.execute()
        #expect(throws: DataLoaderError.self) {
            try value.wait()
        }

        // Test throwing loader with auto-executing
        let throwLoaderAutoExecute = DataLoader<Int, Int>(
            options: DataLoaderOptions()
        ) { _ in
            throw DataLoaderError.typeError(loaderErrorMessage)
        }

        #expect(throws: DataLoaderError.self) {
            try throwLoaderAutoExecute.load(key: 1, on: eventLoopGroup).wait()
        }
    }
}
