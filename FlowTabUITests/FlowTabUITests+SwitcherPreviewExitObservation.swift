import Foundation
import XCTest

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
    private enum SwitcherPreviewTransitionPolicy {
        static let transitionWatchdog:
            TimeInterval = 3
    }

    func enterSwitcherPreview(
        _ workflowApp:
            SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnostics: XCUIElement
    ) -> Bool {
        enterSwitcherPreview(
            workflowApp,
            diagnostics: diagnostics,
            timeout:
                SwitcherPreviewTransitionPolicy
                    .transitionWatchdog
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
        let expectedBundleIdentifier =
            workflowApp.identity.bundleIdentifier
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
        let snapshot =
            switcherDiagnosticsSnapshot(
                diagnostics,
                keys:
                    FlowTabUITestSwitcherSelectionState
                        .diagnosticsKeys
            )
        let expectedBundleIdentifier =
            workflowApp.identity.bundleIdentifier
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
            diagnostics: diagnostics,
            timeout:
                SwitcherPreviewTransitionPolicy
                    .transitionWatchdog
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
        diagnostics: XCUIElement,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition: transition,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.switcherDiagnosticsSnapshot(
                        diagnostics,
                        keys:
                            FlowTabUITestSwitcherSelectionState
                                .diagnosticsKeys
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
