import AppKit
import XCTest

extension FlowTabUITests {
    func testSystemAppMRUOrderSurvivesRelaunchAndRepeatedFreshSwitcherSessions() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let launchArguments = [
            "--flowtab-ui-open-switcher",
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-runtime-log-level", "INFO",
            "-windowLayerAutoEnterDelay", "30.0"
        ]

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: launchArguments,
            beforeFlowTabLaunch: { workflow in
                for workflowApp in workflow.apps.reversed() {
                    XCUIApplication(
                        bundleIdentifier: workflowApp.identity.bundleIdentifier
                    ).activate()
                    XCTAssertTrue(
                        waitForFrontmostBundleIdentifier(
                            workflowApp.identity.bundleIdentifier,
                            timeout: 5
                        ),
                        "Failed to establish the fixture application activation Oracle."
                    )
                }
            }
        ) { workflow, app in
            let fixtureAppIDs = workflow.apps.map(\.identity.bundleIdentifier)
            let initialOrder = waitForWorkflowAppOrder(
                fixtureAppIDs,
                in: app,
                timeout: 10
            )
            XCTAssertEqual(initialOrder.first, fixtureAppIDs.first)

            app.terminate()
            waitForFlowTabUITestApplicationToTerminate(app, timeout: 5)
            XCUIApplication(bundleIdentifier: initialOrder[0]).activate()
            XCTAssertTrue(waitForFrontmostBundleIdentifier(initialOrder[0], timeout: 5))

            let relaunchedApp = makeRealRuntimeFlowTabApp(
                additionalArguments: ["--flowtab-ui-preserve-system-app-mru"] + launchArguments
            )
            defer {
                if relaunchedApp.state == .runningForeground
                    || relaunchedApp.state == .runningBackground {
                    relaunchedApp.terminate()
                }
            }
            launchFlowTabUITestApplication(relaunchedApp, traceLabel: "system-app-mru.relaunch")
            XCTAssertTrue(
                waitForFlowTabUITestApplicationToBecomeReady(
                    relaunchedApp,
                    timeout: 12,
                    traceLabel: "system-app-mru.relaunch"
                )
            )

            let restoredOrder = waitForWorkflowAppOrder(
                fixtureAppIDs,
                in: relaunchedApp,
                timeout: 10
            )
            XCTAssertEqual(restoredOrder, initialOrder)

            relaunchedApp.typeKey(.escape, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                .global,
                traceLabel: "system-app-mru.reopen"
            )
            let reopenedOrder = waitForWorkflowAppOrder(
                fixtureAppIDs,
                in: relaunchedApp,
                timeout: 10
            )
            XCTAssertEqual(reopenedOrder, initialOrder)
        }
    }

    private func waitForWorkflowAppOrder(
        _ expectedAppIDs: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> [String] {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let expectedSet = Set(expectedAppIDs)
        let deadline = Date().addingTimeInterval(timeout)
        var latestOrder: [String] = []

        repeat {
            if diagnosticsSummary.exists {
                latestOrder = switcherPanelDiagnosticsValue(
                    diagnosticsSummary,
                    key: "apps"
                )
                .split(separator: "|")
                .compactMap { entry in
                    entry.split(separator: ":", maxSplits: 1).first.map(String.init)
                }
                .filter(expectedSet.contains)
                if latestOrder.count == expectedAppIDs.count
                    && Set(latestOrder) == expectedSet {
                    return latestOrder
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            "Expected workflow app order \(expectedAppIDs), observed \(latestOrder). "
                + switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary)
        )
        return latestOrder
    }

    private func waitForFlowTabUITestApplicationToTerminate(
        _ app: XCUIApplication,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.state == .notRunning {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTFail("FlowTab did not terminate before the MRU relaunch phase.")
    }
}
