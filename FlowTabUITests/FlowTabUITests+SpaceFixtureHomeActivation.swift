import AppKit
import XCTest

enum FlowTabUITestHomeActivationPolicy {
    static let homeTabNavigationWatchdog: TimeInterval = 10
    static let appRowPublicationWatchdog: TimeInterval = 20
    static let homeWindowProjectionWatchdog: TimeInterval = 12
    static let exactWindowActivationWatchdog: TimeInterval = 10
}

extension FlowTabUITests {
    func testHomeActivationWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestHomeActivationPolicy
                .homeTabNavigationWatchdog,
            10
        )
        XCTAssertTrue(
            FlowTabUITestHomeActivationPolicy
                .homeTabNavigationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeActivationPolicy
                .homeTabNavigationWatchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeActivationPolicy
                .appRowPublicationWatchdog,
            20
        )
        XCTAssertTrue(
            FlowTabUITestHomeActivationPolicy
                .appRowPublicationWatchdog.isFinite
        )
        XCTAssertGreaterThanOrEqual(
            FlowTabUITestHomeActivationPolicy
                .appRowPublicationWatchdog,
            FlowTabUITestHomeActivationPolicy
                .homeTabNavigationWatchdog
        )
        XCTAssertEqual(
            FlowTabUITestHomeActivationPolicy
                .homeWindowProjectionWatchdog,
            12
        )
        XCTAssertTrue(
            FlowTabUITestHomeActivationPolicy
                .homeWindowProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeActivationPolicy
                .homeWindowProjectionWatchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeActivationPolicy
                .exactWindowActivationWatchdog,
            10
        )
        XCTAssertTrue(
            FlowTabUITestHomeActivationPolicy
                .exactWindowActivationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeActivationPolicy
                .exactWindowActivationWatchdog,
            0
        )
    }

    func testHomePageClickingRealWorkflowWindowActivatesExactFixtureWindow() throws {
        try runRealSpaceFixtureMultiAppWorkflow(
            waitsForFullscreenMarkers: false
        ) { workflow, app in
            let targetApp = try XCTUnwrap(
                workflow.apps.first { $0.expectedHomeWindowTitles.count >= 2 },
                "Home activation workflow must include a fixture app with multiple standard windows."
            )
            let targetWindowTitle = try XCTUnwrap(
                targetApp.expectedHomeWindowTitles.dropFirst().first,
                "Home activation workflow must expose a non-initial target window title."
            )

            let homeTabButtons =
                app.buttons.matching(
                    identifier: Identifier.homeTabButton
                )
            let homeTab = homeTabButtons.firstMatch
            XCTAssertTrue(
                tapFirstHittable(
                    in: homeTabButtons,
                    timeout:
                        FlowTabUITestHomeActivationPolicy
                            .homeTabNavigationWatchdog
                ),
                "Home activation Home-tab watchdog expired. "
                    + "candidateCount=\(homeTabButtons.count) "
                    + "firstExists=\(homeTab.exists) "
                    + "firstHittable=\(homeTab.isHittable)"
            )
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "Home window activation scenario must start outside the target fixture app."
            )

            let homeAppRow = app.buttons
                .matching(identifier: targetApp.identity.homeAppAccessibilityIdentifier)
                .firstMatch
            let appRowPublished =
                homeAppRow.waitForExistence(
                    timeout:
                        FlowTabUITestHomeActivationPolicy
                            .appRowPublicationWatchdog
                )
            XCTAssertTrue(
                appRowPublished,
                "Home activation App-row publication watchdog expired. "
                    + "app=\(targetApp.appName) "
                    + "expectedIdentifier="
                    + "\(targetApp.identity.homeAppAccessibilityIdentifier) "
                    + "finalExists=\(homeAppRow.exists) "
                    + "finalHittable=\(homeAppRow.isHittable)"
            )
            let targetWindowRow = try XCTUnwrap(
                performAndWaitForHomeWindowRow(
                    in: app,
                    title: targetWindowTitle,
                    timeout:
                        FlowTabUITestHomeActivationPolicy
                            .homeWindowProjectionWatchdog,
                    trigger: {
                        tapElement(homeAppRow)
                    }
                ),
                "FlowTab did not expose a Home window row for \(targetApp.appName) / \(targetWindowTitle)."
            )
            let targetWindowNumber = try XCTUnwrap(
                cgWindowNumber(fromHomeWindowRowIdentifier: targetWindowRow.identifier),
                "Home window row did not expose a CG window identifier: \(targetWindowRow.identifier)"
            )
            XCTAssertTrue(
                triggerAndWaitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout:
                        FlowTabUITestHomeActivationPolicy
                            .exactWindowActivationWatchdog,
                    trigger: {
                        targetWindowRow.coordinate(
                            withNormalizedOffset:
                                CGVector(dx: 0.5, dy: 0.5)
                        ).tap()
                    }
                ),
                "Clicking the Home window row did not activate the exact \(targetWindowTitle) fixture window."
            )
        }
    }

    private func cgWindowNumber(fromHomeWindowRowIdentifier identifier: String) -> CGWindowID? {
        let prefix = "flowtab.home.window.cg-"
        guard identifier.hasPrefix(prefix) else { return nil }

        let readableComponent = identifier
            .dropFirst(prefix.count)
            .split(separator: ".id-", maxSplits: 1)
            .first
        let tokens = readableComponent?.split(separator: "-") ?? []
        guard let windowNumberToken = tokens.last,
              let windowNumber = UInt32(windowNumberToken)
        else {
            return nil
        }

        return CGWindowID(windowNumber)
    }

    func selectHomeWorkflowApp(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let watchdogBudget =
            FlowTabUITestHomeAppSelectionWatchdogBudget(
                timeout: timeout
            )
        let rowIdentifier = workflowApp.identity.homeAppAccessibilityIdentifier
        let expectedTitle = workflowApp.expectedHomeWindowTitles.first
        let homeRow = app.buttons
            .matching(identifier: rowIdentifier)
            .firstMatch
        let appList = app.scrollViews
            .matching(identifier: Identifier.homeAppList)
            .firstMatch
        let fallbackScrollContainers =
            app.scrollViews.allElementsBoundByIndex

        guard let expectedTitle else {
            return tapElementAfterScrollingIntoView(
                homeRow,
                in: appList,
                fallbackScrollContainers:
                    fallbackScrollContainers,
                timeout: watchdogBudget.remaining
            )
        }

        let owner =
            FlowTabUITestHomeAppSelectionObservationOwner(
                expectedTitle: expectedTitle,
                readback: {
                    self.homeWindowProjectionSnapshot(
                        in: app,
                        expectation: .titleVisible(expectedTitle)
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        if owner.resolvedEvidence != nil {
            return true
        }

        guard tapElementAfterScrollingIntoView(
            homeRow,
            in: appList,
            fallbackScrollContainers:
                fallbackScrollContainers,
            timeout: watchdogBudget.remaining
        ) else {
            logFlowTabUITestTrace(
                "Home app-row trigger failed for \(workflowApp.appName). "
                    + owner.diagnosticSummary
            )
            return false
        }

        owner.markTriggerCompleted()
        guard owner.waitForResolution(
            timeout: watchdogBudget.remaining
        ) != nil else {
            logFlowTabUITestTrace(
                "Home app selection watchdog expired for "
                    + "\(workflowApp.appName). "
                    + owner.diagnosticSummary
            )
            return false
        }

        return true
    }
}
