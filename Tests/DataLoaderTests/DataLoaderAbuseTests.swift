import NIOPosix
import XCTest

@testable import DataLoader

/// Provides descriptive error messages for API abuse
class DataLoaderAbuseTests: XCTestCase {
    func testFuntionWithNoValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { _ in
            eventLoopGroup.next().makeSucceededFuture([])
        }

        let value = try identityLoader.load(key: 1, on: eventLoopGroup)

        XCTAssertThrowsError(
            try value.wait(),
            "Did not return value for key: 1"
        )
    }

    func testBatchFuntionMustPromiseAnArrayOfCorrectLength() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>() { _ in
            eventLoopGroup.next().makeSucceededFuture([])
        }

        let value = try identityLoader.load(key: 1, on: eventLoopGroup)

        XCTAssertThrowsError(
            try value.wait(),
            "The function did not return an array of the same length as the array of keys. \nKeys count: 1\nValues count: 0"
        )
    }

    func testBatchFuntionWithSomeValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>() { keys in
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

        XCTAssertThrowsError(try value2.wait())

        XCTAssertTrue(try value1.wait() == 1)
    }

    func testFuntionWithSomeValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

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

        XCTAssertThrowsError(try value2.wait())

        XCTAssertTrue(try value1.wait() == 1)
    }
}
