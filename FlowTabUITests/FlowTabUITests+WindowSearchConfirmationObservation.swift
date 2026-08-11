import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
    func confirmWindowSearchSelectionAndWaitForActivation(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        activationWatchdog: TimeInterval,
        traceLabel: String
    ) {
        XCTAssertTrue(
            triggerAndWaitForFrontmostWorkflowWindow(
                windowNumber: windowNumber,
                title: title,
                app: workflowApp,
                timeout: activationWatchdog
            ) {
                postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                    .searchConfirm,
                    traceLabel: traceLabel
                )
            },
            "Window Search \(traceLabel) must activate the exact selected workflow window."
        )
    }
}
