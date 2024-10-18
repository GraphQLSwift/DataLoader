import XCTest

@testable import AsyncDataLoader

/// Provides descriptive error messages for API abuse
class DataLoaderAbuseTests: XCTestCase {
    func testFuntionWithNoValues() async throws {
        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { _ in
            []
        }

        async let value = identityLoader.load(key: 1)

        var didFailWithError: Error?

        do {
            _ = try await value
        } catch {
            didFailWithError = error
        }

        XCTAssertNotNil(didFailWithError)
    }

    func testBatchFuntionMustPromiseAnArrayOfCorrectLength() async {
        let identityLoader = DataLoader<Int, Int>() { _ in
            []
        }

        async let value = identityLoader.load(key: 1)

        var didFailWithError: Error?

        do {
            _ = try await value
        } catch {
            didFailWithError = error
        }

        XCTAssertNotNil(didFailWithError)
    }

    func testBatchFuntionWithSomeValues() async throws {
        let identityLoader = DataLoader<Int, Int>() { keys in
            var results = [DataLoaderValue<Int>]()

            for key in keys {
                if key == 1 {
                    results.append(.success(key))
                } else {
                    results.append(.failure("Test error"))
                }
            }

            return results
        }

        async let value1 = identityLoader.load(key: 1)
        async let value2 = identityLoader.load(key: 2)

        var didFailWithError: Error?

        do {
            _ = try await value2
        } catch {
            didFailWithError = error
        }

        XCTAssertNotNil(didFailWithError)

        let value = try await value1

        XCTAssertTrue(value == 1)
    }

    func testFuntionWithSomeValues() async throws {
        let identityLoader = DataLoader<Int, Int>(
            options: DataLoaderOptions(batchingEnabled: false)
        ) { keys in
            var results = [DataLoaderValue<Int>]()

            for key in keys {
                if key == 1 {
                    results.append(.success(key))
                } else {
                    results.append(.failure("Test error"))
                }
            }

            return results
        }

        async let value1 = identityLoader.load(key: 1)
        async let value2 = identityLoader.load(key: 2)

        var didFailWithError: Error?

        do {
            _ = try await value2
        } catch {
            didFailWithError = error
        }

        XCTAssertNotNil(didFailWithError)

        let value = try await value1

        XCTAssertTrue(value == 1)
    }
}

extension String: Swift.Error {}
