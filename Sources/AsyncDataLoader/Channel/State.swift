typealias Waiter<Success, Failure> = CheckedContinuation<Success, Error>

protocol Stateful: Actor {
    associatedtype Success: Sendable
    associatedtype Failure: Sendable

    var waiters: [Waiter<Success, Failure>] { get set }
    var result: Success? { get set }
    var failure: Failure? { get set }

    func setResult(result: Success) async
    func setFailure(failure: Failure) async
    func appendWaiters(waiters: Waiter<Success, Failure>...) async
    func removeAllWaiters() async
}

actor State<Success, Failure>: Stateful {
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
