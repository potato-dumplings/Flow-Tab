import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
    func confirmWindowSearchSelectionAndWaitForEvidence(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        searchInput: XCUIElement,
        traceLabel: String
    ) {
        let dismissalOwner =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: searchInput.identifier,
                readback: { searchInput.exists }
            )
        dismissalOwner.start()
        defer { dismissalOwner.cancel() }

        XCTAssertTrue(
            triggerAndWaitForFrontmostWorkflowWindow(
                windowNumber: windowNumber,
                title: title,
                app: workflowApp,
                timeout:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .windowSearchConfirmedWindowActivation
            ) {
                postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                    .searchConfirm,
                    traceLabel: traceLabel
                )
            },
            "Window Search \(traceLabel) must activate the exact selected workflow window."
        )
        dismissalOwner.markTriggerCompleted()

        guard
            let dismissalEvidence = dismissalOwner.waitForResolution(
                timeout:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .windowSearchInputDismissal
            )
        else {
            XCTFail(
                "Window Search \(traceLabel) input dismissal watchdog expired. "
                    + dismissalOwner.diagnosticSummary
            )
            return
        }
        XCTAssertFalse(
            dismissalEvidence.value.exists,
            "Window Search \(traceLabel) must dismiss the exact Search input element."
        )
    }
}
