import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testTerminateProtectionPreparesBaselineBeforeRequestAndResolvesFromReadback() {
        let scheduler =
            ManualTerminateInterruptionProtectionScheduler()
        let owner = TerminateInterruptionProtectionObservationOwner(
            scheduler: scheduler
        )
        let target = Self.terminateTarget()
        var operationOrder: [String] = []
        var snapshot = Self.terminateSnapshot(
            generation: 7,
            projectionState: .exactInstancePresent,
            processState: .running,
            pendingRequestMatches: true
        )
        let generation = owner.prepareRequest(
            trigger: "terminate",
            presentationGeneration: 3,
            baseline: Self.terminateBaseline(generation: 7)
        )
        operationOrder.append("prepared")
        XCTAssertTrue(owner.isPrepared)

        var completions: [TerminateInterruptionProtectionEvidence] = []
        operationOrder.append("request")
        XCTAssertTrue(
            owner.commitPreparedRequest(
                observationGeneration: generation,
                target: target,
                watchdogInterval: 5.0,
                readback: {
                    operationOrder.append("readback")
                    return snapshot
                },
                onResolved: { completions.append($0) },
                onWatchdog: { _ in
                    XCTFail("Evidence should resolve before the watchdog.")
                }
            )
        )

        XCTAssertEqual(
            operationOrder,
            ["prepared", "request", "readback"]
        )
        XCTAssertTrue(owner.isObserving)
        XCTAssertEqual(scheduler.pendingCount, 1)
        snapshot = Self.terminateSnapshot(
            generation: 8,
            projectionState: .instanceAbsent,
            processState: .terminated,
            pendingRequestMatches: true
        )
        XCTAssertFalse(
            owner.observeProjectionUpdate(presentationGeneration: 3)
        )
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertTrue(
            owner.observePresentationUpdate(
                source: .panelVisibilityReadback,
                presentationGeneration: 3
            )
        )
        XCTAssertEqual(completions.map(\.source), [.panelVisibilityReadback])
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    @MainActor
    func testTerminateProtectionRejectsWrongAndOutOfOrderEvidence() {
        let owner = TerminateInterruptionProtectionObservationOwner(
            scheduler: ManualTerminateInterruptionProtectionScheduler()
        )
        let target = Self.terminateTarget()
        var snapshot = Self.terminateSnapshot(
            generation: 11,
            projectionState: .exactInstancePresent,
            processState: .running,
            pendingRequestMatches: true
        )
        var completions: [TerminateInterruptionProtectionEvidence] = []
        let generation = owner.prepareRequest(
            trigger: "terminate",
            presentationGeneration: 4,
            baseline: Self.terminateBaseline(generation: 11)
        )
        XCTAssertTrue(
            owner.commitPreparedRequest(
                observationGeneration: generation,
                target: target,
                watchdogInterval: 5.0,
                readback: { snapshot },
                onResolved: { completions.append($0) },
                onWatchdog: { _ in }
            )
        )

        snapshot = Self.terminateSnapshot(
            generation: 12,
            projectionState: .instanceAbsent,
            processState: .running,
            pendingRequestMatches: true
        )
        XCTAssertFalse(
            owner.observeWorkspaceTermination(
                appID: target.appID,
                pid: target.pid + 1,
                presentationGeneration: 4
            )
        )
        XCTAssertFalse(
            owner.observeProjectionUpdate(presentationGeneration: 3)
        )
        XCTAssertFalse(
            owner.observeProjectionUpdate(presentationGeneration: 4)
        )
        XCTAssertTrue(completions.isEmpty)

        XCTAssertFalse(
            owner.observeWorkspaceTermination(
                appID: target.appID,
                pid: target.pid,
                presentationGeneration: 4
            )
        )
        XCTAssertTrue(
            owner.observePresentationUpdate(
                source: .panelVisibilityReadback,
                presentationGeneration: 4
            )
        )
        XCTAssertEqual(completions.count, 1)
        XCTAssertTrue(completions[0].matchingTerminationObserved)
        XCTAssertFalse(
            owner.observeWorkspaceTermination(
                appID: target.appID,
                pid: target.pid,
                presentationGeneration: 4
            )
        )
    }

    @MainActor
    func testTerminateProtectionSlowWatchdogSchedulingChangesOnlyCompletionTime() {
        let scheduler =
            ManualTerminateInterruptionProtectionScheduler()
        let owner = TerminateInterruptionProtectionObservationOwner(
            scheduler: scheduler
        )
        let target = Self.terminateTarget()
        var snapshot = Self.terminateSnapshot(
            generation: 21,
            projectionState: .exactInstancePresent,
            processState: .running,
            pendingRequestMatches: true
        )
        var completions: [TerminateInterruptionProtectionEvidence] = []
        let generation = owner.prepareRequest(
            trigger: "slow",
            presentationGeneration: 5,
            baseline: Self.terminateBaseline(generation: 21)
        )
        XCTAssertTrue(
            owner.commitPreparedRequest(
                observationGeneration: generation,
                target: target,
                watchdogInterval: 5.0,
                readback: { snapshot },
                onResolved: { completions.append($0) },
                onWatchdog: { _ in
                    XCTFail("The final evidence should resolve.")
                }
            )
        )

        snapshot = Self.terminateSnapshot(
            generation: 22,
            projectionState: .instanceReplaced,
            processState: .terminated,
            pendingRequestMatches: false
        )
        scheduler.fireNextAvailable()

        XCTAssertTrue(completions.isEmpty)
        XCTAssertTrue(owner.isObserving)
        XCTAssertTrue(
            owner.observePresentationUpdate(
                source: .panelVisibilityReadback,
                presentationGeneration: 5
            )
        )
        XCTAssertEqual(completions.map(\.source), [.panelVisibilityReadback])
        XCTAssertEqual(completions.first?.snapshot, snapshot)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testTerminateProtectionWatchdogReportsLastAndFinalEvidence() {
        let scheduler =
            ManualTerminateInterruptionProtectionScheduler()
        let owner = TerminateInterruptionProtectionObservationOwner(
            scheduler: scheduler
        )
        let target = Self.terminateTarget()
        var snapshot = Self.terminateSnapshot(
            generation: 31,
            projectionState: .exactInstancePresent,
            processState: .running,
            pendingRequestMatches: true
        )
        var failures: [TerminateInterruptionProtectionWatchdogFailure] = []
        let generation = owner.prepareRequest(
            trigger: "watchdog",
            presentationGeneration: 6,
            baseline: Self.terminateBaseline(generation: 31)
        )
        XCTAssertTrue(
            owner.commitPreparedRequest(
                observationGeneration: generation,
                target: target,
                watchdogInterval: 5.0,
                readback: { snapshot },
                onResolved: { _ in
                    XCTFail("An unchanged target must not resolve.")
                },
                onWatchdog: { failures.append($0) }
            )
        )
        _ = owner.observeProjectionUpdate(presentationGeneration: 6)
        snapshot = Self.terminateSnapshot(
            generation: 32,
            projectionState: .exactInstancePresent,
            processState: .terminated,
            pendingRequestMatches: true
        )

        scheduler.fireNextAvailable()

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(
            failures[0].lastEvidence.source,
            .projectionUpdateReadback
        )
        XCTAssertEqual(failures[0].finalEvidence.snapshot, snapshot)
        XCTAssertEqual(owner.lastFailure, failures[0])
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testTerminateProtectionWaitsForPresentationTransitionOrConsumesItsInterruption() {
        let owner = TerminateInterruptionProtectionObservationOwner(
            scheduler: ManualTerminateInterruptionProtectionScheduler()
        )
        let target = Self.terminateTarget()
        var snapshot = Self.terminateSnapshot(
            generation: 51,
            projectionState: .exactInstancePresent,
            processState: .running,
            pendingRequestMatches: true
        )
        var completions: [TerminateInterruptionProtectionEvidence] = []
        let generation = owner.prepareRequest(
            trigger: "presentation-transition",
            presentationGeneration: 7,
            baseline: Self.terminateBaseline(generation: 51)
        )
        XCTAssertTrue(
            owner.commitPreparedRequest(
                observationGeneration: generation,
                target: target,
                watchdogInterval: 5.0,
                readback: { snapshot },
                onResolved: { completions.append($0) },
                onWatchdog: { _ in
                    XCTFail("The protected interruption should resolve.")
                }
            )
        )

        snapshot = Self.terminateSnapshot(
            generation: 52,
            projectionState: .instanceAbsent,
            processState: .terminated,
            pendingRequestMatches: false,
            activeSpaceTransitionPending: true,
            panelKey: false,
            appActive: false
        )
        XCTAssertFalse(
            owner.observeProjectionUpdate(presentationGeneration: 7)
        )
        XCTAssertEqual(
            (owner.lastEvidence?.snapshot.projectionState),
            .instanceAbsent
        )

        snapshot = Self.terminateSnapshot(
            generation: 52,
            projectionState: .instanceAbsent,
            processState: .terminated,
            pendingRequestMatches: false,
            panelKey: false,
            appActive: false
        )
        XCTAssertFalse(
            owner.observePresentationUpdate(
                source: .activeSpaceTransitionReadback,
                presentationGeneration: 7
            )
        )
        XCTAssertFalse(
            owner.observeProtectedSystemInterruption(
                presentationGeneration: 7
            )
        )
        XCTAssertFalse(
            owner.observeProtectedSystemInterruption(
                presentationGeneration: 7
            )
        )

        snapshot = Self.terminateSnapshot(
            generation: 52,
            projectionState: .instanceAbsent,
            processState: .terminated,
            pendingRequestMatches: false
        )
        XCTAssertTrue(
            owner.observePresentationUpdate(
                source: .panelVisibilityReadback,
                presentationGeneration: 7
            )
        )

        XCTAssertEqual(completions.map(\.source), [.panelVisibilityReadback])
        XCTAssertEqual(
            completions.first?.protectedSystemInterruptionObserved,
            true
        )
        XCTAssertFalse(owner.isObserving)
    }

}
