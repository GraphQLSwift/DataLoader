actor Channel<Success: Sendable, Failure: Error>: Sendable {
    private var waiters = [Waiter<Success, Failure>]()
    private var result: Success?
    private var failure: Failure?
}

typealias Waiter<Success, Failure> = CheckedContinuation<Success, Error>

extension Channel {
    @discardableResult
    func fulfill(_ value: Success) -> Bool {
        if result == nil {
            result = value

            for waiter in waiters {
                waiter.resume(returning: value)
            }

            waiters.removeAll()

            return false
        }

        return true
    }

    @discardableResult
    func fail(_ failure: Failure) -> Bool {
        if self.failure == nil {
            self.failure = failure

            for waiter in waiters {
                waiter.resume(throwing: failure)
            }

            waiters.removeAll()

            return false
        }

        return true
    }

    var value: Success {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    if let result = self.result {
                        continuation.resume(returning: result)
                    } else if let failure = self.failure {
                        continuation.resume(throwing: failure)
                    } else {
                        waiters.append(continuation)
                    }
                }
            }
        }
    }
}
