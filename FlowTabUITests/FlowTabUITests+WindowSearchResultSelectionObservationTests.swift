import Foundation
import XCTest

private enum FlowTabUITestWindowSearchResultSelectionTestPolicy {
    static let immediateResolutionReadback: TimeInterval = 0
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testWindowSearchResultSelectionRequiresAppliedEventAfterMatchingBaseline() {
        var order: [String] = []
        var eventReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var snapshot = windowSearchResultSelectionTestSnapshot()
        let owner = windowSearchResultSelectionTestOwner(
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
        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                windowSearchResultSelectionAppliedLogSuffix
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
                    FlowTabUITestWindowSearchResultSelectionTestPolicy
                        .immediateResolutionReadback
            )?.value.diagnostics.values[
                "searchSelectedResult"
            ]?.removingPercentEncoding,
            windowSearchResultSelectionTestResultID
        )
    }

    func testWindowSearchResultSelectionRequiresExactAppliedSuffixAndProjection() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = windowSearchResultSelectionTestSnapshot()
        let owner = windowSearchResultSelectionTestOwner(
            observationRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                "completed switcher command notification "
                + "command=selectSearchResult"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                "select search result command missed resultID="
                + windowSearchResultSelectionTestResultID
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                windowSearchResultSelectionAppliedLogSuffix
                + ".stale"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                "select search result command applied resultID="
                + "window:com.example.browser#43"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                windowSearchResultSelectionAppliedLogSuffix,
            selectedResultID:
                "window:com.example.browser#43"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                windowSearchResultSelectionAppliedLogSuffix
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNotNil(owner.resolvedEvidence)
    }

    func testWindowSearchResultSelectionSlowSchedulingOnlyDelaysResolution() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = windowSearchResultSelectionTestSnapshot()
        let owner = windowSearchResultSelectionTestOwner(
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

        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                windowSearchResultSelectionAppliedLogSuffix
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testWindowSearchResultSelectionCancellationRejectsLateEvent() {
        var eventReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var snapshot = windowSearchResultSelectionTestSnapshot()
        let owner = windowSearchResultSelectionTestOwner(
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

        snapshot = windowSearchResultSelectionTestSnapshot(
            logSuffix:
                windowSearchResultSelectionAppliedLogSuffix
        )
        eventReadback?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testWindowSearchResultSelectionRejectsStaleEventsUnderPressure() {
        let iterationCount =
            FlowTabUITestWindowSearchResultSelectionTestPolicy
                .pressureIterations
        for _ in 0..<iterationCount {
            var eventReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = windowSearchResultSelectionTestSnapshot()
            let owner = windowSearchResultSelectionTestOwner(
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

            snapshot = windowSearchResultSelectionTestSnapshot(
                logSuffix:
                    windowSearchResultSelectionAppliedLogSuffix
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

    func testWindowSearchResultSelectionWatchdogReportsFinalEvidence() {
        let snapshot = windowSearchResultSelectionTestSnapshot()
        let owner = windowSearchResultSelectionTestOwner(
            observationRegistration: { _ in nil },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWindowSearchResultSelectionTestPolicy
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
                    + windowSearchResultSelectionAppliedLogSuffix
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "searchSelectedResult="
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
    var windowSearchResultSelectionTestResultID: String {
        "window:com.example.browser#42"
    }

    var windowSearchResultSelectionAppliedLogSuffix: String {
        "select search result command applied resultID="
            + windowSearchResultSelectionTestResultID
    }

    func windowSearchResultSelectionTestOwner(
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestWindowSearchResultSelectionSnapshot
    ) -> FlowTabUITestWindowSearchResultSelectionObservationOwner {
        FlowTabUITestWindowSearchResultSelectionObservationOwner(
            resultID: windowSearchResultSelectionTestResultID,
            observationRegistration:
                observationRegistration,
            readback: readback
        )
    }

    func windowSearchResultSelectionTestSnapshot(
        logSuffix: String? = nil,
        selectedResultID: String? = nil
    ) -> FlowTabUITestWindowSearchResultSelectionSnapshot {
        let selectedResultID =
            selectedResultID
                ?? windowSearchResultSelectionTestResultID
        let encodedResultID =
            selectedResultID.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics
            ) ?? selectedResultID
        let logContents = logSuffix.map {
            "[00:00:00.000] [INFO] [UITest] \($0)\n"
        } ?? ""
        return FlowTabUITestWindowSearchResultSelectionSnapshot(
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
                        "searchSelectedResult="
                            + encodedResultID,
                    values: [
                        "searchSelectedResult":
                            encodedResultID
                    ]
                )
        )
    }
}
