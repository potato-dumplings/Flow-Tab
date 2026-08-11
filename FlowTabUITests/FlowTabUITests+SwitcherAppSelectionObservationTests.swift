import Foundation
import XCTest

private enum FlowTabUITestSwitcherAppSelectionTestPolicy {
    static let immediateResolutionReadback: TimeInterval = 0
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testSwitcherAppSelectionRequiresAppliedEventAfterMatchingBaseline() {
        var order: [String] = []
        var eventReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var snapshot = switcherAppSelectionTestSnapshot()
        let owner = switcherAppSelectionTestOwner(
            observationRegistration: { callback in
                order.append("register")
                eventReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                order.append("readback")
                return snapshot
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(order, ["register", "readback"])
        XCTAssertNil(owner.resolvedEvidence)
        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix: switcherAppSelectionAppliedLogSuffix
        )
        eventReadback?(.notificationReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherAppSelectionTestPolicy
                        .immediateResolutionReadback
            )?.value.diagnostics.values["selected"],
            switcherAppSelectionTestBundleIdentifier
        )
    }

    func testSwitcherAppSelectionRequiresExactAppliedSuffixAndProjection() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = switcherAppSelectionTestSnapshot()
        let owner = switcherAppSelectionTestOwner(
            observationRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix:
                "completed switcher command notification "
                + "command=selectApp"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix:
                "select app command missed appID="
                + switcherAppSelectionTestBundleIdentifier
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix:
                switcherAppSelectionAppliedLogSuffix
                + ".stale"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix:
                "select app command applied appID="
                + "com.example.other"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix:
                switcherAppSelectionAppliedLogSuffix,
            selectedBundleIdentifier:
                "com.example.other"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix: switcherAppSelectionAppliedLogSuffix
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNotNil(owner.resolvedEvidence)
    }

    func testSwitcherAppSelectionSlowSchedulingOnlyDelaysResolution() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = switcherAppSelectionTestSnapshot()
        let owner = switcherAppSelectionTestOwner(
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

        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix: switcherAppSelectionAppliedLogSuffix
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testSwitcherAppSelectionCancellationRejectsLateEvent() {
        var eventReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var snapshot = switcherAppSelectionTestSnapshot()
        let owner = switcherAppSelectionTestOwner(
            observationRegistration: { callback in
                eventReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()
        owner.cancel()

        snapshot = switcherAppSelectionTestSnapshot(
            logSuffix: switcherAppSelectionAppliedLogSuffix
        )
        eventReadback?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherAppSelectionRejectsStaleEventsUnderPressure() {
        let iterationCount =
            FlowTabUITestSwitcherAppSelectionTestPolicy
                .pressureIterations
        for _ in 0..<iterationCount {
            var eventReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = switcherAppSelectionTestSnapshot()
            let owner = switcherAppSelectionTestOwner(
                observationRegistration: { callback in
                    eventReadbacks.append(callback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )

            owner.start()
            let staleReadback = eventReadbacks[0]
            owner.cancel()
            owner.start()

            snapshot = switcherAppSelectionTestSnapshot(
                logSuffix: switcherAppSelectionAppliedLogSuffix
            )
            staleReadback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            eventReadbacks[1](.notificationReadback)
            eventReadbacks[1](.notificationReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testSwitcherAppSelectionWatchdogReportsFinalEvidence() {
        let snapshot = switcherAppSelectionTestSnapshot()
        let owner = switcherAppSelectionTestOwner(
            observationRegistration: { _ in nil },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherAppSelectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "appliedMarkerPresent=false"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedAppliedSuffix="
                    + switcherAppSelectionAppliedLogSuffix
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("selected=")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("waitResult=")
        )
    }
}

private extension FlowTabUITests {
    var switcherAppSelectionTestBundleIdentifier: String {
        "com.example.browser"
    }

    var switcherAppSelectionAppliedLogSuffix: String {
        "select app command applied appID="
            + switcherAppSelectionTestBundleIdentifier
    }

    func switcherAppSelectionTestOwner(
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestSwitcherAppSelectionSnapshot
    ) -> FlowTabUITestSwitcherAppSelectionObservationOwner {
        FlowTabUITestSwitcherAppSelectionObservationOwner(
            bundleIdentifier:
                switcherAppSelectionTestBundleIdentifier,
            observationRegistration:
                observationRegistration,
            readback: readback
        )
    }

    func switcherAppSelectionTestSnapshot(
        logSuffix: String? = nil,
        selectedBundleIdentifier: String? = nil
    ) -> FlowTabUITestSwitcherAppSelectionSnapshot {
        let selectedBundleIdentifier =
            selectedBundleIdentifier
                ?? switcherAppSelectionTestBundleIdentifier
        let logContents = logSuffix.map {
            "[00:00:00.000] [INFO] [UITest] \($0)\n"
        } ?? ""
        return FlowTabUITestSwitcherAppSelectionSnapshot(
            runtimeLog:
                FlowTabUITestRuntimeLogSnapshot(
                    baselineFileEventGeneration: 10,
                    fileEventGeneration:
                        logSuffix == nil ? 10 : 11,
                    contents: logContents
                ),
            diagnostics:
                FlowTabUITestSwitcherDiagnosticsSnapshot(
                    identifier: "flowtab.testing.switcher.summary",
                    exists: true,
                    rawValue:
                        "selected="
                            + selectedBundleIdentifier,
                    values: [
                        "selected": selectedBundleIdentifier
                    ]
                )
        )
    }
}
