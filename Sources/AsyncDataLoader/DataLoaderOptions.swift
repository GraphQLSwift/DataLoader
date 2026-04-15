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

    /// Default `parallel`. Defines the strategy for execution when
    /// the execution queue exceeds `maxBatchSize`.
    /// This is irrelevant if batching is disabled.
    public let executionStrategy: ExecutionStrategy

    /// Default `nil`. Produces cache key for a given load key. Useful
    /// when objects are keys and two objects should be considered equivalent.
    public let cacheKeyFunction: (@Sendable (Key) -> Key)?

    public init(
        batchingEnabled: Bool = true,
        cachingEnabled: Bool = true,
        maxBatchSize: Int? = nil,
        executionPeriod: UInt64? = 2_000_000,
        executionStrategy: ExecutionStrategy = .parallel,
        cacheKeyFunction: (@Sendable (Key) -> Key)? = nil
    ) {
        self.batchingEnabled = batchingEnabled
        self.cachingEnabled = cachingEnabled
        self.executionPeriod = executionPeriod
        self.executionStrategy = executionStrategy
        self.maxBatchSize = maxBatchSize
        self.cacheKeyFunction = cacheKeyFunction
    }

    /// The strategy for execution when the execution queue exceeds `maxBatchSize`.
    public struct ExecutionStrategy: Sendable {
        let option: Option

        private init(option: Option) {
            self.option = option
        }

        /// Batches within a single execution will be executed simultaneously
        public static var parallel: Self {
            .init(option: .parallel)
        }

        /// Batches within a single execution will be executed one-at-a-time
        public static var serial: Self {
            .init(option: .serial)
        }

        enum Option {
            case parallel
            case serial
        }
    }
}
