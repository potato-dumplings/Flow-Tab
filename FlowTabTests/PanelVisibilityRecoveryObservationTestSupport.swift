import Foundation
import XCTest
@testable import FlowTab

@MainActor
final class ManualPanelVisibilityRecoveryObservationScheduler:
    PanelVisibilityRecoveryObservationScheduling
{
    private enum Kind {
        case conditionReadback
        case watchdog
    }

    private struct ScheduledAction {
        let kind: Kind
        let token: ManualPanelVisibilityRecoveryObservationToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var pendingConditionReadbackCount: Int {
        pendingCount(for: .conditionReadback)
    }

    var pendingWatchdogCount: Int {
        pendingCount(for: .watchdog)
    }

    func scheduleConditionReadback(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelVisibilityRecoveryObservationCancellable {
        XCTAssertEqual(interval, 0.01)
        return schedule(kind: .conditionReadback, action)
    }

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelVisibilityRecoveryObservationCancellable {
        XCTAssertEqual(interval, 1.0)
        return schedule(kind: .watchdog, action)
    }

    func fireConditionReadback() {
        fireNext(kind: .conditionReadback)
    }

    func fireWatchdog() {
        fireNext(kind: .watchdog)
    }

    func fireAll() {
        while let action = scheduled.first(where: {
            $0.token.isAvailable
        }) {
            action.token.markFired()
            action.action()
        }
    }

    private func schedule(
        kind: Kind,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelVisibilityRecoveryObservationCancellable {
        let token =
            ManualPanelVisibilityRecoveryObservationToken()
        scheduled.append(
            ScheduledAction(
                kind: kind,
                token: token,
                action: action
            )
        )
        return token
    }

    private func pendingCount(for kind: Kind) -> Int {
        scheduled.filter {
            $0.kind == kind && $0.token.isAvailable
        }.count
    }

    private func fireNext(kind: Kind) {
        guard let action = scheduled.first(where: {
            $0.kind == kind && $0.token.isAvailable
        }) else {
            return XCTFail("Expected pending \(kind) work.")
        }
        action.token.markFired()
        action.action()
    }
}

@MainActor
private final class ManualPanelVisibilityRecoveryObservationToken:
    PanelVisibilityRecoveryObservationCancellable
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
