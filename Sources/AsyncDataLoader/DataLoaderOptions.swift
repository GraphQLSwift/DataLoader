public struct DataLoaderOptions<Key: Hashable, Value>: Sendable {
    /// Default `true`. Set to `false` to disable batching, invoking
    /// `batchLoadFunction` with a single load key. This is
    /// equivalent to setting `maxBatchSize` to `1`.
    public let batchingEnabled: Bool

    /// Default `nil`. Limits the number of items that get passed in to the
    /// `batchLoadFn`. May be set to `1` to disable batching.
    public let maxBatchSize: Int?

    /// Default `true`. Set to `false` to disable memoization caching, creating a
    /// new `EventLoopFuture` and new key in the `batchLoadFunction`
    /// for every load of the same key.
    public let cachingEnabled: Bool

    /// Default `2ms`. Defines the period of time that the DataLoader should
    /// wait and collect its queue before executing. Faster times result
    /// in smaller batches quicker resolution, slower times result in larger
    /// batches but slower resolution.
    /// This is irrelevant if batching is disabled.
    public let executionPeriod: UInt64?

    /// Default `nil`. Produces cache key for a given load key. Useful
    /// when objects are keys and two objects should be considered equivalent.
    public let cacheKeyFunction: (@Sendable (Key) -> Key)?

    public init(
        batchingEnabled: Bool = true,
        cachingEnabled: Bool = true,
        maxBatchSize: Int? = nil,
        executionPeriod: UInt64? = 2_000_000,
        cacheKeyFunction: (@Sendable (Key) -> Key)? = nil
    ) {
        self.batchingEnabled = batchingEnabled
        self.cachingEnabled = cachingEnabled
        self.executionPeriod = executionPeriod
        self.maxBatchSize = maxBatchSize
        self.cacheKeyFunction = cacheKeyFunction
    }
}
