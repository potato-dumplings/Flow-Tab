import CoreGraphics
import Foundation
import XCTest

enum FlowTabUITestHomeWindowRecencyWindowActivationPolicy {
    static let exactWindowActivationWatchdog: TimeInterval = 10
}

extension FlowTabUITests {
    func testHomeWindowRecencyWindowActivationPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestHomeWindowRecencyWindowActivationPolicy
                .exactWindowActivationWatchdog,
            10
        )
        XCTAssertTrue(
            FlowTabUITestHomeWindowRecencyWindowActivationPolicy
                .exactWindowActivationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeWindowRecencyWindowActivationPolicy
                .exactWindowActivationWatchdog,
            0
        )
    }

    func activateHomeWindowRecencyTargetWindow(
        row: XCUIElement,
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> Bool {
        triggerAndWaitForFrontmostWorkflowWindow(
            windowNumber: windowNumber,
            title: title,
            app: workflowApp,
            timeout:
                FlowTabUITestHomeWindowRecencyWindowActivationPolicy
                    .exactWindowActivationWatchdog,
            trigger: {
                row.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ).tap()
            }
        )
    }
}
