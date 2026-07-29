import Foundation
@testable import FlowTab

@MainActor
final class ManualTabSwitchStressClock:
    TabSwitchStressMonotonicClock
{
    private(set) var nowNanoseconds: UInt64

    init(nowNanoseconds: UInt64 = 0) {
        self.nowNanoseconds = nowNanoseconds
    }

    func advance(
        by nanoseconds: UInt64
    ) {
        nowNanoseconds &+= nanoseconds
    }
}

@MainActor
final class ManualTabSwitchStressScheduler:
    TabSwitchStressScheduling
{
    final class Token:
        TabSwitchStressCancellable
    {
        let action:
            @MainActor @Sendable () -> Void
        private(set) var isCancelled = false

        init(
            action:
                @escaping @MainActor @Sendable () -> Void
        ) {
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var delays: [UInt64] = []
    private(set) var tokens: [Token] = []

    func schedule(
        afterNanoseconds nanoseconds: UInt64,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any TabSwitchStressCancellable {
        delays.append(nanoseconds)
        let token = Token(action: action)
        tokens.append(token)
        return token
    }

    func fire(
        at index: Int,
        includingCancelled: Bool = false
    ) {
        let token = tokens[index]
        guard includingCancelled
                || !token.isCancelled
        else {
            return
        }
        token.action()
    }
}

@MainActor
final class SynchronousTabSwitchStressScheduler:
    TabSwitchStressScheduling
{
    private let clock: ManualTabSwitchStressClock
    private(set) var tokens:
        [ManualTabSwitchStressScheduler.Token] = []

    init(clock: ManualTabSwitchStressClock) {
        self.clock = clock
    }

    func schedule(
        afterNanoseconds nanoseconds: UInt64,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any TabSwitchStressCancellable {
        let token =
            ManualTabSwitchStressScheduler.Token(
                action: action
            )
        tokens.append(token)
        clock.advance(by: nanoseconds)
        action()
        return token
    }
}
