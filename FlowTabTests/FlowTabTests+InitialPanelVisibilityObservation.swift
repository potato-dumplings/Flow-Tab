import Foundation
import XCTest
@testable import FlowTab

@MainActor
final class ManualInitialPanelVisibilityObservationScheduler:
    InitialPanelVisibilityObservationScheduling
{
    private struct ScheduledAction {
        let interval: TimeInterval
        let token: ManualInitialPanelVisibilityObservationToken
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
    ) -> any InitialPanelVisibilityObservationCancellable {
        let token = ManualInitialPanelVisibilityObservationToken()
        scheduled.append(
            ScheduledAction(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    func fireNext() {
        guard let scheduledAction = scheduled.first(where: {
            $0.token.isAvailable
        }) else {
            return XCTFail(
                "Expected a pending initial-visibility recovery escalation."
            )
        }
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

@MainActor
private final class ImmediateInitialPanelVisibilityObservationScheduler:
    InitialPanelVisibilityObservationScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialPanelVisibilityObservationCancellable {
        let token = ManualInitialPanelVisibilityObservationToken()
        action()
        return token
    }
}

@MainActor
private final class ManualInitialPanelVisibilityObservationToken:
    InitialPanelVisibilityObservationCancellable
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

extension FlowTabTests {
    @MainActor
    func testInitialPanelVisibilityObservationAcceptsSatisfiedInitialReadback() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var visibleEvidence: [InitialPanelVisibilityEvidence] = []

        let generation = owner.start(
            trigger: "already_visible",
            presentationGeneration: 7,
            recoveryEscalationInterval: 0.35,
            readback: {
                Self.initialPanelVisibilitySnapshot(userVisible: true)
            },
            onVisible: { visibleEvidence.append($0) },
            onRecoveryEscalation: { _ in
                XCTFail("Satisfied initial readback must complete.")
            }
        )

        XCTAssertEqual(generation, 1)
        XCTAssertEqual(
            visibleEvidence.map(\.source),
            [.initialReadback]
        )
        XCTAssertEqual(
            visibleEvidence.map(\.presentationGeneration),
            [7]
        )
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
        XCTAssertFalse(owner.hasPendingRecoveryEscalation)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialPanelVisibilityObservationCompletesFromMatchingWindowEvidence() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: false
        )
        var visibleEvidence: [InitialPanelVisibilityEvidence] = []
        let generation = owner.start(
            trigger: "window_event",
            presentationGeneration: 11,
            recoveryEscalationInterval: 0.35,
            readback: { snapshot },
            onVisible: { visibleEvidence.append($0) },
            onRecoveryEscalation: { _ in
                XCTFail("Matching window evidence must complete.")
            }
        )

        XCTAssertEqual(scheduler.pendingIntervals, [0.35])
        snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: true,
            panelKey: true
        )
        XCTAssertTrue(
            owner.observe(
                source: .panelBecameKey,
                observationGeneration: generation,
                presentationGeneration: 11
            )
        )

        XCTAssertEqual(
            visibleEvidence.map(\.source),
            [.panelBecameKey]
        )
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
        XCTAssertFalse(owner.hasPendingRecoveryEscalation)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialPanelVisibilityObservationRejectsStaleAndDuplicateEvidence() {
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: ManualInitialPanelVisibilityObservationScheduler()
        )
        var snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: false
        )
        var completionCount = 0
        let generation = owner.start(
            trigger: "identity",
            presentationGeneration: 13,
            recoveryEscalationInterval: 0.35,
            readback: { snapshot },
            onVisible: { _ in completionCount += 1 },
            onRecoveryEscalation: { _ in
                XCTFail("Current evidence completes before recovery escalation.")
            }
        )

        snapshot = Self.initialPanelVisibilitySnapshot(userVisible: true)
        XCTAssertFalse(
            owner.observe(
                source: .panelExposed,
                observationGeneration: generation - 1,
                presentationGeneration: 13
            )
        )
        XCTAssertFalse(
            owner.observe(
                source: .panelExposed,
                observationGeneration: generation,
                presentationGeneration: 12
            )
        )
        XCTAssertTrue(
            owner.observe(
                source: .panelExposed,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertFalse(
            owner.observe(
                source: .panelExposed,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertEqual(completionCount, 1)
    }

    @MainActor
    func testInitialPanelVisibilityRecoveryEscalationPreservesObservationForLaterEvidence() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: false
        )
        var visibleEvidence: [InitialPanelVisibilityEvidence] = []
        var escalations: [InitialPanelVisibilityRecoveryEscalation] = []
        let generation = owner.start(
            trigger: "recovery_escalation",
            presentationGeneration: 17,
            recoveryEscalationInterval: 0.35,
            readback: { snapshot },
            onVisible: { visibleEvidence.append($0) },
            onRecoveryEscalation: { escalations.append($0) }
        )

        snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: false,
            panelKey: true
        )
        XCTAssertFalse(
            owner.observe(
                source: .panelExposed,
                observationGeneration: generation,
                presentationGeneration: 17
            )
        )
        snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: false,
            panelKey: true,
            appActive: true
        )
        scheduler.fireNext()

        XCTAssertEqual(escalations.count, 1)
        XCTAssertEqual(escalations[0].trigger, "recovery_escalation")
        XCTAssertEqual(escalations[0].lastEventEvidence.source, .panelExposed)
        XCTAssertTrue(escalations[0].lastEventEvidence.snapshot.panelKey)
        XCTAssertEqual(
            escalations[0].finalEvidence.source,
            .recoveryEscalationReadback
        )
        XCTAssertTrue(escalations[0].finalEvidence.snapshot.appActive)
        XCTAssertTrue(
            escalations[0].logFields.contains("condition=userVisible")
        )
        XCTAssertEqual(owner.lastRecoveryEscalation, escalations[0])
        XCTAssertTrue(owner.isObserving)
        XCTAssertFalse(owner.hasPendingRecoveryEscalation)

        snapshot = Self.initialPanelVisibilitySnapshot(userVisible: true)
        XCTAssertTrue(
            owner.observe(
                source: .panelExposed,
                observationGeneration: generation,
                presentationGeneration: 17
            )
        )
        XCTAssertEqual(visibleEvidence.map(\.source), [.panelExposed])
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialPanelVisibilityDelayedRecoveryEscalationAcceptsFinalVisibleReadback() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: false
        )
        var visibleEvidence: [InitialPanelVisibilityEvidence] = []
        var escalationCount = 0
        _ = owner.start(
            trigger: "slow_scheduler",
            presentationGeneration: 19,
            recoveryEscalationInterval: 0.35,
            readback: { snapshot },
            onVisible: { visibleEvidence.append($0) },
            onRecoveryEscalation: { _ in escalationCount += 1 }
        )

        snapshot = Self.initialPanelVisibilitySnapshot(userVisible: true)
        scheduler.fireNext()

        XCTAssertEqual(
            visibleEvidence.map(\.source),
            [.recoveryEscalationReadback]
        )
        XCTAssertEqual(escalationCount, 0)
        XCTAssertNil(owner.lastRecoveryEscalation)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialPanelVisibilityCancellationInvalidatesPendingRecoveryEscalation() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var callbackCount = 0
        _ = owner.start(
            trigger: "cancel",
            presentationGeneration: 23,
            recoveryEscalationInterval: 0.35,
            readback: {
                Self.initialPanelVisibilitySnapshot(userVisible: false)
            },
            onVisible: { _ in callbackCount += 1 },
            onRecoveryEscalation: { _ in callbackCount += 1 }
        )

        owner.cancel(invalidate: true)
        scheduler.fireAll()

        XCTAssertEqual(owner.generation, 2)
        XCTAssertNil(owner.currentTrigger)
        XCTAssertFalse(owner.hasPendingRecoveryEscalation)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(callbackCount, 0)
    }

    @MainActor
    func testInitialPanelVisibilityRapidReplacementPressureKeepsOneRecoveryEscalation() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var callbackCount = 0
        let replacementCount = 2_000

        for index in 0..<replacementCount {
            _ = owner.start(
                trigger: "pressure_\(index)",
                presentationGeneration: index,
                recoveryEscalationInterval: 0.35,
                readback: {
                    Self.initialPanelVisibilitySnapshot(
                        userVisible: false
                    )
                },
                onVisible: { _ in callbackCount += 1 },
                onRecoveryEscalation: { _ in callbackCount += 1 }
            )
        }

        XCTAssertEqual(owner.generation, replacementCount)
        XCTAssertEqual(owner.currentTrigger, "pressure_1999")
        XCTAssertEqual(scheduler.pendingIntervals, [0.35])
        XCTAssertTrue(owner.hasPendingRecoveryEscalation)

        owner.cancel(invalidate: true)
        scheduler.fireAll()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testInitialPanelVisibilitySynchronousRecoveryEscalationRetainsNoSchedule() {
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: ImmediateInitialPanelVisibilityObservationScheduler()
        )
        var snapshot = Self.initialPanelVisibilitySnapshot(userVisible: false)
        var escalations: [InitialPanelVisibilityRecoveryEscalation] = []
        var visibleEvidence: [InitialPanelVisibilityEvidence] = []

        let generation = owner.start(
            trigger: "synchronous_escalation",
            presentationGeneration: 31,
            recoveryEscalationInterval: 0.35,
            readback: { snapshot },
            onVisible: { visibleEvidence.append($0) },
            onRecoveryEscalation: { escalations.append($0) }
        )

        XCTAssertEqual(escalations.count, 1)
        XCTAssertTrue(owner.isObserving)
        XCTAssertFalse(owner.hasPendingRecoveryEscalation)
        snapshot = Self.initialPanelVisibilitySnapshot(userVisible: true)
        XCTAssertTrue(
            owner.observe(
                source: .panelBecameKey,
                observationGeneration: generation,
                presentationGeneration: 31
            )
        )
        XCTAssertEqual(visibleEvidence.map(\.source), [.panelBecameKey])
        XCTAssertFalse(owner.isObserving)
    }

    private static func initialPanelVisibilitySnapshot(
        userVisible: Bool,
        panelKey: Bool = false,
        appActive: Bool = false
    ) -> PanelVisibilitySnapshot {
        PanelVisibilitySnapshot(
            panelPresented: true,
            userVisible: userVisible,
            occlusionVisible: userVisible,
            panelKey: panelKey,
            appActive: appActive,
            searchActive: false,
            inputFocused: false,
            firstResponder: "nil"
        )
    }
}
