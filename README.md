# SwiftDataLoader
SwiftDataLoader is a generic utility to be used as part of your application's data fetching layer to provide a simplified and consistent API over various remote data sources such as databases or web services via batching and caching.

This is a Swift version of the Facebook [DataLoader](https://github.com/facebook/dataloader).

[![Swift][swift-badge]][swift-url]
[![License][mit-badge]][mit-url]
[![CircleCI][circleci-badge]][circleci-uri]
[![codecov][codecov-badge]][codecov-uri]

## Installation 💻

Update your `Package.swift` file.

```swift
.Package(url: "https://github.com/GraphQLSwift/SwiftDataLoader.git", .upToNextMajor(from: "1.1.0"))
```

## Gettings started 🚀
### Batching
Batching is not an advanced feature, it's DataLoader's primary feature. 

Create a DataLoader by providing a batch loading function
```swift
let userLoader = Dataloader<Int, User>(batchLoadFunction: { keys in
  try User.query(on: req).filter(\User.id ~~ keys).all().map { users in
    return users.map { DataLoaderFutureValue.success($0) }
  }
})
```
#### Load single key
```swift
let future1 = try userLoader.load(key: 1, on: eventLoopGroup)
let future2 = try userLoader.load(key: 2, on: eventLoopGroup)
let future3 = try userLoader.load(key: 1, on: eventLoopGroup)
```

Now there is only one thing left and that is to dispathc it `try userLoader.dispatchQueue(on: req.eventLoop)`

The example above will only fetch two users, because the user with key `1` is present twice in the list. 

#### Load multiple keys
There is also a method to load multiple keys at once
```swift
try userLoader.loadMany(keys: [1, 2, 3], on: eventLoopGroup)
```

#### Disable batching
It is possible to disable batching `DataLoaderOptions(batchingEnabled: false)`
It will invoke `batchLoadFunction` immediately whenever any key is loaded

### Caching

DataLoader provides a memoization cache for all loads which occur in a single
request to your application. After `.load()` is called once with a given key,
the resulting value is cached to eliminate redundant loads.

In addition to relieving pressure on your data storage, caching results per-request
also creates fewer objects which may relieve memory pressure on your application:

```swift
let userLoader = DataLoader<Int, Int>(...)
let future1 = userLoader.load(key: 1, on: eventLoopGroup)
let future2 = userLoader.load(key: 1, on: eventLoopGroup)
assert(future1 === future2)
```

#### Caching per-Request

DataLoader caching *does not* replace Redis, Memcache, or any other shared
application-level cache. DataLoader is first and foremost a data loading mechanism,
and its cache only serves the purpose of not repeatedly loading the same data in
the context of a single request to your Application. To do this, it maintains a
simple in-memory memoization cache (more accurately: `.load()` is a memoized function).

Avoid multiple requests from different users using the DataLoader instance, which
could result in cached data incorrectly appearing in each request. Typically,
DataLoader instances are created when a Request begins, and are not used once the
Request ends.

#### Clearing Cache

In certain uncommon cases, clearing the request cache may be necessary.

The most common example when clearing the loader's cache is necessary is after
a mutation or update within the same request, when a cached value could be out of
date and future loads should not use any possibly cached value.

Here's a simple example using SQL UPDATE to illustrate.

```swift
// Request begins...
let userLoader = DataLoader<Int, Int>(...)

// And a value happens to be loaded (and cached).
userLoader.load(key: 4, on: eventLoopGroup)

// A mutation occurs, invalidating what might be in cache.
sqlRun('UPDATE users WHERE id=4 SET username="zuck"').then { userLoader.clear(4) }

// Later the value load is loaded again so the mutated data appears.
userLoader.load(key: 4, on: eventLoopGroup)

// Request completes.
```

#### Caching Errors

If a batch load fails (that is, a batch function throws or returns a DataLoaderFutureValue.failure(Error)), 
then the requested values will not be cached. However if a batch
function returns an `Error` instance for an individual value, that `Error` will
be cached to avoid frequently loading the same `Error`.

In some circumstances you may wish to clear the cache for these individual Errors:

```swift
userLoader.load(key: 1, on: eventLoopGroup).catch { error in {
    if (/* determine if should clear error */) {
        userLoader.clear(key: 1);
    }
    throw error
}
```

#### Disabling Cache

In certain uncommon cases, a DataLoader which *does not* cache may be desirable.
Calling `DataLoader(options: DataLoaderOptions(cachingEnabled: false), batchLoadFunction: batchLoadFunction)` will ensure that every
call to `.load()` will produce a *new* Future, and previously requested keys will not be
saved in memory.

However, when the memoization cache is disabled, your batch function will
receive an array of keys which may contain duplicates! Each key will be
associated with each call to `.load()`. Your batch loader should provide a value
for each instance of the requested key.

For example:

```swift
let myLoader =  DataLoader<String, String>(
    options: DataLoaderOptions(cachingEnabled: false),
    batchLoadFunction: { keys in 
        self.someBatchLoader(keys: keys).map { DataLoaderFutureValue.success($0) }
    }
)

myLoader.load(key: "A", on: eventLoopGroup)
myLoader.load(key: "B", on: eventLoopGroup)
myLoader.load(key: "A", on: eventLoopGroup)

// > [ "A", "B", "A" ]
```

More complex cache behavior can be achieved by calling `.clear()` or `.clearAll()`
rather than disabling the cache completely. For example, this DataLoader will
provide unique keys to a batch function due to the memoization cache being
enabled, but will immediately clear its cache when the batch function is called
so later requests will load new values.

```swift
let myLoader = DataLoader<String, String>(batchLoadFunction: { keys in
    identityLoader.clearAll()
    return someBatchLoad(keys: keys)
})
```

## Contributing 🤘

All your feedback and help to improve this project is very welcome. Please create issues for your bugs, ideas and enhancement requests, or better yet, contribute directly by creating a PR. 😎

When reporting an issue, please add a detailed instruction, and if possible a code snippet or test that can be used as a reproducer of your problem. 💥

When creating a pull request, please adhere to the current coding style where possible, and create tests with your code so it keeps providing an awesome test coverage level 💪

## Acknowledgements 👏

This library is entirely a Swift version of Facebooks [DataLoader](https://github.com/facebook/dataloader). Developed by  [Lee Byron](https://github.com/leebyron) and
[Nicholas Schrock](https://github.com/schrockn) from [Facebook](https://www.facebook.com/).

[swift-badge]: https://img.shields.io/badge/Swift-5.2-orange.svg?style=flat
[swift-url]: https://swift.org

[mit-badge]: https://img.shields.io/badge/License-MIT-blue.svg?style=flat
[mit-url]: https://tldrlegal.com/license/mit-license

[circleci-badge]: https://circleci.com/gh/kimdv/SwiftDataLoader.svg?style=svg
[circleci-uri]: https://circleci.com/gh/kimdv/SwiftDataLoader

[codecov-badge]: https://codecov.io/gh/kimdv/SwiftDataLoader/branch/master/graph/badge.svg
[codecov-uri]: https://codecov.io/gh/kimdv/SwiftDataLoader
