import CoreGraphics
import Foundation
import XCTest
@testable import FlowTab

@MainActor
final class ManualActiveSpaceTransitionObservationScheduler:
    ActiveSpaceTransitionObservationScheduling
{
    private struct ScheduledAction {
        let token: ManualActiveSpaceTransitionObservationToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var pendingCount: Int {
        scheduled.filter(\.token.isAvailable).count
    }

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any ActiveSpaceTransitionObservationCancellable {
        XCTAssertEqual(interval, 1.0)
        let token = ManualActiveSpaceTransitionObservationToken()
        scheduled.append(
            ScheduledAction(token: token, action: action)
        )
        return token
    }

    func fireNext() {
        guard let scheduledAction = scheduled.first(where: {
            $0.token.isAvailable
        }) else {
            return XCTFail(
                "Expected a pending Active Space transition watchdog."
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
private final class ManualActiveSpaceTransitionObservationToken:
    ActiveSpaceTransitionObservationCancellable
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
    func testActiveSpaceTransitionCapturesBaselineBeforeRequestReturnEvidence() {
        let scheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let owner = ActiveSpaceTransitionObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.activeSpaceSnapshot(
            generation: 7,
            currentSpaceID: 21,
            userVisible: true
        )
        var completions: [ActiveSpaceTransitionEvidence] = []
        let generation = owner.start(
            trigger: "request_return",
            presentationGeneration: 11,
            watchdogInterval: 1.0,
            readback: { snapshot },
            onResolved: { completions.append($0) },
            onWatchdog: { _ in
                XCTFail("Request-return evidence must resolve.")
            }
        )

        snapshot = Self.activeSpaceSnapshot(
            generation: 8,
            currentSpaceID: 22,
            userVisible: false
        )
        XCTAssertTrue(
            owner.observe(
                source: .requestReturnReadback,
                observationGeneration: generation,
                presentationGeneration: 11
            )
        )

        XCTAssertEqual(completions.map(\.source), [.requestReturnReadback])
        XCTAssertEqual(completions.first?.baseline.spaceGeneration, 7)
        XCTAssertEqual(completions.first?.snapshot.spaceGeneration, 8)
        XCTAssertEqual(completions.first?.currentSpaceIdentityChanged, true)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    @MainActor
    func testActiveSpaceTransitionRejectsStaleDuplicateAndOutOfOrderEvidence() {
        let scheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let owner = ActiveSpaceTransitionObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.activeSpaceSnapshot(
            generation: 13,
            currentSpaceID: 31,
            userVisible: true
        )
        var completions: [ActiveSpaceTransitionEvidence] = []
        let generation = owner.start(
            trigger: "identity",
            presentationGeneration: 17,
            watchdogInterval: 1.0,
            readback: { snapshot },
            onResolved: { completions.append($0) },
            onWatchdog: { _ in
                XCTFail("Matching projection evidence must resolve.")
            }
        )

        snapshot = Self.activeSpaceSnapshot(
            generation: 12,
            currentSpaceID: 30,
            userVisible: false
        )
        XCTAssertFalse(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: generation,
                presentationGeneration: 17
            )
        )
        snapshot = Self.activeSpaceSnapshot(
            generation: 14,
            currentSpaceID: 32,
            userVisible: false
        )
        XCTAssertFalse(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: generation - 1,
                presentationGeneration: 17
            )
        )
        XCTAssertFalse(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: generation,
                presentationGeneration: 16
            )
        )
        XCTAssertTrue(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: generation,
                presentationGeneration: 17
            )
        )
        XCTAssertFalse(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: generation,
                presentationGeneration: 17
            )
        )

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.currentSpaceIdentityChanged, true)
    }

    @MainActor
    func testActiveSpaceTransitionSlowSchedulingChangesOnlyCompletionTime() {
        let scheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let owner = ActiveSpaceTransitionObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.activeSpaceSnapshot(
            generation: 23,
            currentSpaceID: 41,
            userVisible: true
        )
        var completions: [ActiveSpaceTransitionEvidence] = []
        var failureCount = 0
        _ = owner.start(
            trigger: "slow",
            presentationGeneration: 29,
            watchdogInterval: 1.0,
            readback: { snapshot },
            onResolved: { completions.append($0) },
            onWatchdog: { _ in failureCount += 1 }
        )

        snapshot = Self.activeSpaceSnapshot(
            generation: 24,
            currentSpaceID: 42,
            userVisible: false
        )
        scheduler.fireNext()

        XCTAssertEqual(completions.map(\.source), [.watchdogReadback])
        XCTAssertEqual(failureCount, 0)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testActiveSpaceTransitionWatchdogReportsLastAndFinalEvidence() {
        let scheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let owner = ActiveSpaceTransitionObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.activeSpaceSnapshot(
            generation: 37,
            currentSpaceID: 51,
            userVisible: true
        )
        var failures: [ActiveSpaceTransitionWatchdogFailure] = []
        let generation = owner.start(
            trigger: "watchdog",
            presentationGeneration: 43,
            watchdogInterval: 1.0,
            readback: { snapshot },
            onResolved: { _ in
                XCTFail("Unchanged generation must reach the watchdog.")
            },
            onWatchdog: { failures.append($0) }
        )

        snapshot = Self.activeSpaceSnapshot(
            generation: 37,
            currentSpaceID: 51,
            userVisible: false
        )
        XCTAssertFalse(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: generation,
                presentationGeneration: 43
            )
        )
        snapshot = Self.activeSpaceSnapshot(
            generation: 37,
            currentSpaceID: 52,
            userVisible: false
        )
        scheduler.fireNext()

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(
            failures.first?.lastEvidence.source,
            .projectionUpdateReadback
        )
        XCTAssertEqual(
            failures.first?.finalEvidence.source,
            .watchdogReadback
        )
        XCTAssertTrue(
            failures.first?.logFields.contains(
                "condition=spaceGenerationAdvanced"
            ) == true
        )
        XCTAssertEqual(owner.lastFailure, failures.first)
    }

    @MainActor
    func testActiveSpaceTransitionReplacementAndCancellationDiscardWork() {
        let scheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let owner = ActiveSpaceTransitionObservationOwner(
            scheduler: scheduler
        )
        var callbackCount = 0

        for generation in 1...2_000 {
            _ = owner.start(
                trigger: "replace_\(generation)",
                presentationGeneration: generation,
                watchdogInterval: 1.0,
                readback: {
                    Self.activeSpaceSnapshot(
                        generation: UInt64(generation),
                        currentSpaceID: generation,
                        userVisible: false
                    )
                },
                onResolved: { _ in callbackCount += 1 },
                onWatchdog: { _ in callbackCount += 1 }
            )
        }

        XCTAssertTrue(owner.isObserving)
        XCTAssertEqual(scheduler.pendingCount, 1)
        owner.cancel()
        scheduler.fireAll()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    private static func activeSpaceSnapshot(
        generation: UInt64,
        currentSpaceID: Int,
        userVisible: Bool
    ) -> ActiveSpaceTransitionSnapshot {
        ActiveSpaceTransitionSnapshot(
            spaceGeneration: generation,
            currentSpaceIdentity: [
                ActiveSpaceDisplayIdentity(
                    displayID: CGDirectDisplayID(1),
                    currentSpaceID: currentSpaceID
                )
            ],
            panelVisibility: PanelVisibilitySnapshot(
                panelPresented: userVisible,
                userVisible: userVisible,
                occlusionVisible: userVisible,
                panelKey: userVisible,
                appActive: false,
                searchActive: false,
                inputFocused: false,
                firstResponder: "nil"
            )
        )
    }
}
