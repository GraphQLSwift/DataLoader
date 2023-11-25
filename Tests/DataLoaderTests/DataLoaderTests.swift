import XCTest

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
final class DataLoaderTests: XCTestCase {
    /// Builds a really really simple data loader'
    func testReallyReallySimpleDataLoader() async throws {
        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { keys in
            keys.map { DataLoaderValue.success($0) }
        }

        let value = try await identityLoader.load(key: 1)

        XCTAssertEqual(value, 1)
    }

    /// Supports loading multiple keys in one call
    func testLoadingMultipleKeys() async throws {
        let identityLoader = DataLoader<Int, Int>() { keys in
            keys.map { DataLoaderValue.success($0) }
        }

        let values = try await identityLoader.loadMany(keys: [1, 2])

        XCTAssertEqual(values, [1, 2])

        let empty = try await identityLoader.loadMany(keys: [])

        XCTAssertTrue(empty.isEmpty)
    }

    // Batches multiple requests
    func testMultipleRequests() async throws {
        let loadCalls = Concurrent<[[Int]]>([])

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(
                batchingEnabled: true,
                executionPeriod: nil
            )
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: 1)
        async let value2 = identityLoader.load(key: 2)

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2

        XCTAssertEqual(result1, 1)
        XCTAssertEqual(result2, 2)

        let calls = await loadCalls.wrappedValue

        XCTAssertEqual(calls.map { $0.sorted() }, [[1, 2]])
    }

    /// Batches multiple requests with max batch sizes
    func testMultipleRequestsWithMaxBatchSize() async throws {
        let loadCalls = Concurrent<[[Int]]>([])

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(
                batchingEnabled: true,
                maxBatchSize: 2,
                executionPeriod: nil
            )
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: 1)
        async let value2 = identityLoader.load(key: 2)
        async let value3 = identityLoader.load(key: 3)

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2
        let result3 = try await value3

        XCTAssertEqual(result1, 1)
        XCTAssertEqual(result2, 2)
        XCTAssertEqual(result3, 3)

        let calls = await loadCalls.wrappedValue

        XCTAssertEqual(calls.map { $0.sorted() }, [[1, 2], [3]])
    }

    /// Coalesces identical requests
    func testCoalescesIdenticalRequests() async throws {
        let loadCalls = Concurrent<[[Int]]>([])

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: 1)
        async let value2 = identityLoader.load(key: 1)

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2

        XCTAssertTrue(result1 == 1)
        XCTAssertTrue(result2 == 1)

        let calls = await loadCalls.wrappedValue

        XCTAssertTrue(calls.map { $0.sorted() } == [[1]])
    }

    // Caches repeated requests
    func testCachesRepeatedRequests() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2

        XCTAssertTrue(result1 == "A")
        XCTAssertTrue(result2 == "B")

        let calls = await loadCalls.wrappedValue

        XCTAssertTrue(calls.map { $0.sorted() } == [["A", "B"]])

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "C")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        XCTAssertNil(didFailWithError2)

        let result3 = try await value3
        let result4 = try await value4

        XCTAssertTrue(result3 == "A")
        XCTAssertTrue(result4 == "C")

        let calls2 = await loadCalls.wrappedValue

        XCTAssertTrue(calls2.map { $0.sorted() } == [["A", "B"], ["C"]])

        async let value5 = identityLoader.load(key: "A")
        async let value6 = identityLoader.load(key: "B")
        async let value7 = identityLoader.load(key: "C")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError3: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError3 = error
        }

        XCTAssertNil(didFailWithError3)

        let result5 = try await value5
        let result6 = try await value6
        let result7 = try await value7

        XCTAssertTrue(result5 == "A")
        XCTAssertTrue(result6 == "B")
        XCTAssertTrue(result7 == "C")

        let calls3 = await loadCalls.wrappedValue

        XCTAssertTrue(calls3.map { $0.sorted() } == [["A", "B"], ["C"]])
    }

    /// Clears single value in loader
    func testClearSingleValueLoader() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2

        XCTAssertTrue(result1 == "A")
        XCTAssertTrue(result2 == "B")

        let calls = await loadCalls.wrappedValue

        XCTAssertTrue(calls.map { $0.sorted() } == [["A", "B"]])

        await identityLoader.clear(key: "A")

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        XCTAssertNil(didFailWithError2)

        let result3 = try await value3
        let result4 = try await value4

        XCTAssertTrue(result3 == "A")
        XCTAssertTrue(result4 == "B")

        let calls2 = await loadCalls.wrappedValue

        XCTAssertTrue(calls2.map { $0.sorted() } == [["A", "B"], ["A"]])
    }

    /// Clears all values in loader
    func testClearsAllValuesInLoader() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2

        XCTAssertTrue(result1 == "A")
        XCTAssertTrue(result2 == "B")

        let calls = await loadCalls.wrappedValue

        XCTAssertTrue(calls.map { $0.sorted() } == [["A", "B"]])

        await identityLoader.clearAll()

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        XCTAssertNil(didFailWithError2)

        let result3 = try await value3
        let result4 = try await value4

        XCTAssertTrue(result3 == "A")
        XCTAssertTrue(result4 == "B")

        let calls2 = await loadCalls.wrappedValue

        XCTAssertTrue(calls2.map { $0.sorted() } == [["A", "B"], ["A", "B"]])
    }

    // Allows priming the cache
    func testAllowsPrimingTheCache() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        try await identityLoader.prime(key: "A", value: "A")

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2

        XCTAssertTrue(result1 == "A")
        XCTAssertTrue(result2 == "B")

        let calls = await loadCalls.wrappedValue

        XCTAssertTrue(calls.map { $0.sorted() } == [["B"]])
    }

    /// Does not prime keys that already exist
    func testDoesNotPrimeKeysThatAlreadyExist() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        try await identityLoader.prime(key: "A", value: "X")

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2

        XCTAssertTrue(result1 == "X")
        XCTAssertTrue(result2 == "B")

        try await identityLoader.prime(key: "A", value: "Y")
        try await identityLoader.prime(key: "B", value: "Y")

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        XCTAssertNil(didFailWithError2)

        let result3 = try await value3
        let result4 = try await value4

        XCTAssertTrue(result3 == "X")
        XCTAssertTrue(result4 == "B")

        let calls = await loadCalls.wrappedValue

        XCTAssertTrue(calls.map { $0.sorted() } == [["B"]])
    }

    /// Allows forcefully priming the cache
    func testAllowsForcefullyPrimingTheCache() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        try await identityLoader.prime(key: "A", value: "X")

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        XCTAssertNil(didFailWithError)

        let result1 = try await value1
        let result2 = try await value2

        XCTAssertTrue(result1 == "X")
        XCTAssertTrue(result2 == "B")

        try await identityLoader.clear(key: "A").prime(key: "A", value: "Y")
        try await identityLoader.clear(key: "B").prime(key: "B", value: "Y")

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        XCTAssertNil(didFailWithError2)

        let result3 = try await value3
        let result4 = try await value4

        XCTAssertTrue(result3 == "Y")
        XCTAssertTrue(result4 == "Y")

        let calls = await loadCalls.wrappedValue

        XCTAssertTrue(calls.map { $0.sorted() } == [["B"]])
    }

    func testAutoExecute() async throws {
        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: 2_000_000)
        ) { keys in

            keys.map { DataLoaderValue.success($0) }
        }

        async let value = identityLoader.load(key: "A")

        // Don't manually call execute, but wait for more than 2ms
        usleep(3000)

        let result = try await value

        XCTAssertNotNil(result)
    }

    func testErrorResult() async throws {
        let loaderErrorMessage = "TEST"

        // Test throwing loader without auto-executing
        let throwLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { _ in
            throw DataLoaderError.typeError(loaderErrorMessage)
        }

        async let value = throwLoader.load(key: 1)

        try await Task.sleep(nanoseconds: 2_000_000)

        var didFailWithError: DataLoaderError?

        do {
            _ = try await throwLoader.execute()
        } catch {
            didFailWithError = error as? DataLoaderError
        }

        XCTAssertNil(didFailWithError)

        var didFailWithError2: DataLoaderError?

        do {
            _ = try await value
        } catch {
            didFailWithError2 = error as? DataLoaderError
        }

        var didFailWithErrorText2 = ""

        switch didFailWithError2 {
        case let .typeError(text):
            didFailWithErrorText2 = text
        case .noValueForKey:
            break
        case .none:
            break
        }

        XCTAssertEqual(didFailWithErrorText2, loaderErrorMessage)

        // Test throwing loader with auto-executing
        let throwLoaderAutoExecute = DataLoader<Int, Int>(
            options: DataLoaderOptions()
        ) { _ in
            throw DataLoaderError.typeError(loaderErrorMessage)
        }

        async let valueAutoExecute = throwLoaderAutoExecute.load(key: 1)

        var didFailWithError3: DataLoaderError?

        do {
            _ = try await valueAutoExecute
        } catch {
            didFailWithError3 = error as? DataLoaderError
        }

        var didFailWithErrorText3 = ""

        switch didFailWithError3 {
        case let .typeError(text):
            didFailWithErrorText3 = text
        case .noValueForKey:
            break
        case .none:
            break
        }

        XCTAssertEqual(didFailWithErrorText3, loaderErrorMessage)
    }
}
