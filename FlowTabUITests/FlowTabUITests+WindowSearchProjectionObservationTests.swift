import Foundation
import XCTest

private enum FlowTabUITestWindowSearchProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testWindowSearchProjectionRequiresPostKeyboardReadback() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let snapshot = windowSearchProjectionTestSnapshot()
        let owner =
            FlowTabUITestWindowSearchProjectionObservationOwner(
                requirement: windowSearchProjectionTestRequirement,
                acceptsEvidence: {
                    acceptsEvidence
                },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testWindowSearchProjectionRequiresOneAtomicCleanSnapshot() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = windowSearchProjectionTestSnapshot(
            resultState: "building"
        )
        let owner =
            FlowTabUITestWindowSearchProjectionObservationOwner(
                requirement: windowSearchProjectionTestRequirement,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchProjectionTestSnapshot(
            titles: ["Primary", "Fullscreen", "Noisy"]
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.results.count,
            2
        )
    }

    func testWindowSearchProjectionAllowsNoisySiblingRows() {
        let requirement =
            FlowTabUITestWindowSearchProjectionRequirement(
                appID: "com.example.browser",
                expectedTitles: ["Primary", "Fullscreen"],
                expectedCount: nil
            )
        let owner =
            FlowTabUITestWindowSearchProjectionObservationOwner(
                requirement: requirement,
                observationRegistration: nil,
                readback: {
                    self.windowSearchProjectionTestSnapshot(
                        titles: [
                            "Primary",
                            "Fullscreen",
                            "Noisy"
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.results.count,
            3
        )
    }

    func testWindowSearchProjectionSlowSchedulingOnlyDelaysResolution() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = windowSearchProjectionTestSnapshot(
            readiness: "building"
        )
        let owner =
            FlowTabUITestWindowSearchProjectionObservationOwner(
                requirement: windowSearchProjectionTestRequirement,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = windowSearchProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testWindowSearchProjectionCancellationRejectsLateReadback() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var snapshot = windowSearchProjectionTestSnapshot(
            resultState: "building"
        )
        let owner =
            FlowTabUITestWindowSearchProjectionObservationOwner(
                requirement: windowSearchProjectionTestRequirement,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        owner.cancel()

        snapshot = windowSearchProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testWindowSearchProjectionRejectsStaleReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestWindowSearchProjectionTestPolicy
            .pressureIterations
        {
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = windowSearchProjectionTestSnapshot(
                resultState: "building"
            )
            let owner =
                FlowTabUITestWindowSearchProjectionObservationOwner(
                    requirement:
                        windowSearchProjectionTestRequirement,
                    observationRegistration: { callback in
                        readbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )

            owner.start()
            let staleReadback = readbacks[0]
            owner.cancel()
            owner.start()
            snapshot = windowSearchProjectionTestSnapshot()

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            readbacks[1](.scheduledReadback)
            readbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testWindowSearchProjectionWatchdogReportsFinalSnapshot() {
        let owner =
            FlowTabUITestWindowSearchProjectionObservationOwner(
                requirement: windowSearchProjectionTestRequirement,
                observationRegistration: nil,
                readback: {
                    self.windowSearchProjectionTestSnapshot(
                        resultState: "building"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWindowSearchProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "searchIndexResultState=building"
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
    var windowSearchProjectionTestRequirement:
        FlowTabUITestWindowSearchProjectionRequirement
    {
        FlowTabUITestWindowSearchProjectionRequirement(
            appID: "com.example.browser",
            expectedTitles: ["Primary", "Fullscreen"],
            expectedCount: 2
        )
    }

    func windowSearchProjectionTestSnapshot(
        titles: [String] = ["Primary", "Fullscreen"],
        readiness: String = "committedGenerationValidated",
        resultState: String = "committedGenerationResult"
    ) -> FlowTabUITestWindowSearchProjectionSnapshot {
        let results = titles.enumerated().map { index, title in
            SwitcherSearchWindowResultObservation(
                identifier: "search.window.\(index)",
                searchableText: "\(title)\nBrowser",
                resultID: "window:\(index)",
                title: title,
                appName: "Browser",
                appID: "com.example.browser",
                windowID: "cg:\(index)"
            )
        }
        return FlowTabUITestWindowSearchProjectionSnapshot(
            diagnostics:
                FlowTabUITestSwitcherDiagnosticsSnapshot(
                    identifier: "flowtab.testing.switcher.summary",
                    exists: true,
                    rawValue: "test-projection",
                    values: [
                        "searchIndexReadiness": readiness,
                        "searchIndexResultState": resultState,
                        "searchIndexDegraded": "0",
                        "searchIndexCoversCurrentGeneration": "1",
                        "searchFreshnessBarrierRequested": "0"
                    ]
                ),
            results: results
        )
    }
}
