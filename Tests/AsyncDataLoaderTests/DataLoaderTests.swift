import Foundation
import Testing

@testable import AsyncDataLoader

let sleepConstant = UInt64(2_000_000)

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
/// The `try await Task.sleep(nanoseconds: 2_000_000)` introduces a small delay to simulate
/// asynchronous behavior and ensure that concurrent requests (`value1`, `value2`...)
/// are grouped into a single batch for processing, as intended by the batching settings.
struct DataLoaderTests {
    /// Builds a really really simple data loader'
    @Test func reallyReallySimpleDataLoader() async throws {
        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { keys in
            keys.map { DataLoaderValue.success($0) }
        }

        let value = try await identityLoader.load(key: 1)

        #expect(value == 1)
    }

    /// Supports loading multiple keys in one call
    @Test func loadingMultipleKeys() async throws {
        let identityLoader = DataLoader<Int, Int> { keys in
            keys.map { DataLoaderValue.success($0) }
        }

        let values = try await identityLoader.loadMany(keys: [1, 2])

        #expect(values == [1, 2])

        let empty = try await identityLoader.loadMany(keys: [])

        #expect(empty.isEmpty)
    }

    /// Batches multiple requests
    @Test func multipleRequests() async throws {
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

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2

        #expect(result1 == 1)
        #expect(result2 == 2)

        let calls = await loadCalls.wrappedValue

        #expect(calls.map { $0.sorted() } == [[1, 2]])
    }

    /// Batches multiple requests with max batch sizes
    @Test func multipleRequestsWithMaxBatchSize() async throws {
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

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2
        let result3 = try await value3

        #expect(result1 == 1)
        #expect(result2 == 2)
        #expect(result3 == 3)

        let calls = await loadCalls.wrappedValue

        #expect(calls.first?.count == 2)
        #expect(calls.last?.count == 1)
    }

    /// Coalesces identical requests
    @Test func coalescesIdenticalRequests() async throws {
        let loadCalls = Concurrent<[[Int]]>([])

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: 1)
        async let value2 = identityLoader.load(key: 1)

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2

        #expect(result1 == 1)
        #expect(result2 == 1)

        let calls = await loadCalls.wrappedValue

        #expect(calls.map { $0.sorted() } == [[1]])
    }

    /// Caches repeated requests
    @Test func cachesRepeatedRequests() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2

        #expect(result1 == "A")
        #expect(result2 == "B")

        let calls = await loadCalls.wrappedValue

        #expect(calls.map { $0.sorted() } == [["A", "B"]])

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "C")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        #expect(didFailWithError2 == nil)

        let result3 = try await value3
        let result4 = try await value4

        #expect(result3 == "A")
        #expect(result4 == "C")

        let calls2 = await loadCalls.wrappedValue

        #expect(calls2.map { $0.sorted() } == [["A", "B"], ["C"]])

        async let value5 = identityLoader.load(key: "A")
        async let value6 = identityLoader.load(key: "B")
        async let value7 = identityLoader.load(key: "C")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError3: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError3 = error
        }

        #expect(didFailWithError3 == nil)

        let result5 = try await value5
        let result6 = try await value6
        let result7 = try await value7

        #expect(result5 == "A")
        #expect(result6 == "B")
        #expect(result7 == "C")

        let calls3 = await loadCalls.wrappedValue

        #expect(calls3.map { $0.sorted() } == [["A", "B"], ["C"]])
    }

    /// Clears single value in loader
    @Test func clearSingleValueLoader() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2

        #expect(result1 == "A")
        #expect(result2 == "B")

        let calls = await loadCalls.wrappedValue

        #expect(calls.map { $0.sorted() } == [["A", "B"]])

        await identityLoader.clear(key: "A")

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        #expect(didFailWithError2 == nil)

        let result3 = try await value3
        let result4 = try await value4

        #expect(result3 == "A")
        #expect(result4 == "B")

        let calls2 = await loadCalls.wrappedValue

        #expect(calls2.map { $0.sorted() } == [["A", "B"], ["A"]])
    }

    /// Clears all values in loader
    @Test func clearsAllValuesInLoader() async throws {
        let loadCalls = Concurrent<[[String]]>([])

        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { keys in
            await loadCalls.mutating { $0.append(keys) }

            return keys.map { DataLoaderValue.success($0) }
        }

        async let value1 = identityLoader.load(key: "A")
        async let value2 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2

        #expect(result1 == "A")
        #expect(result2 == "B")

        let calls = await loadCalls.wrappedValue

        #expect(calls.map { $0.sorted() } == [["A", "B"]])

        await identityLoader.clearAll()

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        #expect(didFailWithError2 == nil)

        let result3 = try await value3
        let result4 = try await value4

        #expect(result3 == "A")
        #expect(result4 == "B")

        let calls2 = await loadCalls.wrappedValue

        #expect(calls2.map { $0.sorted() } == [["A", "B"], ["A", "B"]])
    }

    /// Allows priming the cache
    @Test func allowsPrimingTheCache() async throws {
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

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2

        #expect(result1 == "A")
        #expect(result2 == "B")

        let calls = await loadCalls.wrappedValue

        #expect(calls.map { $0.sorted() } == [["B"]])
    }

    /// Does not prime keys that already exist
    @Test func doesNotPrimeKeysThatAlreadyExist() async throws {
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

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2

        #expect(result1 == "X")
        #expect(result2 == "B")

        try await identityLoader.prime(key: "A", value: "Y")
        try await identityLoader.prime(key: "B", value: "Y")

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        #expect(didFailWithError2 == nil)

        let result3 = try await value3
        let result4 = try await value4

        #expect(result3 == "X")
        #expect(result4 == "B")

        let calls = await loadCalls.wrappedValue

        #expect(calls.map { $0.sorted() } == [["B"]])
    }

    /// Allows forcefully priming the cache
    @Test func allowsForcefullyPrimingTheCache() async throws {
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

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError = error
        }

        #expect(didFailWithError == nil)

        let result1 = try await value1
        let result2 = try await value2

        #expect(result1 == "X")
        #expect(result2 == "B")

        try await identityLoader.clear(key: "A").prime(key: "A", value: "Y")
        try await identityLoader.clear(key: "B").prime(key: "B", value: "Y")

        async let value3 = identityLoader.load(key: "A")
        async let value4 = identityLoader.load(key: "B")

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError2: Error?

        do {
            _ = try await identityLoader.execute()
        } catch {
            didFailWithError2 = error
        }

        #expect(didFailWithError2 == nil)

        let result3 = try await value3
        let result4 = try await value4

        #expect(result3 == "Y")
        #expect(result4 == "Y")

        let calls = await loadCalls.wrappedValue

        #expect(calls.map { $0.sorted() } == [["B"]])
    }

    @Test func autoExecute() async throws {
        let identityLoader = DataLoader<String, String>(
            options: DataLoaderOptions(executionPeriod: sleepConstant)
        ) { keys in
            keys.map { DataLoaderValue.success($0) }
        }

        async let value = identityLoader.load(key: "A")

        // Don't manually call execute, but wait for more than 2ms
        usleep(3000)

        let result = try await value

        #expect(result == "A")
    }

    @Test func errorResult() async throws {
        let loaderErrorMessage = "TEST"

        // Test throwing loader without auto-executing
        let throwLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(executionPeriod: nil)
        ) { _ in
            throw DataLoaderError.typeError(loaderErrorMessage)
        }

        async let value = throwLoader.load(key: 1)

        try await Task.sleep(nanoseconds: sleepConstant)

        var didFailWithError: DataLoaderError?

        do {
            _ = try await throwLoader.execute()
        } catch {
            didFailWithError = error as? DataLoaderError
        }

        #expect(didFailWithError == nil)

        var didFailWithError2: DataLoaderError?

        do {
            _ = try await value
        } catch {
            didFailWithError2 = error as? DataLoaderError
        }

        var didFailWithErrorText2 = ""

        switch didFailWithError2 {
        case .typeError(let text):
            didFailWithErrorText2 = text
        case .noValueForKey:
            break
        case .none:
            break
        }

        #expect(didFailWithErrorText2 == loaderErrorMessage)

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
        case .typeError(let text):
            didFailWithErrorText3 = text
        case .noValueForKey:
            break
        case .none:
            break
        }

        #expect(didFailWithErrorText3 == loaderErrorMessage)
    }
}
