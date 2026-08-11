import Foundation
import XCTest

private enum FlowTabUITestWindowSearchQueryProjectionTestPolicy {
    static let immediateResolutionReadback: TimeInterval = 0
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testWindowSearchQueryProjectionAcceptsImmediatePostTriggerResult() {
        var scheduledRegistrationCount = 0
        var snapshot = windowSearchQueryProjectionTestSnapshot(
            query: ""
        )
        let owner = windowSearchQueryProjectionTestOwner(
            scheduledReadbackRegistration: { _ in
                scheduledRegistrationCount += 1
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertTrue(owner.hasInitialBaseline)
        XCTAssertNil(owner.resolvedEvidence)
        snapshot = windowSearchQueryProjectionTestSnapshot()
        owner.completeTriggerAndRequestReadback()

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(scheduledRegistrationCount, 0)
        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWindowSearchQueryProjectionTestPolicy
                        .immediateResolutionReadback
            )?.resultID,
            "window:com.example.browser#42"
        )
    }

    func testWindowSearchQueryProjectionRequiresTransitionFromMatchingBaseline() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var snapshot = windowSearchQueryProjectionTestSnapshot()
        let owner = windowSearchQueryProjectionTestOwner(
            scheduledReadbackRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        owner.completeTriggerAndRequestReadback()
        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchQueryProjectionTestSnapshot(
            query: ""
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchQueryProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "projectionTransitionObserved=true"
            )
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testWindowSearchQueryProjectionRequiresAtomicCommittedIdentity() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = windowSearchQueryProjectionTestSnapshot(
            query: ""
        )
        let owner = windowSearchQueryProjectionTestOwner(
            scheduledReadbackRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }
        owner.completeTriggerAndRequestReadback()

        snapshot = windowSearchQueryProjectionTestSnapshot(
            scope: "app"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchQueryProjectionTestSnapshot(
            query: "Other"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchQueryProjectionTestSnapshot(
            title: "Other"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchQueryProjectionTestSnapshot(
            appName: "Other App"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchQueryProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)
        XCTAssertNotNil(owner.resolvedEvidence)
    }

    func testWindowSearchQueryProjectionSlowSchedulingOnlyDelaysResolution() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = windowSearchQueryProjectionTestSnapshot(
            query: ""
        )
        let owner = windowSearchQueryProjectionTestOwner(
            scheduledReadbackRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }
        owner.completeTriggerAndRequestReadback()

        snapshot = windowSearchQueryProjectionTestSnapshot(
            title: "Pending"
        )
        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = windowSearchQueryProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testWindowSearchQueryProjectionCancellationRejectsLateReadback() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var snapshot = windowSearchQueryProjectionTestSnapshot(
            query: ""
        )
        let owner = windowSearchQueryProjectionTestOwner(
            scheduledReadbackRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()
        owner.completeTriggerAndRequestReadback()
        owner.cancel()

        snapshot = windowSearchQueryProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testWindowSearchQueryProjectionRejectsStaleReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestWindowSearchQueryProjectionTestPolicy
            .pressureIterations
        {
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = windowSearchQueryProjectionTestSnapshot(
                query: ""
            )
            let owner = windowSearchQueryProjectionTestOwner(
                scheduledReadbackRegistration: { callback in
                    scheduledReadbacks.append(callback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )

            owner.start()
            owner.completeTriggerAndRequestReadback()
            let staleReadback = scheduledReadbacks[0]
            owner.cancel()

            snapshot = windowSearchQueryProjectionTestSnapshot(
                query: ""
            )
            owner.start()
            owner.completeTriggerAndRequestReadback()
            snapshot = windowSearchQueryProjectionTestSnapshot()

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            scheduledReadbacks[1](.scheduledReadback)
            scheduledReadbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testWindowSearchQueryProjectionWatchdogReportsFinalEvidence() {
        let snapshot = windowSearchQueryProjectionTestSnapshot(
            query: ""
        )
        let owner = windowSearchQueryProjectionTestOwner(
            scheduledReadbackRegistration: { _ in nil },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }
        owner.completeTriggerAndRequestReadback()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWindowSearchQueryProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "committedMatchingWindow scope=window query=Target"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "phase=postTrigger"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "baseline={scope=window query="
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult="
            )
        )
    }
}

private extension FlowTabUITests {
    func windowSearchQueryProjectionTestOwner(
        scheduledReadbackRegistration:
            @escaping FlowTabUITestConditionObservationRegistration,
        readback: @escaping () ->
            FlowTabUITestSwitcherSearchResultSnapshot
    ) -> FlowTabUITestWindowSearchQueryProjectionObservationOwner {
        FlowTabUITestWindowSearchQueryProjectionObservationOwner(
            scope: "window",
            query: "Target",
            title: "Target",
            appName: "Browser",
            scheduledReadbackRegistration:
                scheduledReadbackRegistration,
            readback: readback
        )
    }

    func windowSearchQueryProjectionTestSnapshot(
        scope: String = "window",
        query: String = "Target",
        title: String = "Target",
        appName: String = "Browser"
    ) -> FlowTabUITestSwitcherSearchResultSnapshot {
        let result = SwitcherSearchWindowResultObservation(
            identifier: "search.window.target",
            searchableText: "\(title)\n\(appName)",
            resultID: "window:com.example.browser#42",
            title: title,
            appName: appName,
            appID: "com.example.browser",
            windowID: "cg:42"
        )
        return FlowTabUITestSwitcherSearchResultSnapshot(
            results: [result],
            resultsScope: scope,
            resultsQuery: query
        )
    }
}
