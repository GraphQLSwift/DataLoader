typealias Waiter<Success, Failure> = CheckedContinuation<Success, Error>

actor State<Success, Failure> {
    var waiters = [Waiter<Success, Failure>]()
    var result: Success?
    var failure: Failure?
}

extension State {
    func setResult(result: Success) {
        self.result = result
    }

    func setFailure(failure: Failure) {
        self.failure = failure
    }

    func appendWaiters(waiters: Waiter<Success, Failure>...) {
        self.waiters.append(contentsOf: waiters)
    }

    func removeAllWaiters() {
        waiters.removeAll()
    }
}
