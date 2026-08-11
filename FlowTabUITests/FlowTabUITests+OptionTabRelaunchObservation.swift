import Foundation
import XCTest

extension FlowTabUITests {
    func relaunchGlobalSwitcherAndWaitForFrontmostWorkflowWindow(
        _ app: XCUIApplication,
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        windowNumber: CGWindowID,
        title: String,
        traceLabel: String,
        allowsNoisyCGSiblings: Bool,
        activationWatchdog: TimeInterval
    ) throws -> XCUIElement {
        var relaunchResult: Result<XCUIElement, Error>?
        let activationResolved =
            triggerAndWaitForFrontmostWorkflowWindow(
                windowNumber: windowNumber,
                title: title,
                app: workflowApp,
                timeout: activationWatchdog
            ) {
                relaunchResult = Result {
                    try self.relaunchGlobalSwitcher(
                        app,
                        for: workflowApp,
                        traceLabel: traceLabel,
                        allowsNoisyCGSiblings:
                            allowsNoisyCGSiblings
                    )
                }
            }
        let result = try XCTUnwrap(
            relaunchResult,
            "Option+Tab relaunch did not return its exact switcher readiness result."
        )
        let diagnosticsSummary = try result.get()
        XCTAssertTrue(
            activationResolved,
            "Option+Tab relaunch must preserve the exact frontmost workflow window."
        )
        return diagnosticsSummary
    }
}
