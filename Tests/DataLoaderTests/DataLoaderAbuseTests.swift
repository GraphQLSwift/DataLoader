import NIOPosix
import Testing

@testable import DataLoader

/// Provides descriptive error messages for API abuse
struct DataLoaderAbuseTests {
    @Test func funtionWithNoValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { _ in
            eventLoopGroup.next().makeSucceededFuture([])
        }

        let value = try identityLoader.load(key: 1, on: eventLoopGroup)

        let error = #expect(throws: DataLoaderError.self) {
            try value.wait()
        }
        #expect(error.testDescription == #".noValueForKey("Did not return value for key: 1")"#)
    }

    @Test func batchFuntionMustPromiseAnArrayOfCorrectLength() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<Int, Int> { _ in
            eventLoopGroup.next().makeSucceededFuture([])
        }

        let value = try identityLoader.load(key: 1, on: eventLoopGroup)

        let error = #expect(throws: Error.self) {
            try value.wait()
        }
        #expect(
            error.testDescription
                == #".typeError("The function did not return an array of the same length as the array of keys. \nKeys count: 1\nValues count: 0")"#
        )
    }

    @Test func batchFuntionWithSomeValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<Int, Int> { keys in
            var results = [DataLoaderFutureValue<Int>]()

            for key in keys {
                if key == 1 {
                    results.append(DataLoaderFutureValue.success(key))
                } else {
                    results.append(
                        DataLoaderFutureValue.failure(DataLoaderError.typeError("Test error"))
                    )
                }
            }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: 1, on: eventLoopGroup)
        let value2 = try identityLoader.load(key: 2, on: eventLoopGroup)

        #expect(throws: Error.self) {
            try value2.wait()
        }

        #expect(try value1.wait() == 1)
    }

    @Test func funtionWithSomeValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { keys in
            var results = [DataLoaderFutureValue<Int>]()

            for key in keys {
                if key == 1 {
                    results.append(DataLoaderFutureValue.success(key))
                } else {
                    results.append(
                        DataLoaderFutureValue.failure(DataLoaderError.typeError("Test error"))
                    )
                }
            }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: 1, on: eventLoopGroup)
        let value2 = try identityLoader.load(key: 2, on: eventLoopGroup)

        #expect(throws: Error.self) {
            try value2.wait()
        }

        #expect(try value1.wait() == 1)
    }
}
