import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    var focusRecoveryPolicy: RuntimeFocusRecoveryPolicy {
        RuntimeFocusRecoveryPolicy(
            pollingIntervals: [0.1, 0.3],
            watchdogInterval: 2
        )
    }

    func focusRecoveryTarget(
        appID: String,
        pid: pid_t = 900
    ) -> RuntimeFocusRecoveryTarget {
        RuntimeFocusRecoveryTarget(
            appID: appID,
            pid: pid,
            windowID: "cg:\(pid):800",
            targetCGWindowID: 800
        )
    }

    func focusRecoveryReadback(
        conditionSatisfied: Bool,
        processIsTerminated: Bool = false,
        targetCGWindowID: CGWindowID = 800
    ) -> RuntimeFocusRecoveryReadback {
        RuntimeFocusRecoveryReadback(
            completed: conditionSatisfied,
            observation: RuntimeFocusRecoveryObservation(
                conditionSatisfied: conditionSatisfied,
                processIsTerminated: processIsTerminated,
                targetIsVisible: conditionSatisfied,
                focusedCGWindowID:
                    conditionSatisfied ? targetCGWindowID : nil,
                frontmostCGWindowID:
                    conditionSatisfied ? targetCGWindowID : nil,
                visibleCGWindowIDs:
                    conditionSatisfied ? [targetCGWindowID] : []
            )
        )
    }
}

@MainActor
final class ManualRuntimeFocusRecoveryScheduler:
    RuntimeFocusRecoveryScheduling
{
    private struct ScheduledAction {
        let interval: TimeInterval
        let token: ManualRuntimeFocusRecoveryToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var pendingIntervals: [TimeInterval] {
        scheduled.compactMap {
            $0.token.isAvailable ? $0.interval : nil
        }
    }

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeFocusRecoveryCancellable {
        let token = ManualRuntimeFocusRecoveryToken()
        scheduled.append(
            ScheduledAction(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    func fireNext(after interval: TimeInterval) {
        guard let index = scheduled.firstIndex(where: {
            $0.interval == interval && $0.token.isAvailable
        }) else {
            return XCTFail(
                "Missing scheduled focus recovery action after \(interval)"
            )
        }
        let scheduledAction = scheduled[index]
        scheduledAction.token.markFired()
        scheduledAction.action()
    }

    func fireAll() {
        while let scheduledAction = scheduled.first(where: {
            $0.token.isAvailable
        }) {
            scheduledAction.token.markFired()
            scheduledAction.action()
        }
    }
}

private final class ManualRuntimeFocusRecoveryToken:
    RuntimeFocusRecoveryCancellable
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
