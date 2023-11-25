import Algorithms
import AsyncAlgorithms
import AsyncCollections

public enum DataLoaderValue<T: Sendable>: Sendable {
    case success(T)
    case failure(Error)
}

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

public typealias BatchLoadFunction<Key: Hashable & Sendable, Value: Sendable> = @Sendable (_ keys: [Key]) async throws -> [DataLoaderValue<Value>]
private typealias LoaderQueue<Key: Hashable & Sendable, Value: Sendable> = [(key: Key, channel: Channel<Value, Error>)]

/// DataLoader creates a public API for loading data from a particular
/// data back-end with unique keys such as the id column of a SQL table
/// or document name in a MongoDB database, given a batch loading function.
///
/// Each DataLoader instance contains a unique memoized cache. Use caution
/// when used in long-lived applications or those which serve many users
/// with different access permissions and consider creating a new instance
/// per data request.
public actor DataLoader<Key: Hashable & Sendable, Value: Sendable> {
    private let batchLoadFunction: BatchLoadFunction<Key, Value>
    private let options: DataLoaderOptions<Key, Value>

    private var cache = [Key: Channel<Value, Error>]()
    private var queue = LoaderQueue<Key, Value>()

    private var dispatchScheduled = false

    public init(
        options: DataLoaderOptions<Key, Value> = DataLoaderOptions(),
        batchLoadFunction: @escaping BatchLoadFunction<Key, Value>
    ) {
        self.options = options
        self.batchLoadFunction = batchLoadFunction
    }

    /// Loads a key, returning an `Value` for the value represented by that key.
    public func load(key: Key) async throws -> Value {
        let cacheKey = options.cacheKeyFunction?(key) ?? key

        if options.cachingEnabled, let cached = cache[cacheKey] {
            return try await cached.value
        }

        let channel = Channel<Value, Error>()

        if options.batchingEnabled {
            queue.append((key: key, channel: channel))
            if let executionPeriod = options.executionPeriod, !dispatchScheduled {
                Task.detached {
                    try await Task.sleep(nanoseconds: executionPeriod)
                    try await self.execute()
                }
                dispatchScheduled = true
            }
        } else {
            Task.detached {
                do {
                    let results = try await self.batchLoadFunction([key])
                    if results.isEmpty {
                        await channel.fail(with: DataLoaderError.noValueForKey("Did not return value for key: \(key)"))
                    } else {
                        let result = results[0]
                        switch result {
                        case let .success(value):
                            await channel.fulfill(with: value)
                        case let .failure(error):
                                await channel.fail(with: error)
                        }
                    }
                } catch {
                    await channel.fail(with: error)
                }
            }
        }

        if options.cachingEnabled {
            cache[cacheKey] = channel
        }

        return try await channel.value
    }

    /// Loads multiple keys, promising an array of values:
    ///
    /// ```swift
    /// async let aAndB = try myLoader.loadMany(keys: [ "a", "b" ])
    /// ```
    ///
    /// This is equivalent to the more verbose:
    ///
    /// ```swift
    /// async let aAndB = [
    ///   myLoader.load(key: "a"),
    ///   myLoader.load(key: "b")
    /// ]
    /// ```
    /// or
    /// ```swift
    /// async let a = myLoader.load(key: "a")
    /// async let b = myLoader.load(key: "b")
    /// let aAndB = try await a + b
    /// ```
    public func loadMany(keys: [Key]) async throws -> [Value] {
        guard !keys.isEmpty else {
            return []
        }
        let futures = try await keys.concurrentMap { try await self.load(key: $0) }
        return futures
    }

    /// Clears the value at `key` from the cache, if it exists. Returns itself for
    /// method chaining.
    @discardableResult
    public func clear(key: Key) -> DataLoader<Key, Value> {
        let cacheKey = options.cacheKeyFunction?(key) ?? key
        cache.removeValue(forKey: cacheKey)
        return self
    }

    /// Clears the entire cache. To be used when some event results in unknown
    /// invalidations across this particular `DataLoader`. Returns itself for
    /// method chaining.
    @discardableResult
    public func clearAll() -> DataLoader<Key, Value> {
        cache.removeAll()
        return self
    }

    /// Adds the provied key and value to the cache. If the key already exists, no
    /// change is made. Returns itself for method chaining.
    @discardableResult
    public func prime(key: Key, value: Value) async throws -> DataLoader<Key, Value> {
        let cacheKey = options.cacheKeyFunction?(key) ?? key

        if cache[cacheKey] == nil {
            let channel = Channel<Value, Error>()
            Task.detached {
                await channel.fulfill(with: value)
            }

            cache[cacheKey] = channel
        }

        return self
    }

    public func execute() async throws {
        // Take the current loader queue, replacing it with an empty queue.
        let batch = queue
        queue = []
        if dispatchScheduled {
            dispatchScheduled = false
        }

        guard !batch.isEmpty else {
            return ()
        }

        // If a maxBatchSize was provided and the queue is longer, then segment the
        // queue into multiple batches, otherwise treat the queue as a single batch.
        if let maxBatchSize = options.maxBatchSize, maxBatchSize > 0, maxBatchSize < batch.count {
            try await batch.chunks(ofCount: maxBatchSize).asyncForEach { slicedBatch in
                try await self.executeBatch(batch: Array(slicedBatch))
            }
        } else {
            try await executeBatch(batch: batch)
        }
    }

    private func executeBatch(batch: LoaderQueue<Key, Value>) async throws {
        let keys = batch.map { $0.key }

        if keys.isEmpty {
            return
        }

        // Step through the values, resolving or rejecting each Promise in the
        // loaded queue.
        do {
            let values = try await batchLoadFunction(keys)
            if values.count != keys.count {
                throw DataLoaderError.typeError("The function did not return an array of the same length as the array of keys. \nKeys count: \(keys.count)\nValues count: \(values.count)")
            }

            for entry in batch.enumerated() {
                let result = values[entry.offset]

                switch result {
                case let .failure(error):
                        await entry.element.channel.fail(with: error)
                case let .success(value):
                    await entry.element.channel.fulfill(with: value)
                }
            }
        } catch {
            await failedExecution(batch: batch, error: error)
        }
    }

    private func failedExecution(batch: LoaderQueue<Key, Value>, error: Error) async {
        for (key, channel) in batch {
            _ = clear(key: key)
            await channel.fail(with: error)
        }
    }
}

public actor Channel<Success: Sendable, Failure: Error>: Sendable {
    typealias Waiter = CheckedContinuation<Success, Error>

    private actor State {
        var waiters = [Waiter]()
        var result: Success? = nil
        var failure: Failure? = nil

        func setResult(result: Success) {
            self.result = result
        }

        func setFailure(failure: Failure) {
            self.failure = failure
        }

        func appendWaiters(waiters: Waiter...) {
            self.waiters.append(contentsOf: waiters)
        }

        func removeAllWaiters() {
            self.waiters.removeAll()
        }
    }

    private var state = State()

    public init(_ elementType: Success.Type = Success.self) {}

    @discardableResult
    public func fulfill(with value: Success) async -> Bool {
            if await state.result == nil {
                await state.setResult(result:value)
                for waiters in await state.waiters {
                    waiters.resume(returning: value)
                }
                await state.removeAllWaiters()
                return false
            }
        return true
    }

    @discardableResult
    public func fail(with failure: Failure) async -> Bool {
            if await state.failure == nil {
                await state.setFailure(failure: failure)
                for waiters in await state.waiters {
                    waiters.resume(throwing: failure)
                }
                await state.removeAllWaiters()
                return false
            }
        return true
    }

    public var value: Success {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    if let result = await state.result {
                        continuation.resume(returning: result)
                    } else if let failure = await self.state.failure {
                        continuation.resume(throwing: failure)
                    } else {
                        await state.appendWaiters(waiters: continuation)
                    }
                }
            }
        }
    }
}

extension Channel where Success == Void {
    func fulfill() async -> Bool {
        return await fulfill(with: ())
    }
}
