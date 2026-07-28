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
                "Expected a pending initial-visibility watchdog."
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
            watchdogInterval: 0.35,
            readback: {
                Self.initialPanelVisibilitySnapshot(userVisible: true)
            },
            onVisible: { visibleEvidence.append($0) },
            onWatchdog: { _ in
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
        XCTAssertFalse(owner.hasPendingWatchdog)
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
            watchdogInterval: 0.35,
            readback: { snapshot },
            onVisible: { visibleEvidence.append($0) },
            onWatchdog: { _ in
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
        XCTAssertFalse(owner.hasPendingWatchdog)
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
            watchdogInterval: 0.35,
            readback: { snapshot },
            onVisible: { _ in completionCount += 1 },
            onWatchdog: { _ in
                XCTFail("Current evidence completes before the watchdog.")
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
    func testInitialPanelVisibilityWatchdogReportsLastEventAndFinalReadback() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: false
        )
        var failures: [InitialPanelVisibilityWatchdogFailure] = []
        let generation = owner.start(
            trigger: "watchdog",
            presentationGeneration: 17,
            watchdogInterval: 0.35,
            readback: { snapshot },
            onVisible: { _ in
                XCTFail("Unsatisfied visibility must reach the watchdog.")
            },
            onWatchdog: { failures.append($0) }
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

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].trigger, "watchdog")
        XCTAssertEqual(failures[0].lastEventEvidence.source, .panelExposed)
        XCTAssertTrue(failures[0].lastEventEvidence.snapshot.panelKey)
        XCTAssertEqual(failures[0].finalEvidence.source, .watchdogReadback)
        XCTAssertTrue(failures[0].finalEvidence.snapshot.appActive)
        XCTAssertTrue(
            failures[0].logFields.contains("condition=userVisible")
        )
        XCTAssertEqual(owner.lastFailure, failures[0])
    }

    @MainActor
    func testInitialPanelVisibilityDelayedWatchdogAcceptsFinalVisibleReadback() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.initialPanelVisibilitySnapshot(
            userVisible: false
        )
        var visibleEvidence: [InitialPanelVisibilityEvidence] = []
        var failureCount = 0
        _ = owner.start(
            trigger: "slow_scheduler",
            presentationGeneration: 19,
            watchdogInterval: 0.35,
            readback: { snapshot },
            onVisible: { visibleEvidence.append($0) },
            onWatchdog: { _ in failureCount += 1 }
        )

        snapshot = Self.initialPanelVisibilitySnapshot(userVisible: true)
        scheduler.fireNext()

        XCTAssertEqual(
            visibleEvidence.map(\.source),
            [.watchdogReadback]
        )
        XCTAssertEqual(failureCount, 0)
        XCTAssertNil(owner.lastFailure)
    }

    @MainActor
    func testInitialPanelVisibilityCancellationInvalidatesPendingWatchdog() {
        let scheduler = ManualInitialPanelVisibilityObservationScheduler()
        let owner = InitialPanelVisibilityObservationOwner(
            scheduler: scheduler
        )
        var callbackCount = 0
        _ = owner.start(
            trigger: "cancel",
            presentationGeneration: 23,
            watchdogInterval: 0.35,
            readback: {
                Self.initialPanelVisibilitySnapshot(userVisible: false)
            },
            onVisible: { _ in callbackCount += 1 },
            onWatchdog: { _ in callbackCount += 1 }
        )

        owner.cancel(invalidate: true)
        scheduler.fireAll()

        XCTAssertEqual(owner.generation, 2)
        XCTAssertNil(owner.currentTrigger)
        XCTAssertFalse(owner.hasPendingWatchdog)
        XCTAssertEqual(callbackCount, 0)
    }

    @MainActor
    func testInitialPanelVisibilityRapidReplacementPressureKeepsOneWatchdog() {
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
                watchdogInterval: 0.35,
                readback: {
                    Self.initialPanelVisibilitySnapshot(
                        userVisible: false
                    )
                },
                onVisible: { _ in callbackCount += 1 },
                onWatchdog: { _ in callbackCount += 1 }
            )
        }

        XCTAssertEqual(owner.generation, replacementCount)
        XCTAssertEqual(owner.currentTrigger, "pressure_1999")
        XCTAssertEqual(scheduler.pendingIntervals, [0.35])
        XCTAssertTrue(owner.hasPendingWatchdog)

        owner.cancel(invalidate: true)
        scheduler.fireAll()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
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
