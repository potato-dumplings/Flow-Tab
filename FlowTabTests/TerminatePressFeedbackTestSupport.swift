import Foundation
@testable import FlowTab

@MainActor
final class ManualTerminatePressFeedbackScheduler:
    TerminatePressFeedbackScheduling
{
    private struct ScheduledAction {
        let interval: TimeInterval
        let token: ManualTerminatePressFeedbackToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var scheduledIntervals: [TimeInterval] {
        scheduled.map(\.interval)
    }

    func scheduleCompletion(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminatePressFeedbackCancellable {
        let token = ManualTerminatePressFeedbackToken()
        scheduled.append(
            ScheduledAction(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    @discardableResult
    func fire(
        at index: Int,
        includingCancelled: Bool = false
    ) -> Bool {
        guard scheduled.indices.contains(index) else {
            return false
        }
        let scheduledAction = scheduled[index]
        guard !scheduledAction.token.didFire else {
            return false
        }
        guard
            includingCancelled
                || !scheduledAction.token.isCancelled
        else {
            return false
        }
        scheduledAction.token.didFire = true
        scheduledAction.action()
        return true
    }
}

@MainActor
final class ManualTerminatePressFeedbackToken:
    TerminatePressFeedbackCancellable
{
    private(set) var isCancelled = false
    var didFire = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
final class SynchronousTerminatePressFeedbackScheduler:
    TerminatePressFeedbackScheduling
{
    let token = ManualTerminatePressFeedbackToken()

    func scheduleCompletion(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminatePressFeedbackCancellable {
        action()
        return token
    }
}
