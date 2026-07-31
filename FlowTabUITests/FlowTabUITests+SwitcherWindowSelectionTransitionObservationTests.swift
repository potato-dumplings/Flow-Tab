import Foundation
import XCTest

private enum
    FlowTabUITestSwitcherWindowSelectionTransitionTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testWindowSelectionTransitionRegistersBeforeInitialReadback() {
        var order: [String] = []
        let owner =
            FlowTabUITestSwitcherWindowSelectionTransitionObservationOwner(
                baselineWindowNumber: 101,
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self.windowSelectionTransitionTestSnapshot(
                        windowNumber: 101,
                        title: "Primary"
                    )
                }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        owner.cancel()
        XCTAssertEqual(
            order,
            ["register", "readback", "cancel"]
        )
    }

    func testWindowSelectionTransitionClosesSynchronousTriggerRace() {
        var triggerCompleted = false
        var snapshot = windowSelectionTransitionTestSnapshot(
            windowNumber: 101,
            title: "Primary"
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherWindowSelectionTransitionObservationOwner(
                baselineWindowNumber: 101,
                acceptsEvidence: {
                    triggerCompleted
                },
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    snapshot
                }
            )
        owner.start()
        defer { owner.cancel() }

        snapshot = windowSelectionTransitionTestSnapshot(
            windowNumber: 202,
            title: "Secondary"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedWindowNumber,
            202
        )
    }

    func testWindowSelectionTransitionRequiresCompleteNewCGIdentity() {
        var snapshot = windowSelectionTransitionTestSnapshot(
            windowNumber: 101,
            title: "Primary"
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherWindowSelectionTransitionObservationOwner(
                baselineWindowNumber: 101,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    snapshot
                }
            )
        owner.start()
        defer { owner.cancel() }

        snapshot = windowSelectionTransitionTestSnapshot(
            mode: "appCycle",
            windowNumber: 202,
            title: "Secondary"
        )
        for _ in 0..<10 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = windowSelectionTransitionTestSnapshot(
            windowID: "ax:42:202",
            windowNumber: 202,
            title: "Secondary"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSelectionTransitionTestSnapshot(
            windowID: "cg:0:202",
            windowNumber: 202,
            title: "Secondary"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSelectionTransitionTestSnapshot(
            windowID: "cg:42:202:extra",
            windowNumber: 202,
            title: "Secondary"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = windowSelectionTransitionTestSnapshot(
            windowNumber: 101,
            title: "Renamed"
        )
        for _ in 0..<10 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = windowSelectionTransitionTestSnapshot(
            windowNumber: 202,
            title: "Primary"
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedWindowID,
            "cg:42:202"
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedWindowOwnerPID,
            42
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedWindowNumber,
            202
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedWindowTitle,
            "Primary"
        )
    }

    func testWindowSelectionTransitionRejectsStaleCallbacksUnderPressure() {
        for _ in
            0..<FlowTabUITestSwitcherWindowSelectionTransitionTestPolicy
                .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = windowSelectionTransitionTestSnapshot(
                windowNumber: 101,
                title: "Primary"
            )
            let owner =
                FlowTabUITestSwitcherWindowSelectionTransitionObservationOwner(
                    baselineWindowNumber: 101,
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        snapshot
                    }
                )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()
            snapshot = windowSelectionTransitionTestSnapshot(
                windowNumber: 202,
                title: "Secondary"
            )

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

    func testWindowSelectionTransitionWatchdogReportsFinalEvidence() {
        let owner =
            FlowTabUITestSwitcherWindowSelectionTransitionObservationOwner(
                baselineWindowNumber: 101,
                observationRegistration: nil,
                readback: {
                    self.windowSelectionTransitionTestSnapshot(
                        windowNumber: 101,
                        title: "Renamed"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherWindowSelectionTransitionTestPolicy
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
                "baselineWindowNumber=101"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "selectedWindowID=cg:42:101"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "selectedWindowTitle=Renamed"
            )
        )
    }

    private func windowSelectionTransitionTestSnapshot(
        mode: String = "windowCycle(com.example.fixture)",
        windowID: String? = nil,
        windowNumber: UInt32,
        title: String
    ) -> FlowTabUITestSwitcherWindowSelectionTransitionSnapshot {
        let observedWindowID =
            windowID ?? "cg:42:\(windowNumber)"
        let rawValue =
            "mode=\(mode);selectedWindow=\(observedWindowID);"
            + "selectedWindowTitle=\(title)"
        return FlowTabUITestSwitcherWindowSelectionTransitionSnapshot(
            diagnostics:
                FlowTabUITestSwitcherDiagnosticsSnapshot(
                    identifier: "switcher-summary",
                    exists: true,
                    rawValue: rawValue,
                    values: [
                        "mode": mode,
                        "selectedWindow": observedWindowID,
                        "selectedWindowTitle": title,
                    ]
                )
        )
    }
}
