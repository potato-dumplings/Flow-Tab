import Foundation
import XCTest

extension FlowTabUITestSwitcherSelectionTransition {
    static func previewExit(
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
            baseline.mode
                == "windowCycle("
                    + expectedBundleIdentifier
                    + ")"
        else {
            return nil
        }
        return .exitWindowCycle(from: baseline)
    }
}

extension FlowTabUITests {
    private enum SwitcherPreviewExitPolicy {
        static let transitionWatchdog:
            TimeInterval = 3
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

        app.typeKey(
            .upArrow,
            modifierFlags: []
        )
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard
            owner.waitForResolution(
                timeout:
                    SwitcherPreviewExitPolicy
                        .transitionWatchdog
            ) != nil
        else {
            XCTFail(
                "Switcher preview exit watchdog expired. "
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
