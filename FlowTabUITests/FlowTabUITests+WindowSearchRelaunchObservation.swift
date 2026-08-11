import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
    func relaunchWindowSearchAndWaitForFrontmostWorkflowWindow(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        traceLabel: String,
        relaunch: () -> XCUIElement
    ) throws -> XCUIElement {
        var searchInput: XCUIElement?
        let activationResolved =
            triggerAndWaitForFrontmostWorkflowWindow(
                windowNumber: windowNumber,
                title: title,
                app: workflowApp,
                timeout:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .windowSearchRelaunchWindowTopology
            ) {
                searchInput = relaunch()
            }
        let resolvedSearchInput = try XCTUnwrap(
            searchInput,
            "Window Search \(traceLabel) relaunch did not return its exact Search-input readiness result."
        )
        XCTAssertTrue(
            activationResolved,
            "Window Search \(traceLabel) relaunch must preserve the exact frontmost workflow window."
        )
        return resolvedSearchInput
    }
}
