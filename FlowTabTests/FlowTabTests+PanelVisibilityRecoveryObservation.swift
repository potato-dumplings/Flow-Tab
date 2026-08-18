import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testPanelVisibilityRecoveryAcceptsSatisfiedInitialReadback() {
        let scheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let owner = PanelVisibilityRecoveryObservationOwner(
            scheduler: scheduler
        )
        var actionCount = 0
        var completions: [PanelVisibilityRecoveryEvidence] = []

        let remainedPending = owner.start(
            trigger: "already_visible",
            recoveryGeneration: 3,
            presentationGeneration: 5,
            mode: .hardReorder,
            maximumAttemptCount: 4,
            conditionReadbackInterval: 0.01,
            watchdogInterval: 1.0,
            readback: {
                Self.panelRecoverySnapshot(
                    panelPresented: true,
                    userVisible: true
                )
            },
            actions: .init(
                performSoftReorder: { _, _ in actionCount += 1 },
                performOrderOut: { _, _ in actionCount += 1 },
                performOrderFront: { _, _ in actionCount += 1 }
            ),
            callbacks: .init(
                onAttempt: { _, _ in actionCount += 1 },
                onVisible: { completions.append($0) },
                onWatchdog: { _ in
                    XCTFail("Initial visible readback must complete.")
                }
            )
        )

        XCTAssertFalse(remainedPending)
        XCTAssertEqual(completions.map(\.source), [.initialReadback])
        XCTAssertEqual(actionCount, 0)
        XCTAssertEqual(scheduler.pendingWatchdogCount, 0)
    }

    @MainActor
    func testPanelVisibilityRecoveryWaitsForOrderOutReadbackAndWindowEvidence() {
        let scheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let owner = PanelVisibilityRecoveryObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.panelRecoverySnapshot(
            panelPresented: true,
            userVisible: false
        )
        var orderOutCount = 0
        var orderFrontCount = 0
        var completions: [PanelVisibilityRecoveryEvidence] = []

        XCTAssertTrue(
            owner.start(
                trigger: "ordered",
                recoveryGeneration: 7,
                presentationGeneration: 11,
                mode: .hardReorder,
                maximumAttemptCount: 4,
                conditionReadbackInterval: 0.01,
                watchdogInterval: 1.0,
                readback: { snapshot },
                actions: .init(
                    performSoftReorder: { _, _ in
                        XCTFail("Hard recovery must not soft reorder.")
                    },
                    performOrderOut: { _, _ in
                        orderOutCount += 1
                    },
                    performOrderFront: { _, _ in
                        orderFrontCount += 1
                    }
                ),
                callbacks: .init(
                    onAttempt: { _, _ in },
                    onVisible: { completions.append($0) },
                    onWatchdog: { _ in
                        XCTFail("Matching order evidence must complete.")
                    }
                )
            )
        )
        XCTAssertEqual(orderOutCount, 1)
        XCTAssertEqual(orderFrontCount, 0)

        snapshot = Self.panelRecoverySnapshot(
            panelPresented: true,
            userVisible: true
        )
        XCTAssertFalse(
            owner.observe(
                source: .panelExposed,
                recoveryGeneration: 7,
                presentationGeneration: 11
            )
        )
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(orderFrontCount, 0)

        snapshot = Self.panelRecoverySnapshot(
            panelPresented: true,
            userVisible: false
        )
        scheduler.fireConditionReadback()
        XCTAssertEqual(orderFrontCount, 0)
        XCTAssertEqual(scheduler.pendingConditionReadbackCount, 1)

        snapshot = Self.panelRecoverySnapshot(
            panelPresented: false,
            userVisible: false
        )
        scheduler.fireConditionReadback()
        XCTAssertEqual(orderFrontCount, 1)
        XCTAssertFalse(
            owner.observe(
                source: .panelExposed,
                recoveryGeneration: 6,
                presentationGeneration: 11
            )
        )

        snapshot = Self.panelRecoverySnapshot(
            panelPresented: true,
            userVisible: true
        )
        XCTAssertTrue(
            owner.observe(
                source: .panelExposed,
                recoveryGeneration: 7,
                presentationGeneration: 11
            )
        )
        XCTAssertEqual(
            completions.map(\.source),
            [.panelExposed]
        )
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(scheduler.pendingWatchdogCount, 0)
    }

    @MainActor
    func testPanelVisibilityRecoverySlowSchedulerChangesOnlyCompletionTime() {
        let scheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let owner = PanelVisibilityRecoveryObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.panelRecoverySnapshot(
            panelPresented: false,
            userVisible: false
        )
        var attempts: [Int] = []
        var completions: [PanelVisibilityRecoveryEvidence] = []
        var failureCount = 0

        XCTAssertTrue(
            owner.start(
                trigger: "slow",
                recoveryGeneration: 13,
                presentationGeneration: 17,
                mode: .hardReorder,
                maximumAttemptCount: 2,
                conditionReadbackInterval: 0.01,
                watchdogInterval: 1.0,
                readback: { snapshot },
                actions: .init(
                    performSoftReorder: { _, _ in },
                    performOrderOut: { _, _ in },
                    performOrderFront: { _, _ in }
                ),
                callbacks: .init(
                    onAttempt: { attempt, _ in
                        attempts.append(attempt)
                    },
                    onVisible: { completions.append($0) },
                    onWatchdog: { _ in failureCount += 1 }
                )
            )
        )
        XCTAssertEqual(attempts, [1])
        XCTAssertEqual(scheduler.pendingConditionReadbackCount, 1)

        scheduler.fireConditionReadback()
        XCTAssertEqual(attempts, [1, 2])
        snapshot = Self.panelRecoverySnapshot(
            panelPresented: true,
            userVisible: true
        )
        scheduler.fireWatchdog()

        XCTAssertEqual(
            completions.map(\.source),
            [.watchdogReadback]
        )
        XCTAssertEqual(failureCount, 0)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testPanelVisibilityRecoveryWatchdogReportsLastAndFinalEvidence() {
        let scheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let owner = PanelVisibilityRecoveryObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.panelRecoverySnapshot(
            panelPresented: false,
            userVisible: false
        )
        var failures: [PanelVisibilityRecoveryWatchdogFailure] = []

        _ = owner.start(
            trigger: "watchdog",
            recoveryGeneration: 19,
            presentationGeneration: 23,
            mode: .hardReorder,
            maximumAttemptCount: 1,
            conditionReadbackInterval: 0.01,
            watchdogInterval: 1.0,
            readback: { snapshot },
            actions: .init(
                performSoftReorder: { _, _ in },
                performOrderOut: { _, _ in },
                performOrderFront: { _, _ in }
            ),
            callbacks: .init(
                onAttempt: { _, _ in },
                onVisible: { _ in
                    XCTFail("Hidden panel must reach the watchdog.")
                },
                onWatchdog: { failures.append($0) }
            )
        )
        snapshot = Self.panelRecoverySnapshot(
            panelPresented: true,
            userVisible: false,
            panelKey: true
        )
        _ = owner.observe(
            source: .panelExposed,
            recoveryGeneration: 19,
            presentationGeneration: 23
        )
        scheduler.fireWatchdog()

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].completedAttemptCount, 1)
        XCTAssertEqual(
            failures[0].lastEvidence.source,
            .panelExposed
        )
        XCTAssertTrue(failures[0].lastEvidence.snapshot.panelKey)
        XCTAssertEqual(
            failures[0].finalEvidence.source,
            .watchdogReadback
        )
        XCTAssertTrue(
            failures[0].logFields.contains("condition=userVisible")
        )
        XCTAssertEqual(owner.lastFailure, failures[0])
    }

    @MainActor
    func testPanelVisibilityRecoveryCancellationAndReplacementDiscardWork() {
        let scheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let owner = PanelVisibilityRecoveryObservationOwner(
            scheduler: scheduler
        )
        var callbackCount = 0

        for generation in 1...2_000 {
            _ = owner.start(
                trigger: "replace_\(generation)",
                recoveryGeneration: generation,
                presentationGeneration: generation,
                mode: .hardReorder,
                maximumAttemptCount: 1,
                conditionReadbackInterval: 0.01,
                watchdogInterval: 1.0,
                readback: {
                    Self.panelRecoverySnapshot(
                        panelPresented: false,
                        userVisible: false
                    )
                },
                actions: .init(
                    performSoftReorder: { _, _ in },
                    performOrderOut: { _, _ in },
                    performOrderFront: { _, _ in }
                ),
                callbacks: .init(
                    onAttempt: { _, _ in },
                    onVisible: { _ in callbackCount += 1 },
                    onWatchdog: { _ in callbackCount += 1 }
                )
            )
        }

        XCTAssertTrue(owner.isObserving)
        XCTAssertEqual(scheduler.pendingConditionReadbackCount, 1)
        XCTAssertEqual(scheduler.pendingWatchdogCount, 1)
        owner.cancel()
        scheduler.fireAll()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(scheduler.pendingConditionReadbackCount, 0)
        XCTAssertEqual(scheduler.pendingWatchdogCount, 0)
    }

    private static func panelRecoverySnapshot(
        panelPresented: Bool,
        userVisible: Bool,
        panelKey: Bool = false
    ) -> PanelVisibilitySnapshot {
        PanelVisibilitySnapshot(
            panelPresented: panelPresented,
            userVisible: userVisible,
            occlusionVisible: userVisible,
            panelKey: panelKey,
            appActive: false,
            searchActive: false,
            inputFocused: false,
            firstResponder: "nil"
        )
    }
}
