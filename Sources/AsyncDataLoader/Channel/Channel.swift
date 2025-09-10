actor Channel<
    Success: Sendable,
    Failure: Error,
    ChannelState: Stateful
>: Sendable where ChannelState.Success == Success, ChannelState.Failure == Failure {
    private var state: ChannelState

    init(_ state: ChannelState) {
        self.state = state
    }
}

extension Channel where ChannelState == State<Success, Failure> {
    /// Default initializer: uses DefaultState
    init() {
        self.init(State<Success, Failure>())
    }
}

extension Channel {
    @discardableResult
    func fulfill(_ value: Success) async -> Bool {
        if await state.result == nil {
            await state.setResult(result: value)

            for waiters in await state.waiters {
                waiters.resume(returning: value)
            }

            await state.removeAllWaiters()

            return false
        }

        return true
    }

    @discardableResult
    func fail(_ failure: Failure) async -> Bool {
        if await state.failure == nil {
            await state.setFailure(failure: failure)

            for waiters in await state.waiters {
                waiters.resume(throwing: failure)
            }

            await state.removeAllWaiters()

            return false
        }

        return true
    }

    var value: Success {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    if let result = await state.result {
                        continuation.resume(returning: result)
                    } else if let failure = await self.state.failure {
                        continuation.resume(throwing: failure)
                    } else {
                        await state.appendWaiters(waiters: continuation)
                    }
                }
            }
        }
    }
}
