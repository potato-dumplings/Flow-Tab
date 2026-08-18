import Foundation
import XCTest

private enum FlowTabUITestSwitcherSelectedWindowTitleTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherSelectedWindowTitleAcceptsMatchingInitialTitle() {
        var order: [String] = []
        let owner =
            FlowTabUITestSwitcherSelectedWindowTitleObservationOwner(
                expectation: .exact("Primary"),
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self
                        .switcherSelectedWindowTitleTestSnapshot(
                            "Primary"
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
            order,
            ["register", "readback", "cancel"]
        )
    }

    func testSwitcherSelectedWindowTitleWaitsForAllowedTitle() {
        var selectedTitle = "Unrelated"
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherSelectedWindowTitleObservationOwner(
                expectation:
                    .oneOf(["Fullscreen A", "Fullscreen B"]),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.switcherSelectedWindowTitleTestSnapshot(
                        selectedTitle
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        selectedTitle = "Fullscreen B"
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testSwitcherSelectedWindowTitleRejectsWrongExactTitle() {
        var selectedTitle = "Secondary"
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherSelectedWindowTitleObservationOwner(
                expectation: .exact("Primary"),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.switcherSelectedWindowTitleTestSnapshot(
                        selectedTitle
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        selectedTitle = "Primary"
        scheduledReadback?(.scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testSwitcherSelectedWindowTitleRejectsStaleReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestSwitcherSelectedWindowTitleTestPolicy
            .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var selectedTitle = "Secondary"
            let owner =
                FlowTabUITestSwitcherSelectedWindowTitleObservationOwner(
                    expectation: .exact("Primary"),
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        self
                            .switcherSelectedWindowTitleTestSnapshot(
                                selectedTitle
                            )
                    }
                )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()
            selectedTitle = "Primary"

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testSwitcherSelectedWindowTitleWatchdogReportsFinalTitle() {
        let owner =
            FlowTabUITestSwitcherSelectedWindowTitleObservationOwner(
                expectation: .exact("Primary"),
                observationRegistration: nil,
                readback: {
                    self.switcherSelectedWindowTitleTestSnapshot(
                        "Secondary"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherSelectedWindowTitleTestPolicy
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
                "selectedTitle=Secondary"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "selectedWindowTitle=Secondary"
            )
        )
    }

    private func switcherSelectedWindowTitleTestSnapshot(
        _ selectedTitle: String
    ) -> FlowTabUITestSwitcherSelectedWindowTitleSnapshot {
        FlowTabUITestSwitcherSelectedWindowTitleSnapshot(
            identifier: "switcher-summary",
            exists: true,
            rawValue:
                "selectedWindowTitle=\(selectedTitle);mode=windowCycle",
            selectedTitle: selectedTitle
        )
    }
}
