import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
    func confirmOptionTabSelectionAndWaitForEvidence(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        diagnosticsSummary: XCUIElement,
        activationWatchdog: TimeInterval,
        dismissalWatchdog: TimeInterval,
        traceLabel: String
    ) {
        let dismissalOwner =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: diagnosticsSummary.identifier,
                readback: { diagnosticsSummary.exists }
            )
        dismissalOwner.start()
        defer { dismissalOwner.cancel() }

        XCTAssertTrue(
            triggerAndWaitForFrontmostWorkflowWindow(
                windowNumber: windowNumber,
                title: title,
                app: workflowApp,
                timeout: activationWatchdog
            ) {
                postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                    .confirm,
                    traceLabel: traceLabel
                )
            }
        )
        dismissalOwner.markTriggerCompleted()

        guard
            let dismissalEvidence = dismissalOwner.waitForResolution(
                timeout: dismissalWatchdog
            )
        else {
            XCTFail(
                "Option+Tab \(traceLabel) switcher dismissal watchdog expired. "
                    + dismissalOwner.diagnosticSummary
            )
            return
        }
        XCTAssertFalse(
            dismissalEvidence.value.exists,
            "Option+Tab \(traceLabel) must dismiss the exact switcher diagnostics element."
        )
    }
}
