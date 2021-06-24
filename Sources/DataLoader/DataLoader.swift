import NIO

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

    private var futureCache = [Key: EventLoopFuture<Value>]()
    private var queue = LoaderQueue<Key, Value>()

    public init(options: DataLoaderOptions<Key, Value> = DataLoaderOptions(), batchLoadFunction: @escaping BatchLoadFunction<Key, Value>) {
        self.options = options
        self.batchLoadFunction = batchLoadFunction
    }

    /// Loads a key, returning an `EventLoopFuture` for the value represented by that key.
    public func load(key: Key, on eventLoop: EventLoopGroup) throws -> EventLoopFuture<Value> {
        let cacheKey = options.cacheKeyFunction?(key) ?? key

        if options.cachingEnabled, let cachedFuture = futureCache[cacheKey] {
            return cachedFuture
        }

        let promise: EventLoopPromise<Value> = eventLoop.next().makePromise()

        if options.batchingEnabled {
            queue.append((key: key, promise: promise))
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
            futureCache[cacheKey] = future
        }

        return future
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
    public func loadMany(keys: [Key], on eventLoop: EventLoopGroup) throws -> EventLoopFuture<[Value]> {
        guard !keys.isEmpty else { return eventLoop.next().makeSucceededFuture([]) }

        let promise: EventLoopPromise<[Value]> = eventLoop.next().makePromise()

        var result = [Value]()

        let futures = try keys.map { try load(key: $0, on: eventLoop) }

        for future in futures {
            _ = future.map { value in
                result.append(value)

                if result.count == keys.count {
                    promise.succeed(result)
                }
            }
        }

        return promise.futureResult
    }
    
    /// Clears the value at `key` from the cache, if it exists. Returns itself for
    /// method chaining.
    @discardableResult
    func clear(key: Key) -> DataLoader<Key, Value> {
        let cacheKey = options.cacheKeyFunction?(key) ?? key
        futureCache.removeValue(forKey: cacheKey)
        return self
    }
    
    /// Clears the entire cache. To be used when some event results in unknown
    /// invalidations across this particular `DataLoader`. Returns itself for
    /// method chaining.
    @discardableResult
    func clearAll() -> DataLoader<Key, Value> {
        futureCache.removeAll()
        return self
    }

    /// Adds the provied key and value to the cache. If the key already exists, no
    /// change is made. Returns itself for method chaining.
    @discardableResult
    func prime(key: Key, value: Value, on eventLoop: EventLoopGroup) -> DataLoader<Key, Value> {
        let cacheKey = options.cacheKeyFunction?(key) ?? key

        if futureCache[cacheKey] == nil {
            let promise: EventLoopPromise<Value> = eventLoop.next().makePromise()
            promise.succeed(value)

            futureCache[cacheKey] = promise.futureResult
        }

        return self
    }

    public func dispatchQueue(on eventLoop: EventLoopGroup) throws {
        // Take the current loader queue, replacing it with an empty queue.
        let queue = self.queue
        self.queue = []

        // If a maxBatchSize was provided and the queue is longer, then segment the
        // queue into multiple batches, otherwise treat the queue as a single batch.
        if let maxBatchSize = options.maxBatchSize, maxBatchSize > 0 && maxBatchSize < queue.count {
            for i in 0...(queue.count / maxBatchSize) {
                let startIndex = i * maxBatchSize
                let endIndex = (i + 1) * maxBatchSize
                let slicedQueue = queue[startIndex..<min(endIndex, queue.count)]
                try dispatchQueueBatch(queue: Array(slicedQueue), on: eventLoop)
            }
        } else {
                try dispatchQueueBatch(queue: queue, on: eventLoop)
        }
    }
    
    private func dispatchQueueBatch(queue: LoaderQueue<Key, Value>, on eventLoop: EventLoopGroup) throws {
        let keys = queue.map { $0.key }

        if keys.isEmpty {
            return
        }

        // Step through the values, resolving or rejecting each Promise in the
        // loaded queue.
            _ = try batchLoadFunction(keys)
                .flatMapThrowing { values in
                    if values.count != keys.count {
                        throw DataLoaderError.typeError("The function did not return an array of the same length as the array of keys. \nKeys count: \(keys.count)\nValues count: \(values.count)")
                    }

                    for entry in queue.enumerated() {
                        let result = values[entry.offset]

                        switch result {
                        case .failure(let error): entry.element.promise.fail(error)
                        case .success(let value): entry.element.promise.succeed(value)
                        }
                    }
                }
                .recover { error in
                    self.failedDispatch(queue: queue, error: error)
        }
    }

    private func failedDispatch(queue: LoaderQueue<Key, Value>, error: Error) {
        queue.forEach { (key, promise) in
            _ = clear(key: key)
            promise.fail(error)
        }
    }
}