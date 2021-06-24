import XCTest
import NIO

@testable import SwiftDataLoader

/// Provides descriptive error messages for API abuse
class DataLoaderAbuseTests: XCTestCase {

    func testFuntionWithNoValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>(options: DataLoaderOptions(batchingEnabled: false)) { keys in
            eventLoopGroup.next().makeSucceededFuture([])
        }

        let value = try identityLoader.load(key: 1, on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.dispatchQueue(on: eventLoopGroup))

        XCTAssertThrowsError(try value.wait(), "Did not return value for key: 1")
    }

    func testBatchFuntionMustPromiseAnArrayOfCorrectLength() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>(options: DataLoaderOptions()) { keys in
            eventLoopGroup.next().makeSucceededFuture([])
        }

        let value = try identityLoader.load(key: 1, on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.dispatchQueue(on: eventLoopGroup))

        XCTAssertThrowsError(try value.wait(), "The function did not return an array of the same length as the array of keys. \nKeys count: 1\nValues count: 0")
    }

    func testBatchFuntionWithSomeValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>(options: DataLoaderOptions()) { keys in
            var results = [DataLoaderFutureValue<Int>]()

            for key in keys {
                if key == 1 {
                    results.append(DataLoaderFutureValue.success(key))
                } else {
                    results.append(DataLoaderFutureValue.failure("Test error"))
                }
            }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: 1, on: eventLoopGroup)
        let value2 = try identityLoader.load(key: 2, on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.dispatchQueue(on: eventLoopGroup))

        XCTAssertThrowsError(try value2.wait())

        XCTAssertTrue(try value1.wait() == 1)
    }

    func testFuntionWithSomeValues() throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let identityLoader = DataLoader<Int, Int>(options: DataLoaderOptions(batchingEnabled: false)) { keys in
            var results = [DataLoaderFutureValue<Int>]()

            for key in keys {
                if key == 1 {
                    results.append(DataLoaderFutureValue.success(key))
                } else {
                    results.append(DataLoaderFutureValue.failure("Test error"))
                }
            }

            return eventLoopGroup.next().makeSucceededFuture(results)
        }

        let value1 = try identityLoader.load(key: 1, on: eventLoopGroup)
        let value2 = try identityLoader.load(key: 2, on: eventLoopGroup)

        XCTAssertNoThrow(try identityLoader.dispatchQueue(on: eventLoopGroup))

        XCTAssertThrowsError(try value2.wait())

        XCTAssertTrue(try value1.wait() == 1)
    }

    static var allTests: [(String, (DataLoaderAbuseTests) -> () throws -> Void)] = [
        ("testFuntionWithNoValues", testFuntionWithNoValues),
        ("testBatchFuntionMustPromiseAnArrayOfCorrectLength", testBatchFuntionMustPromiseAnArrayOfCorrectLength),
        ("testBatchFuntionWithSomeValues", testBatchFuntionWithSomeValues),
        ("testFuntionWithSomeValues", testFuntionWithSomeValues)
    ]
    
}

extension String: Error { }
