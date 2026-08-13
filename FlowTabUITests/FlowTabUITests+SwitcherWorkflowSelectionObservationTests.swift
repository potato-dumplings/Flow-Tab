import Foundation
import XCTest

private enum FlowTabUITestSwitcherSelectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherPreviewOpenWindowMutationModePolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .openWindowMutationModeWatchdog,
            5
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .openWindowMutationModeWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .openWindowMutationModeWatchdog,
            0
        )
    }

    func testSwitcherPreviewSelectedWindowMutationModePolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .selectedWindowMutationModeWatchdog,
            5
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .selectedWindowMutationModeWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .selectedWindowMutationModeWatchdog,
            0
        )
    }

    func testSwitcherPreviewTransitionPolicyPreservesCompatibleBounds() {
        XCTAssertEqual(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .entryProjectionWatchdog(
                    for: .exactTitles(["Primary"])
                ),
            11
        )
        XCTAssertEqual(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .entryProjectionWatchdog(
                    for:
                        .requiredRealWindows(
                            standardTitles: ["Primary"],
                            fullscreenTitles: ["Fullscreen"]
                        )
                ),
            15
        )
        XCTAssertEqual(
            FlowTabUITestSwitcherPreviewTransitionPolicy
                .exitWatchdog,
            3
        )
    }

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

    func testSwitcherWindowCycleEntryResolvesFromExactTriggerReadback() {
        let bundleIdentifier = "com.example.notes"
        let baseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: bundleIdentifier,
                mode: "appCycle"
            )
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition:
                    .enterWindowCycle(from: baseline),
                previewExpectation:
                    .exactTitles(["Primary", "Secondary"]),
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
                        selected: bundleIdentifier,
                        mode:
                            "windowCycle("
                            + bundleIdentifier
                            + ")",
                        preview:
                            bundleIdentifier
                            + "::Primary|Secondary"
                    )
                }
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
        XCTAssertEqual(
            owner.resolvedEvidence?.value.values,
            [
                "selected": bundleIdentifier,
                "mode":
                    "windowCycle("
                    + bundleIdentifier
                    + ")",
                "preview":
                    bundleIdentifier
                    + "::Primary|Secondary",
            ]
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherWindowCycleEntryRequiresAtomicPreviewProjection() {
        let bundleIdentifier = "com.example.notes"
        let baseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: bundleIdentifier,
                mode: "appCycle"
            )
        var triggerCompleted = false
        var snapshot = switcherSelectionTestSnapshot(
            selected: bundleIdentifier,
            mode: "appCycle",
            preview: "inactive"
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition:
                    .enterWindowCycle(from: baseline),
                previewExpectation:
                    .exactTitles(["Primary", "Secondary"]),
                acceptsEvidence: {
                    triggerCompleted
                },
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }
        triggerCompleted = true

        snapshot = switcherSelectionTestSnapshot(
            selected: bundleIdentifier,
            mode: "windowCycle(\(bundleIdentifier))",
            preview: bundleIdentifier + "::Primary"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherSelectionTestSnapshot(
            selected: "com.example.other",
            mode: "windowCycle(com.example.other)",
            preview: bundleIdentifier + "::Primary|Secondary"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherSelectionTestSnapshot(
            selected: bundleIdentifier,
            mode: "windowCycle(\(bundleIdentifier))",
            preview:
                "com.example.other::Primary|Secondary"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherSelectionTestSnapshot(
            selected: bundleIdentifier,
            mode: "windowCycle(\(bundleIdentifier))",
            preview:
                bundleIdentifier
                + "::Secondary|Primary"
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(
            FlowTabUITestSwitcherPreviewProjectionSnapshot(
                diagnostics:
                    owner.resolvedEvidence?.value
                        ?? snapshot
            ).titles,
            ["Secondary", "Primary"]
        )
    }

    func testSwitcherWindowCycleEntryCancellationRejectsLateProjection() {
        let bundleIdentifier = "com.example.notes"
        let baseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: bundleIdentifier,
                mode: "appCycle"
            )
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = switcherSelectionTestSnapshot(
            selected: bundleIdentifier,
            mode: "appCycle",
            preview: "inactive"
        )
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition:
                    .enterWindowCycle(from: baseline),
                previewExpectation:
                    .exactTitles(["Primary"]),
                observationRegistration: { readback in
                    callback = readback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        owner.cancel()

        snapshot = switcherSelectionTestSnapshot(
            selected: bundleIdentifier,
            mode: "windowCycle(\(bundleIdentifier))",
            preview: bundleIdentifier + "::Primary"
        )
        callback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
    }

    func testSwitcherWindowCycleEntryScheduledLatencyOnlyDelaysResolution() {
        let bundleIdentifier = "com.example.notes"
        let baseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: bundleIdentifier,
                mode: "appCycle"
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = switcherSelectionTestSnapshot(
            selected: bundleIdentifier,
            mode: "appCycle",
            preview: "inactive"
        )
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition:
                    .enterWindowCycle(from: baseline),
                previewExpectation:
                    .exactTitles(["Primary", "Secondary"]),
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
        snapshot = switcherSelectionTestSnapshot(
            selected: bundleIdentifier,
            mode: "windowCycle(\(bundleIdentifier))",
            preview:
                bundleIdentifier
                + "::Primary|Secondary"
        )
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
            let bundleIdentifier = "com.example.notes"
            let baseline =
                FlowTabUITestSwitcherSelectionState(
                    selectedBundleIdentifier:
                        bundleIdentifier,
                    mode: "appCycle"
                )
            var scheduledReadbacks: [
                (
                    FlowTabUITestConditionObservationSource
                ) -> Void
            ] = []
            var snapshot = switcherSelectionTestSnapshot(
                selected: bundleIdentifier,
                mode: "appCycle",
                preview: "inactive"
            )
            let owner =
                FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                    transition:
                        .enterWindowCycle(
                            from: baseline
                        ),
                    previewExpectation:
                        .exactTitles(
                            ["Primary", "Secondary"]
                        ),
                    observationRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )

            owner.start()
            let staleReadback = scheduledReadbacks[0]
            owner.cancel()
            owner.start()
            snapshot = switcherSelectionTestSnapshot(
                selected: bundleIdentifier,
                mode: "windowCycle(\(bundleIdentifier))",
                preview:
                    bundleIdentifier
                    + "::Primary|Secondary"
            )

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

    func testSwitcherWindowCycleEntryWatchdogReportsFinalProjection() {
        let bundleIdentifier = "com.example.notes"
        let baseline =
            FlowTabUITestSwitcherSelectionState(
                selectedBundleIdentifier: bundleIdentifier,
                mode: "appCycle"
            )
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition:
                    .enterWindowCycle(from: baseline),
                previewExpectation:
                    .exactTitles(["Primary", "Secondary"]),
                observationRegistration: nil,
                readback: {
                    self.switcherSelectionTestSnapshot(
                        selected: bundleIdentifier,
                        mode:
                            "windowCycle("
                            + bundleIdentifier
                            + ")",
                        preview:
                            bundleIdentifier
                            + "::Primary"
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
                "enterWindowCycle"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedPreview=[exactTitles="
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "observedPreview=["
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "titles=[\"Primary\"]"
            )
        )
    }

    private func switcherSelectionTestSnapshot(
        selected: String,
        mode: String,
        preview: String? = nil
    ) -> FlowTabUITestSwitcherDiagnosticsSnapshot {
        var rawValue =
            "selected=\(selected);mode=\(mode)"
        var values = [
            "selected": selected,
            "mode": mode,
        ]
        if let preview {
            rawValue += ";preview=\(preview)"
            values["preview"] = preview
        }
        return FlowTabUITestSwitcherDiagnosticsSnapshot(
            identifier: "switcher-summary",
            exists: true,
            rawValue: rawValue,
            values: values
        )
    }
}
