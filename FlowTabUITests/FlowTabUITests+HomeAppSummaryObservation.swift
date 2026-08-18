import Foundation
import XCTest

enum FlowTabUITestHomePostlaunchAppSummaryPolicy {
    static let homeTabNavigationWatchdog: TimeInterval = 10
    static let appRowPublicationWatchdog: TimeInterval = 20
    static let exactWindowCountWatchdog: TimeInterval = 20
}

extension FlowTabUITests {
    func testHomePostlaunchAppSummaryWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestHomePostlaunchAppSummaryPolicy
                .homeTabNavigationWatchdog,
            10
        )
        XCTAssertEqual(
            FlowTabUITestHomePostlaunchAppSummaryPolicy
                .appRowPublicationWatchdog,
            20
        )
        XCTAssertEqual(
            FlowTabUITestHomePostlaunchAppSummaryPolicy
                .exactWindowCountWatchdog,
            20
        )
    }

    func testHomeObservesFixtureAppsLaunchedAfterFlowTab() throws {
        try runRealSpaceFixtureMultiAppWorkflow(
            validatesPermissionsBeforeFixtureLaunch: true,
            prelaunchesFlowTabBeforeFixture: true
        ) { workflow, app in
            let homeTabButtons = app.buttons.matching(
                identifier: Identifier.homeTabButton
            )
            let homeTab = homeTabButtons.firstMatch
            XCTAssertTrue(
                tapFirstHittable(
                    in: homeTabButtons,
                    timeout:
                        FlowTabUITestHomePostlaunchAppSummaryPolicy
                            .homeTabNavigationWatchdog
                ),
                "Home-tab navigation watchdog expired. "
                    + "candidateCount=\(homeTabButtons.count) "
                    + "firstExists=\(homeTab.exists) "
                    + "firstHittable=\(homeTab.isHittable)"
            )

            for workflowApp in workflow.apps {
                let homeRow = app.buttons
                    .matching(
                        identifier:
                            workflowApp.identity
                                .homeAppAccessibilityIdentifier
                    )
                    .firstMatch
                let rowWaitCompleted = homeRow.waitForExistence(
                    timeout:
                        FlowTabUITestHomePostlaunchAppSummaryPolicy
                            .appRowPublicationWatchdog
                )
                let rowExists = homeRow.exists
                guard rowExists else {
                    XCTFail(
                        "Home app-row publication watchdog expired for "
                            + "\(workflowApp.appName). identifier="
                            + "\(homeRow.identifier) waiterCompleted="
                            + "\(rowWaitCompleted) finalExists="
                            + "\(homeRow.exists) finalValue="
                            + elementStringValue(homeRow).debugDescription
                    )
                    continue
                }
                assertValue(
                    of: homeRow,
                    equals: "\(workflowApp.windowCount)w",
                    timeout:
                        FlowTabUITestHomePostlaunchAppSummaryPolicy
                            .exactWindowCountWatchdog
                )
            }
        }
    }
}
