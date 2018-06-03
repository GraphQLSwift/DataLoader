//
//  DataLoaderOptions.swift
//  CNIOAtomics
//
//  Created by Kim de Vos on 02/06/2018.
//

public struct DataLoaderOptions<Key: Hashable, Value> {
    public let batchingEnabled: Bool
    public let cachingEnabled: Bool
    public let cacheMap: [Key: Value]
    public let maxBatchSize: Int?
    public let cacheKeyFunction: ((Key) -> Key)?

    public init(batchingEnabled: Bool = true,
                cachingEnabled: Bool = true,
                maxBatchSize: Int? = nil,
                cacheMap: [Key: Value] = [:],
                cacheKeyFunction: ((Key) -> Key)? = nil) {
        self.batchingEnabled = batchingEnabled
        self.cachingEnabled = cachingEnabled
        self.maxBatchSize = maxBatchSize
        self.cacheMap = cacheMap
        self.cacheKeyFunction = cacheKeyFunction
    }
}
