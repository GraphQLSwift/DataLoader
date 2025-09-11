# DataLoader

[![](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](https://tldrlegal.com/license/mit-license)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FGraphQLSwift%2FDataLoader%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/GraphQLSwift/DataLoader)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FGraphQLSwift%2FDataLoader%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/GraphQLSwift/DataLoader)
[![WASI 0.1](https://github.com/GraphQLSwift/DataLoader/actions/workflows/wasm.yml/badge.svg?branch=main)](https://github.com/GraphQLSwift/DataLoader/actions/workflows/wasm.yml)

DataLoader is a generic utility to be used as part of your application's data fetching layer to provide a simplified and consistent API over various remote data sources such as databases or web services via batching and caching.

This is a Swift version of the Facebook [DataLoader](https://github.com/facebook/dataloader).

## Gettings started 🚀

Include this repo in your `Package.swift` file.

```swift
.Package(url: "https://github.com/GraphQLSwift/DataLoader.git", .upToNextMajor(from: "1.1.0"))
```

To get started, create a DataLoader. Each DataLoader instance represents a unique cache. Typically instances are created per request when used
within a web-server if different users can see different things.

## Batching 🍪
Batching is not an advanced feature, it's DataLoader's primary feature.

Create a DataLoader by providing a batch loading function:
```swift
let userLoader = Dataloader<Int, User>(batchLoadFunction: { keys in
  try User.query(on: req).filter(\User.id ~~ keys).all().map { users in
    keys.map { key in
      DataLoaderFutureValue.success(users.filter{ $0.id == key })
    }
  }
})
```

The order of the returned DataLoaderFutureValues must match the order of the keys.

### Load individual keys
```swift
let future1 = try userLoader.load(key: 1, on: eventLoopGroup)
let future2 = try userLoader.load(key: 2, on: eventLoopGroup)
let future3 = try userLoader.load(key: 1, on: eventLoopGroup)
```

The example above will only fetch two users, because the user with key `1` is present twice in the list.

### Load multiple keys
There is also a method to load multiple keys at once
```swift
try userLoader.loadMany(keys: [1, 2, 3], on: eventLoopGroup)
```

### Execution
By default, a DataLoader will wait for a short time from the moment `load` is called to collect keys prior
to running the `batchLoadFunction` and completing the `load` futures. This is to let keys accumulate and
batch into a smaller number of total requests. This amount of time is configurable using the `executionPeriod`
option:

```swift
let myLoader =  DataLoader<String, String>(
    options: DataLoaderOptions(executionPeriod: .milliseconds(50)),
    batchLoadFunction: { keys in
        self.someBatchLoader(keys: keys).map { DataLoaderFutureValue.success($0) }
    }
)
```

Longer execution periods reduce the number of total data requests, but also reduce the responsiveness of the
`load` futures.

If desired, you can manually execute the `batchLoadFunction` and complete the futures at any time, using the
`.execute()` method.

Scheduled execution can be disabled by setting `executionPeriod` to `nil`, but be careful - you *must* call `.execute()`
manually in this case. Otherwise, the futures will never complete!

### Disable batching
It is possible to disable batching by setting the   `batchingEnabled` option to `false`.
In this case, the `batchLoadFunction` will be invoked immediately when a key is loaded.


## Caching 💰
DataLoader provides a memoization cache. After `.load()` is called with a key, the resulting value is cached
for the lifetime of the DataLoader object. This eliminates redundant loads.

In addition to relieving pressure on your data storage, caching results also creates fewer objects which may
relieve memory pressure on your application:

```swift
let userLoader = DataLoader<Int, Int>(...)
let future1 = userLoader.load(key: 1, on: eventLoopGroup)
let future2 = userLoader.load(key: 1, on: eventLoopGroup)
print(future1 == future2) // true
```

### Caching per-Request

DataLoader caching *does not* replace Redis, Memcache, or any other shared
application-level cache. DataLoader is first and foremost a data loading mechanism,
and its cache only serves the purpose of not repeatedly loading the same data in
the context of a single request to your Application. To do this, it maintains a
simple in-memory memoization cache (more accurately: `.load()` is a memoized function).

Avoid multiple requests from different users using the DataLoader instance, which
could result in cached data incorrectly appearing in each request. Typically,
DataLoader instances are created when a Request begins, and are not used once the
Request ends.

### Clearing Cache

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
sqlRun('UPDATE users WHERE id=4 SET username="zuck"').whenComplete { userLoader.clear(key: 4) }

// Later the value load is loaded again so the mutated data appears.
userLoader.load(key: 4, on: eventLoopGroup)

// Request completes.
```

### Caching Errors

If a batch load fails (that is, a batch function throws or returns a DataLoaderFutureValue.failure(Error)),
then the requested values will not be cached. However if a batch
function returns an `Error` instance for an individual value, that `Error` will
be cached to avoid frequently loading the same `Error`.

In some circumstances you may wish to clear the cache for these individual Errors:

```swift
userLoader.load(key: 1, on: eventLoopGroup).whenFailure { error in
    if (/* determine if should clear error */) {
        userLoader.clear(key: 1);
    }
    throw error
}
```

### Disabling Cache

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

## Using with GraphQL 🎀

DataLoader pairs nicely well with [GraphQL](https://github.com/GraphQLSwift/GraphQL) and
[Graphiti](https://github.com/GraphQLSwift/Graphiti). GraphQL fields are designed to be
stand-alone functions. Without a caching or batching mechanism,
it's easy for a naive GraphQL server to issue new database requests each time a
field is resolved.

Consider the following GraphQL request:

```
{
  me {
    name
    bestFriend {
      name
    }
    friends(first: 5) {
      name
      bestFriend {
        name
      }
    }
  }
}
```

Naively, if `me`, `bestFriend` and `friends` each need to request the backend,
there could be at most 12 database requests!

By using DataLoader, we could batch our requests to a `User` type, and
only require at most 4 database requests, and possibly fewer if there are cache hits.
Here's a full example using Graphiti:

```swift
struct User : Codable {
    let id: Int
    let name: String
    let bestFriendID: Int
    let friendIDs: [Int]

    func getBestFriend(context: UserContext, arguments: NoArguments, group: EventLoopGroup) throws -> EventLoopFuture<User> {
        return try context.userLoader.load(key: user.bestFriendID, on: group)
    }

    struct FriendArguments {
        first: Int
    }
    func getFriends(context: UserContext, arguments: FriendArguments, group: EventLoopGroup) throws -> EventLoopFuture<[User]> {
        return try context.userLoader.loadMany(keys: user.friendIDs[0..<arguments.first], on: group)
    }
}

struct UserResolver {
    public func me(context: UserContext, arguments: NoArguments) -> User {
        ...
    }
}

class UserContext {
    let database = ...
    let userLoader = DataLoader<Int, User>() { [weak self] keys in
        guard let self = self else { throw ContextError }
        return User.query(on: self.database).filter(\.$id ~~ keys).all().map { users in
            keys.map { key in
                users.first { $0.id == key }!
            }
        }
    }
}

struct UserAPI : API {
    let resolver = UserResolver()
    let schema = Schema<UserResolver, UserContext> {
        Type(User.self) {
            Field("name", at: \.content)
            Field("bestFriend", at: \.getBestFriend, as: TypeReference<User>.self)
            Field("friends", at: \.getFriends, as: [TypeReference<User>]?.self) {
                Argument("first", at: .\first)
            }
        }

        Query {
            Field("me", at: UserResolver.hero, as: User.self)
        }
    }
}
```

## Contributing 🤘

All your feedback and help to improve this project is very welcome. Please create issues for your bugs, ideas and
enhancement requests, or better yet, contribute directly by creating a PR. 😎

When reporting an issue, please add a detailed example, and if possible a code snippet or test
to reproduce your problem. 💥

When creating a pull request, please adhere to the current coding style where possible, and create tests with your
code so it keeps providing an awesome test coverage level 💪

This repo uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), and includes lint checks to enforce these formatting standards.
To format your code, install `swiftformat` and run:

```bash
swiftformat .
```

## Acknowledgements 👏

This library is entirely a Swift version of Facebooks [DataLoader](https://github.com/facebook/dataloader).
Developed by  [Lee Byron](https://github.com/leebyron) and [Nicholas Schrock](https://github.com/schrockn)
from [Facebook](https://www.facebook.com/).
