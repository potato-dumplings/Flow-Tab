import Foundation
import XCTest

enum FlowTabUITestSwitcherPreviewTransitionPolicy {
    static let standardFixtureEntryWatchdog:
        TimeInterval = 5
    static let exactEntryProjectionWatchdog:
        TimeInterval = 11
    static let noisyEntryProjectionWatchdog:
        TimeInterval = 15
    static let exitWatchdog: TimeInterval = 3
    static let openWindowMutationModeWatchdog: TimeInterval = 5
    static let selectedWindowMutationModeWatchdog: TimeInterval = 5

    static func entryProjectionWatchdog(
        for expectation:
            FlowTabUITestSwitcherPreviewProjectionExpectation
    ) -> TimeInterval {
        switch expectation {
        case .exactTitles, .exactTitleCount:
            return exactEntryProjectionWatchdog
        case .requiredRealWindows:
            return noisyEntryProjectionWatchdog
        }
    }
}

extension FlowTabUITestSwitcherSelectionState {
    static func exactWindowCycle(
        expectedBundleIdentifier: String,
        from snapshot:
            FlowTabUITestSwitcherDiagnosticsSnapshot
    ) -> Self? {
        guard
            let state = Self(snapshot: snapshot),
            state.selectedBundleIdentifier
                == expectedBundleIdentifier,
            state.mode
                == "windowCycle("
                    + expectedBundleIdentifier
                    + ")"
        else {
            return nil
        }
        return state
    }
}

extension FlowTabUITestSwitcherSelectionTransition {
    static func previewEntry(
        expectedBundleIdentifier: String,
        from snapshot:
            FlowTabUITestSwitcherDiagnosticsSnapshot
    ) -> Self? {
        guard
            let baseline =
                FlowTabUITestSwitcherSelectionState(
                    snapshot: snapshot
                ),
            baseline.selectedBundleIdentifier
                == expectedBundleIdentifier,
            baseline.mode == "appCycle"
        else {
            return nil
        }
        return .enterWindowCycle(from: baseline)
    }

    static func previewExit(
        expectedBundleIdentifier: String,
        from snapshot:
            FlowTabUITestSwitcherDiagnosticsSnapshot
    ) -> Self? {
        guard
            let baseline =
                FlowTabUITestSwitcherSelectionState.exactWindowCycle(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from: snapshot
                )
        else {
            return nil
        }
        return .exitWindowCycle(from: baseline)
    }
}

extension FlowTabUITests {
    func enterSwitcherWindowCycle(
        expectedBundleIdentifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let diagnostics = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        return enterSwitcherPreview(
            expectedBundleIdentifier:
                expectedBundleIdentifier,
            diagnostics: diagnostics,
            previewExpectation: nil,
            timeout: timeout
        ) {
            app.typeKey(
                .downArrow,
                modifierFlags: []
            )
        }
    }

    func enterSwitcherPreview(
        _ workflowApp:
            SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnostics: XCUIElement,
        allowsNoisyCGSiblings: Bool
    ) -> Bool {
        enterSwitcherPreview(
            workflowApp,
            in: app,
            diagnostics: diagnostics,
            previewExpectation:
                .workflowApp(
                    workflowApp,
                    allowsNoisyCGSiblings:
                        allowsNoisyCGSiblings
                )
        )
    }

    func enterSwitcherPreview(
        _ workflowApp:
            SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnostics: XCUIElement,
        previewExpectation:
            FlowTabUITestSwitcherPreviewProjectionExpectation
    ) -> Bool {
        enterSwitcherPreview(
            workflowApp,
            diagnostics: diagnostics,
            previewExpectation: previewExpectation,
            timeout:
                FlowTabUITestSwitcherPreviewTransitionPolicy
                    .entryProjectionWatchdog(
                        for: previewExpectation
                    )
        ) {
            app.typeKey(
                .downArrow,
                modifierFlags: []
            )
        }
    }

    func enterSwitcherPreview(
        _ workflowApp:
            SpaceFixtureResolvedWorkflow.App,
        diagnostics: XCUIElement,
        previewExpectation:
            FlowTabUITestSwitcherPreviewProjectionExpectation,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        enterSwitcherPreview(
            expectedBundleIdentifier:
                workflowApp.identity.bundleIdentifier,
            diagnostics: diagnostics,
            previewExpectation: previewExpectation,
            timeout: timeout,
            trigger: trigger
        )
    }

    func enterSwitcherPreview(
        expectedBundleIdentifier: String,
        diagnostics: XCUIElement,
        previewExpectation:
            FlowTabUITestSwitcherPreviewProjectionExpectation?,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        let baselineSnapshot =
            switcherDiagnosticsSnapshot(
                diagnostics,
                keys:
                    FlowTabUITestSwitcherSelectionState
                        .diagnosticsKeys
            )
        guard
            let transition =
                FlowTabUITestSwitcherSelectionTransition
                    .previewEntry(
                        expectedBundleIdentifier:
                            expectedBundleIdentifier,
                        from: baselineSnapshot
                    )
        else {
            XCTFail(
                "Switcher preview entry requires the "
                    + "exact selected application in "
                    + "appCycle. expected="
                    + expectedBundleIdentifier
                    + " "
                    + baselineSnapshot.diagnosticSummary
            )
            return false
        }

        return performSwitcherPreviewTransition(
            transition,
            expectedBundleIdentifier:
                expectedBundleIdentifier,
            operation: "entry",
            previewExpectation: previewExpectation,
            diagnostics: diagnostics,
            timeout: timeout,
            trigger: trigger
        )
    }

    func requireActiveSwitcherPreview(
        _ workflowApp:
            SpaceFixtureResolvedWorkflow.App,
        diagnostics: XCUIElement
    ) -> Bool {
        requireActiveSwitcherPreview(
            expectedBundleIdentifier:
                workflowApp.identity.bundleIdentifier,
            diagnostics: diagnostics
        )
    }

    func requireActiveSwitcherPreview(
        expectedBundleIdentifier: String,
        diagnostics: XCUIElement
    ) -> Bool {
        let snapshot =
            switcherDiagnosticsSnapshot(
                diagnostics,
                keys:
                    FlowTabUITestSwitcherSelectionState
                        .diagnosticsKeys
            )
        guard
            FlowTabUITestSwitcherSelectionState
                .exactWindowCycle(
                    expectedBundleIdentifier:
                        expectedBundleIdentifier,
                    from: snapshot
                ) != nil
        else {
            XCTFail(
                "Switcher preview readback requires the "
                    + "exact selected application in "
                    + "windowCycle. expected="
                    + expectedBundleIdentifier
                    + " "
                    + snapshot.diagnosticSummary
            )
            return false
        }
        return true
    }

    func exitSwitcherPreview(
        _ workflowApp:
            SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnostics: XCUIElement
    ) -> Bool {
        let baselineSnapshot =
            switcherDiagnosticsSnapshot(
                diagnostics,
                keys:
                    FlowTabUITestSwitcherSelectionState
                        .diagnosticsKeys
            )
        let expectedBundleIdentifier =
            workflowApp.identity.bundleIdentifier
        guard
            let transition =
                FlowTabUITestSwitcherSelectionTransition
                    .previewExit(
                        expectedBundleIdentifier:
                            expectedBundleIdentifier,
                        from: baselineSnapshot
                    )
        else {
            XCTFail(
                "Switcher preview exit requires the "
                    + "exact selected application in "
                    + "windowCycle. expected="
                    + expectedBundleIdentifier
                    + " "
                    + baselineSnapshot.diagnosticSummary
            )
            return false
        }

        return performSwitcherPreviewTransition(
            transition,
            expectedBundleIdentifier:
                expectedBundleIdentifier,
            operation: "exit",
            previewExpectation: nil,
            diagnostics: diagnostics,
            timeout:
                FlowTabUITestSwitcherPreviewTransitionPolicy
                    .exitWatchdog
        ) {
            app.typeKey(
                .upArrow,
                modifierFlags: []
            )
        }
    }

    private func performSwitcherPreviewTransition(
        _ transition:
            FlowTabUITestSwitcherSelectionTransition,
        expectedBundleIdentifier: String,
        operation: String,
        previewExpectation:
            FlowTabUITestSwitcherPreviewProjectionExpectation?,
        diagnostics: XCUIElement,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        var triggerCompleted = false
        let diagnosticsKeys =
            FlowTabUITestSwitcherSelectionState
                .diagnosticsKeys
            + (previewExpectation == nil ? [] : ["preview"])
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition: transition,
                previewExpectation:
                    previewExpectation,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.switcherDiagnosticsSnapshot(
                        diagnostics,
                        keys:
                            diagnosticsKeys
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard
            owner.waitForResolution(
                timeout: timeout
            ) != nil
        else {
            XCTFail(
                "Switcher preview \(operation) watchdog expired. "
                    + "expected="
                    + expectedBundleIdentifier
                    + " "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
