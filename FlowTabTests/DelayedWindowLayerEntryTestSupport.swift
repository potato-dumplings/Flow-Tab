import Foundation
@testable import FlowTab

@MainActor
final class ManualDelayedWindowLayerEntryScheduler:
    DelayedWindowLayerEntryScheduling
{
    private struct ScheduledAction {
        let fireAtMilliseconds: Double
        let interval: TimeInterval
        let token: ManualDelayedWindowLayerEntryToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []
    private(set) var nowMilliseconds: Double

    init(nowMilliseconds: Double = 1_000) {
        self.nowMilliseconds = nowMilliseconds
    }

    var pendingCount: Int {
        scheduled.filter(\.token.isAvailable).count
    }

    var scheduledIntervals: [TimeInterval] {
        scheduled.map(\.interval)
    }

    func scheduleDeadline(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any DelayedWindowLayerEntryCancellable {
        let token = ManualDelayedWindowLayerEntryToken()
        scheduled.append(
            ScheduledAction(
                fireAtMilliseconds:
                    nowMilliseconds + interval * 1_000,
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    func advance(byMilliseconds interval: Double) {
        precondition(interval >= 0)
        nowMilliseconds += interval
    }

    @discardableResult
    func fireNextDeadline(
        advancingClock: Bool = true
    ) -> Bool {
        guard let scheduledAction = scheduled.first(where: {
            $0.token.isAvailable
        }) else {
            return false
        }
        scheduledAction.token.markFired()
        if advancingClock {
            nowMilliseconds = max(
                nowMilliseconds,
                scheduledAction.fireAtMilliseconds
            )
        }
        scheduledAction.action()
        return true
    }

    func fireAllDeadlines() {
        while fireNextDeadline() {}
    }
}

@MainActor
private final class ManualDelayedWindowLayerEntryToken:
    DelayedWindowLayerEntryCancellable
{
    private(set) var isCancelled = false
    private(set) var didFire = false

    var isAvailable: Bool {
        !isCancelled && !didFire
    }

    func markFired() {
        didFire = true
    }

    func cancel() {
        isCancelled = true
    }
}
