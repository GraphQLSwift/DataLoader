@testable import class AsyncDataLoader.Channel
@testable import protocol AsyncDataLoader.Stateful
@testable import typealias AsyncDataLoader.Waiter
import Testing

/// When Channel.fulfill or .fail is called, an arbitrarily long suspension of
///     await state.removeAllWaiters()
/// would allow actor reentrancy, where another continuation could be added, removed, but not resumed.
/// This reproducer injects a mock state object that artificially pauses the removal of all waiters until a new one is added.
/// At that point, Channel will no longer resume the water and just remove it.
/// This test passes, but with a logged message
///     SWIFT TASK CONTINUATION MISUSE: reproduceLeakingCheckedContinuation() leaked its continuation without resuming it. This may cause tasks waiting on it to remain suspended forever.
///
/// Note that it is not leaked in the computed property `value`. This reproducer only shows that a continuation could be leaked through the state and actor reentrancy.
/// Calling Channel.value instead causes this test to hang indefinitely because it is waiting for an unresumed continuation.
@Test func reproduceLeakedCheckedContinuation() async throws {
    // setup global variables
    //
    // fulfill task
    // - create state and channel
    // - pass out to main thread
    // - call fulfill so that removeAllWaiters is called
    // - signal removeAllWaiters was called
    // - suspend Task until append is called
    //
    // wait for removeAllWaiters signal
    //
    // leak continuation task
    // - call append
    //   - appends the waiter
    //   - resumes the continuation created in removeAllWaiters, allowing the fulfill task to resume
    //
    // wait for fulfill task to complete, which removesAllWaiters
    // test ends with SWIFT TASK CONTINUATION MISUSE

    var state: MockState<Int, Never>?
    var channel: Channel<Int, Never, MockState<Int, Never>>?

    var fulfillTask: Task<Void, Error>? = nil

    // continuation gets resumed when state.removeAllWaiters is called
    await withCheckedContinuation { continuation in
        let localState = MockState<Int, Never>(continuation)
        state = localState
        channel = Channel(localState)
        fulfillTask = Task {
            _ = try await #require(channel).fulfill(42)
        }
    }

    // leaking continuation task
    Task {
        // calling channel.value here would be ideal, to make that append a continuation to the state
        // but this causes the process to hand forever
        //
        // try await #require(channel).value

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) -> Void in
            Task { // wrap in task to allow throwing
                try await #require(state).appendWaiters(waiters: continuation)
            }
        }
    }

    try await #require(fulfillTask).value
}

actor MockState<Success, Failure>: Stateful {
    var waiters = [Waiter<Success, Failure>]()
    var result: Success?
    var failure: Failure?

    /// suspend until
    let removeAllCalledContinuation: CheckedContinuation<Void, Never>
    var appendCalledContinuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        removeAllCalledContinuation = continuation
    }
}

extension MockState {
    func setResult(result: Success) {
        self.result = result
    }

    func setFailure(failure: Failure) {
        self.failure = failure
    }

    func appendWaiters(waiters: Waiter<Success, Failure>...) {
        self.waiters.append(contentsOf: waiters)
        guard let continuation = appendCalledContinuation else {
            Issue.record("removeAllWaiters was not called before appendWaiters")
            return
        }
        continuation.resume()
    }

    func removeAllWaiters() async {
        removeAllCalledContinuation.resume()
        await withCheckedContinuation { continuation in
            appendCalledContinuation = continuation
        }
        waiters.removeAll()
    }
}
