import Foundation
import XCTest

private enum FlowTabUITestSwitcherSelectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherSelectionTransitionRequiresExactAtomicState() {
        let windowBaseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: "com.example.notes",
                mode: "windowCycle(com.example.notes)"
            )
        let exitWindowCycle =
            FlowTabUITestSwitcherSelectionTransition
                .exitWindowCycle(from: windowBaseline)

        XCTAssertTrue(
            exitWindowCycle.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.notes",
                    mode: "appCycle"
                )
            )
        )
        XCTAssertFalse(
            exitWindowCycle.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.browser",
                    mode: "appCycle"
                )
            )
        )
        XCTAssertFalse(
            exitWindowCycle.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.notes",
                    mode: "windowCycle(com.example.notes)"
                )
            )
        )

        let appBaseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: "com.example.notes",
                mode: "appCycle"
            )
        let enterWindowCycle =
            FlowTabUITestSwitcherSelectionTransition
                .enterWindowCycle(from: appBaseline)

        XCTAssertTrue(
            enterWindowCycle.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.notes",
                    mode: "windowCycle(com.example.notes)"
                )
            )
        )
        XCTAssertFalse(
            enterWindowCycle.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.browser",
                    mode: "windowCycle(com.example.browser)"
                )
            )
        )
        XCTAssertFalse(
            enterWindowCycle.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.notes",
                    mode: "windowCycle(com.example.browser)"
                )
            )
        )
        XCTAssertFalse(
            enterWindowCycle.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.notes",
                    mode: "appCycle"
                )
            )
        )

        let advanceApplication =
            FlowTabUITestSwitcherSelectionTransition
                .advanceApplication(from: appBaseline)

        XCTAssertTrue(
            advanceApplication.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.browser",
                    mode: "appCycle"
                )
            )
        )
        XCTAssertTrue(
            advanceApplication.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.notes",
                    mode: "windowCycle(com.example.notes)"
                )
            )
        )
        XCTAssertFalse(
            advanceApplication.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.notes",
                    mode: "appCycle"
                )
            )
        )
        XCTAssertFalse(
            advanceApplication.isSatisfied(
                by: switcherSelectionTestSnapshot(
                    selected: "com.example.browser",
                    mode: "search"
                )
            )
        )
    }

    func testSwitcherPreviewEntryRequiresExactSelectedApplicationCycleBaseline() {
        let expectedBundleIdentifier =
            "com.example.notes"
        let exactSnapshot =
            switcherSelectionTestSnapshot(
                selected: expectedBundleIdentifier,
                mode: "appCycle"
            )
        let expectedState =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier:
                    expectedBundleIdentifier,
                mode: "appCycle"
            )

        XCTAssertEqual(
            FlowTabUITestSwitcherSelectionTransition
                .previewEntry(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from: exactSnapshot
                ),
            .enterWindowCycle(from: expectedState)
        )
        XCTAssertNil(
            FlowTabUITestSwitcherSelectionTransition
                .previewEntry(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from:
                        switcherSelectionTestSnapshot(
                            selected:
                                "com.example.browser",
                            mode: "appCycle"
                        )
                )
        )
        XCTAssertNil(
            FlowTabUITestSwitcherSelectionTransition
                .previewEntry(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from:
                        switcherSelectionTestSnapshot(
                            selected:
                                expectedBundleIdentifier,
                            mode:
                                "windowCycle("
                                + expectedBundleIdentifier
                                + ")"
                        )
                )
        )
        XCTAssertNil(
            FlowTabUITestSwitcherSelectionTransition
                .previewEntry(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from:
                        switcherSelectionTestSnapshot(
                            selected:
                                expectedBundleIdentifier,
                            mode: "search"
                        )
                )
        )
    }

    func testSwitcherPreviewExitRequiresExactSelectedWindowCycleBaseline() {
        let expectedBundleIdentifier =
            "com.example.notes"
        let exactSnapshot =
            switcherSelectionTestSnapshot(
                selected: expectedBundleIdentifier,
                mode:
                    "windowCycle("
                    + expectedBundleIdentifier
                    + ")"
            )
        let expectedState =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier:
                    expectedBundleIdentifier,
                mode:
                    "windowCycle("
                    + expectedBundleIdentifier
                    + ")"
            )

        XCTAssertEqual(
            FlowTabUITestSwitcherSelectionTransition
                .previewExit(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from: exactSnapshot
                ),
            .exitWindowCycle(from: expectedState)
        )
        XCTAssertNil(
            FlowTabUITestSwitcherSelectionTransition
                .previewExit(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from:
                        switcherSelectionTestSnapshot(
                            selected:
                                "com.example.browser",
                            mode:
                                "windowCycle("
                                + "com.example.browser"
                                + ")"
                        )
                )
        )
        XCTAssertNil(
            FlowTabUITestSwitcherSelectionTransition
                .previewExit(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from:
                        switcherSelectionTestSnapshot(
                            selected:
                                expectedBundleIdentifier,
                            mode:
                                "windowCycle("
                                + "com.example.browser"
                                + ")"
                        )
                )
        )
        XCTAssertNil(
            FlowTabUITestSwitcherSelectionTransition
                .previewExit(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from:
                        switcherSelectionTestSnapshot(
                            selected:
                                expectedBundleIdentifier,
                            mode: "appCycle"
                        )
                )
        )
    }

    func testSwitcherSelectionTransitionRequiresPostTriggerEvidence() {
        let baseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: "com.example.notes",
                mode: "appCycle"
            )
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition:
                    .advanceApplication(from: baseline),
                acceptsEvidence: {
                    acceptsEvidence
                },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.switcherSelectionTestSnapshot(
                        selected: "com.example.browser",
                        mode: "appCycle"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherSelectionTransitionScheduledLatencyOnlyDelaysResolution() {
        let baseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: "com.example.notes",
                mode: "appCycle"
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var selected = "com.example.notes"
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition:
                    .advanceApplication(from: baseline),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.switcherSelectionTestSnapshot(
                        selected: selected,
                        mode: "appCycle"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        selected = "com.example.browser"
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherSelectionTestPolicy
                        .watchdog
            )?.source,
            .scheduledReadback
        )
    }

    func testSwitcherSelectionTransitionRejectsStaleCallbacksUnderPressure() {
        for _ in 0..<FlowTabUITestSwitcherSelectionTestPolicy
            .pressureIterations
        {
            let baseline =
                FlowTabUITestSwitcherSelectionState(
                    selectedBundleIdentifier:
                        "com.example.notes",
                    mode: "appCycle"
                )
            var scheduledReadbacks: [
                (
                    FlowTabUITestConditionObservationSource
                ) -> Void
            ] = []
            var selected = "com.example.notes"
            let owner =
                FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                    transition:
                        .advanceApplication(
                            from: baseline
                        ),
                    observationRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        self.switcherSelectionTestSnapshot(
                            selected: selected,
                            mode: "appCycle"
                        )
                    }
                )

            owner.start()
            let staleReadback = scheduledReadbacks[0]
            owner.cancel()
            owner.start()
            selected = "com.example.browser"

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

    func testSwitcherSelectionTransitionWatchdogReportsFinalState() {
        let baseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: "com.example.notes",
                mode: "appCycle"
            )
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition:
                    .advanceApplication(from: baseline),
                observationRegistration: nil,
                readback: {
                    self.switcherSelectionTestSnapshot(
                        selected: "com.example.notes",
                        mode: "appCycle"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherSelectionTestPolicy
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
                "advanceApplication"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "selected=com.example.notes"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "mode=appCycle"
            )
        )
    }

    private func switcherSelectionTestSnapshot(
        selected: String,
        mode: String
    ) -> FlowTabUITestSwitcherDiagnosticsSnapshot {
        FlowTabUITestSwitcherDiagnosticsSnapshot(
            identifier: "switcher-summary",
            exists: true,
            rawValue:
                "selected=\(selected);mode=\(mode)",
            values: [
                "selected": selected,
                "mode": mode
            ]
        )
    }
}
