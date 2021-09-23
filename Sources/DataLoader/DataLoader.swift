import NIO
import NIOConcurrencyHelpers

public enum DataLoaderFutureValue<T> {
    case success(T)
    case failure(Error)
}

public typealias BatchLoadFunction<Key, Value> = (_ keys: [Key]) throws -> EventLoopFuture<[DataLoaderFutureValue<Value>]>
private typealias LoaderQueue<Key, Value> = Array<(key: Key, promise: EventLoopPromise<Value>)>

/// DataLoader creates a public API for loading data from a particular
/// data back-end with unique keys such as the id column of a SQL table
/// or document name in a MongoDB database, given a batch loading function.
///
/// Each DataLoader instance contains a unique memoized cache. Use caution
/// when used in long-lived applications or those which serve many users
/// with different access permissions and consider creating a new instance
/// per data request.
final public class DataLoader<Key: Hashable, Value> {

    private let batchLoadFunction: BatchLoadFunction<Key, Value>
    private let options: DataLoaderOptions<Key, Value>

    private var cache = [Key: EventLoopFuture<Value>]()
    private var queue = LoaderQueue<Key, Value>()
    
    private var dispatchScheduled = false
    private let lock = Lock()

    public init(options: DataLoaderOptions<Key, Value> = DataLoaderOptions(), batchLoadFunction: @escaping BatchLoadFunction<Key, Value>) {
        self.options = options
        self.batchLoadFunction = batchLoadFunction
    }

    /// Loads a key, returning an `EventLoopFuture` for the value represented by that key.
    public func load(key: Key, on eventLoopGroup: EventLoopGroup) throws -> EventLoopFuture<Value> {
        let cacheKey = options.cacheKeyFunction?(key) ?? key
        
        return try lock.withLock {
            if options.cachingEnabled, let cachedFuture = cache[cacheKey] {
                return cachedFuture
            }

            let promise: EventLoopPromise<Value> = eventLoopGroup.next().makePromise()

            if options.batchingEnabled {
                queue.append((key: key, promise: promise))
                if let executionPeriod = options.executionPeriod, !dispatchScheduled {
                    eventLoopGroup.next().scheduleTask(in: executionPeriod) {
                        try self.execute()
                    }
                    dispatchScheduled = true
                }
            } else {
                _ = try batchLoadFunction([key]).map { results  in
                    if results.isEmpty {
                        promise.fail(DataLoaderError.noValueForKey("Did not return value for key: \(key)"))
                    } else {
                        let result = results[0]
                        switch result {
                        case .success(let value): promise.succeed(value)
                        case .failure(let error): promise.fail(error)
                        }
                    }
                }
            }

            let future = promise.futureResult

            if options.cachingEnabled {
                cache[cacheKey] = future
            }

            return future
        }
    }
    
    /// Loads multiple keys, promising an array of values:
    ///
    /// ```
    /// let aAndB = myLoader.loadMany(keys: [ "a", "b" ], on: eventLoopGroup).wait()
    /// ```
    ///
    /// This is equivalent to the more verbose:
    ///
    /// ```
    /// let aAndB = [
    ///   myLoader.load(key: "a", on: eventLoopGroup),
    ///   myLoader.load(key: "b", on: eventLoopGroup)
    /// ].flatten(on: eventLoopGroup).wait()
    /// ```
    public func loadMany(keys: [Key], on eventLoopGroup: EventLoopGroup) throws -> EventLoopFuture<[Value]> {
        guard !keys.isEmpty else {
            return eventLoopGroup.next().makeSucceededFuture([])
        }
        let futures = try keys.map { try load(key: $0, on: eventLoopGroup) }
        return EventLoopFuture.whenAllSucceed(futures, on: eventLoopGroup.next())
    }
    
    /// Clears the value at `key` from the cache, if it exists. Returns itself for
    /// method chaining.
    @discardableResult
    func clear(key: Key) -> DataLoader<Key, Value> {
        let cacheKey = options.cacheKeyFunction?(key) ?? key
        lock.withLockVoid {
            cache.removeValue(forKey: cacheKey)
        }
        return self
    }
    
    /// Clears the entire cache. To be used when some event results in unknown
    /// invalidations across this particular `DataLoader`. Returns itself for
    /// method chaining.
    @discardableResult
    func clearAll() -> DataLoader<Key, Value> {
        lock.withLockVoid {
            cache.removeAll()
        }
        return self
    }

    /// Adds the provied key and value to the cache. If the key already exists, no
    /// change is made. Returns itself for method chaining.
    @discardableResult
    func prime(key: Key, value: Value, on eventLoop: EventLoopGroup) -> DataLoader<Key, Value> {
        let cacheKey = options.cacheKeyFunction?(key) ?? key
        
        lock.withLockVoid {
            if cache[cacheKey] == nil {
                let promise: EventLoopPromise<Value> = eventLoop.next().makePromise()
                promise.succeed(value)

                cache[cacheKey] = promise.futureResult
            }
        }

        return self
    }

    /// Executes the queue of keys, completing the `EventLoopFutures`.
    ///
    /// If `executionPeriod` was provided in the options, this method is run automatically
    /// after the specified time period. If `executionPeriod` was nil, the client must
    /// run this manually to compete the `EventLoopFutures` of the keys.
    public func execute() throws {
        // Take the current loader queue, replacing it with an empty queue.
        var batch = LoaderQueue<Key, Value>()
        lock.withLockVoid {
            batch = self.queue
            self.queue = []
            if dispatchScheduled {
                dispatchScheduled = false
            }
        }
        
        guard batch.count > 0 else {
            return ()
        }

        // If a maxBatchSize was provided and the queue is longer, then segment the
        // queue into multiple batches, otherwise treat the queue as a single batch.
        if let maxBatchSize = options.maxBatchSize, maxBatchSize > 0 && maxBatchSize < batch.count {
            for i in 0...(batch.count / maxBatchSize) {
                let startIndex = i * maxBatchSize
                let endIndex = (i + 1) * maxBatchSize
                let slicedBatch = batch[startIndex..<min(endIndex, batch.count)]
                try executeBatch(batch: Array(slicedBatch))
            }
        } else {
                try executeBatch(batch: batch)
        }
    }
    
    private func executeBatch(batch: LoaderQueue<Key, Value>) throws {
        let keys = batch.map { $0.key }

        if keys.isEmpty {
            return
        }

        // Step through the values, resolving or rejecting each Promise in the
        // loaded queue.
        _ = try batchLoadFunction(keys).flatMapThrowing { values in
            if values.count != keys.count {
                throw DataLoaderError.typeError("The function did not return an array of the same length as the array of keys. \nKeys count: \(keys.count)\nValues count: \(values.count)")
            }

            for entry in batch.enumerated() {
                let result = values[entry.offset]

                switch result {
                case .failure(let error): entry.element.promise.fail(error)
                case .success(let value): entry.element.promise.succeed(value)
                }
            }
        }.recover { error in
            self.failedExecution(batch: batch, error: error)
        }
    }

    private func failedExecution(batch: LoaderQueue<Key, Value>, error: Error) {
        for (key, promise) in batch {
            _ = clear(key: key)
            promise.fail(error)
        }
    }
}
