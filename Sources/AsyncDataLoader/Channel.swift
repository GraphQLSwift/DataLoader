actor Channel<Success: Sendable, Failure: Error>: Sendable {
    private var waiters = [Waiter<Success, Failure>]()
    private var result: Result<Success, Failure>?
}

typealias Waiter<Success, Failure> = CheckedContinuation<Success, Error>

extension Channel {
    @discardableResult
    func fulfill(_ success: Success) -> Bool {
        if result == nil {
            result = .success(success)

            while let waiter = waiters.popLast() {
                waiter.resume(returning: success)
            }

            return false
        }

        return true
    }

    @discardableResult
    func fail(_ failure: Failure) -> Bool {
        if result == nil {
            result = .failure(failure)

            while let waiter = waiters.popLast() {
                waiter.resume(throwing: failure)
            }

            return false
        }

        return true
    }

    var value: Success {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    switch result {
                    case let .success(success):
                        continuation.resume(returning: success)
                    case let .failure(failure):
                        continuation.resume(throwing: failure)
                    case nil:
                        waiters.append(continuation)
                    }
                }
            }
        }
    }
}
