import Foundation

enum PanelVisibilityRecoveryEvidenceSource: String, Equatable {
    case initialReadback
    case softActionReadback
    case orderOutActionReadback
    case orderFrontActionReadback
    case panelOcclusionChanged
    case panelBecameKey
    case panelExposed
    case conditionReadback
    case watchdogReadback
}

struct PanelVisibilityRecoveryEvidence: Equatable {
    let source: PanelVisibilityRecoveryEvidenceSource
    let recoveryGeneration: Int
    let presentationGeneration: Int
    let attempt: Int
    let snapshot: PanelVisibilitySnapshot
}

struct PanelVisibilityRecoveryWatchdogFailure: Equatable {
    let trigger: String
    let recoveryGeneration: Int
    let presentationGeneration: Int
    let mode: SwitcherPanelController.PanelVisibilityRecoveryMode
    let completedAttemptCount: Int
    let lastEvidence: PanelVisibilityRecoveryEvidence
    let finalEvidence: PanelVisibilityRecoveryEvidence

    var logFields: String {
        "condition=userVisible "
            + "mode=\(mode.debugName) "
            + "completedAttempts=\(completedAttemptCount) "
            + "lastSource=\(lastEvidence.source.rawValue) "
            + "last{\(lastEvidence.snapshot.logFields)} "
            + "finalSource=\(finalEvidence.source.rawValue) "
            + "final{\(finalEvidence.snapshot.logFields)}"
    }
}

struct PanelVisibilityRecoveryActions {
    let performSoftReorder:
        @MainActor (_ attempt: Int, _ totalAttempts: Int) -> Void
    let performOrderOut:
        @MainActor (_ attempt: Int, _ totalAttempts: Int) -> Void
    let performOrderFront:
        @MainActor (_ attempt: Int, _ totalAttempts: Int) -> Void
}

struct PanelVisibilityRecoveryCallbacks {
    let onAttempt:
        @MainActor (_ attempt: Int, _ totalAttempts: Int) -> Void
    let onVisible:
        @MainActor (PanelVisibilityRecoveryEvidence) -> Void
    let onWatchdog:
        @MainActor (PanelVisibilityRecoveryWatchdogFailure) -> Void
}

enum PanelVisibilityRecoveryPhase: Equatable {
    case awaitingOrderOut
    case awaitingVisibility
}

struct PanelVisibilityRecoveryPendingObservation {
    let trigger: String
    let recoveryGeneration: Int
    let presentationGeneration: Int
    let mode: SwitcherPanelController.PanelVisibilityRecoveryMode
    let maximumAttemptCount: Int
    let conditionReadbackInterval: TimeInterval
    let readback: @MainActor () -> PanelVisibilitySnapshot
    let actions: PanelVisibilityRecoveryActions
    let callbacks: PanelVisibilityRecoveryCallbacks
    var attempt = 0
    var phase = PanelVisibilityRecoveryPhase.awaitingVisibility
    var lastEvidence: PanelVisibilityRecoveryEvidence?
    var conditionReadbackToken:
        (any PanelVisibilityRecoveryObservationCancellable)?
    var watchdogToken:
        (any PanelVisibilityRecoveryObservationCancellable)?
}

@MainActor
protocol PanelVisibilityRecoveryObservationCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol PanelVisibilityRecoveryObservationScheduling: AnyObject {
    func scheduleConditionReadback(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelVisibilityRecoveryObservationCancellable

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelVisibilityRecoveryObservationCancellable
}

@MainActor
private final class PanelVisibilityRecoveryObservationToken:
    PanelVisibilityRecoveryObservationCancellable
{
    private let task: Task<Void, Never>

    init(
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        task = Task { @MainActor in
            await operation()
        }
    }

    func cancel() {
        task.cancel()
    }

    deinit {
        task.cancel()
    }
}

@MainActor
final class PanelVisibilityRecoveryObservationScheduler:
    PanelVisibilityRecoveryObservationScheduling
{
    func scheduleConditionReadback(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelVisibilityRecoveryObservationCancellable {
        PanelVisibilityRecoveryObservationToken {
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        (interval * 1_000_000_000).rounded()
                    )
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelVisibilityRecoveryObservationCancellable {
        PanelVisibilityRecoveryObservationToken {
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        (interval * 1_000_000_000).rounded()
                    )
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
