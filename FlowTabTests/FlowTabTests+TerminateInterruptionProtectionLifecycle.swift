import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testTerminateProtectionInitialReadbackLatchesCompletionBeforeSchedulingWatchdog() {
        let scheduler =
            ManualTerminateInterruptionProtectionScheduler()
        let owner = TerminateInterruptionProtectionObservationOwner(
            scheduler: scheduler
        )
        let target = Self.terminateTarget()
        let snapshot = Self.terminateSnapshot(
            generation: 62,
            projectionState: .instanceAbsent,
            processState: .terminated,
            pendingRequestMatches: false
        )
        var completions: [TerminateInterruptionProtectionEvidence] = []
        let generation = owner.prepareRequest(
            trigger: "initial-readback",
            presentationGeneration: 8,
            baseline: Self.terminateBaseline(generation: 61)
        )

        XCTAssertTrue(
            owner.commitPreparedRequest(
                observationGeneration: generation,
                target: target,
                watchdogInterval: 5.0,
                readback: { snapshot },
                onResolved: { completions.append($0) },
                onWatchdog: { _ in
                    XCTFail("Initial completion evidence must cancel the watchdog.")
                }
            )
        )

        XCTAssertTrue(owner.isObserving)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertTrue(
            owner.observePresentationUpdate(
                source: .panelVisibilityReadback,
                presentationGeneration: 8
            )
        )
        XCTAssertEqual(completions.map(\.source), [.panelVisibilityReadback])
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testTerminateProtectionReplacementAndCancellationDiscardTwoThousandWatchdogs() {
        let scheduler =
            ManualTerminateInterruptionProtectionScheduler()
        let owner = TerminateInterruptionProtectionObservationOwner(
            scheduler: scheduler
        )
        let snapshot = Self.terminateSnapshot(
            generation: 41,
            projectionState: .exactInstancePresent,
            processState: .running,
            pendingRequestMatches: true
        )
        var callbackCount = 0

        for iteration in 0..<2_000 {
            let appID = "com.example.target.\(iteration)"
            let target = TerminateInterruptionTargetIdentity(
                appID: appID,
                pid: pid_t(50_000 + iteration),
                requestGeneration: UInt64(iteration + 1)
            )
            let generation = owner.prepareRequest(
                trigger: "pressure",
                presentationGeneration: iteration,
                baseline: Self.terminateBaseline(
                    appID: appID,
                    generation: 41
                )
            )
            XCTAssertTrue(
                owner.commitPreparedRequest(
                    observationGeneration: generation,
                    target: target,
                    watchdogInterval: 5.0,
                    readback: { snapshot },
                    onResolved: { _ in callbackCount += 1 },
                    onWatchdog: { _ in callbackCount += 1 }
                )
            )
        }

        XCTAssertEqual(scheduler.pendingCount, 1)
        owner.cancel()
        XCTAssertEqual(scheduler.pendingCount, 0)
        scheduler.fireEveryRetainedAction()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertFalse(owner.isObserving)
    }
}
