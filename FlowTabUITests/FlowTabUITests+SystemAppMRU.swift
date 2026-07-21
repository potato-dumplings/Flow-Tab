import AppKit
import XCTest

extension FlowTabUITests {
    func testSystemAppMRURebuildsForEveryFlowTabProcessSession() throws {
        let workflow = try configuredSystemAppMRUFixtureWorkflow()
        var initialLaunchLogSnapshot: [String: UInt64] = [:]
        let launchArguments = [
            "--flowtab-ui-open-switcher",
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-runtime-log-level", "DEBUG",
            "--flowtab-ui-enable-verbose-logs",
            "-windowLayerAutoEnterDelay", "30.0"
        ]

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: launchArguments,
            beforeFlowTabLaunch: { [self] workflow in
                self.establishSystemAppOrder(
                    workflow.apps.map(\.identity.bundleIdentifier)
                )
                initialLaunchLogSnapshot = self.makeRuntimeLogFileSnapshot()
            }
        ) { workflow, app in
            let fixtureAppIDs = workflow.apps.map(\.identity.bundleIdentifier)
            let initialOrder = waitForWorkflowAppOrder(
                fixtureAppIDs,
                in: app,
                timeout: 10
            )
            XCTAssertEqual(initialOrder, fixtureAppIDs)
            waitForRuntimeLogFiles(
                containing: ["collectAppRank", "bootstrapFallback=0"],
                since: initialLaunchLogSnapshot,
                timeout: 10
            )

            app.terminate()
            waitForFlowTabUITestApplicationToTerminate(app, timeout: 5)
            let relaunchedExpectedOrder = [3, 7, 1, 5, 0, 6, 2, 4].map { fixtureAppIDs[$0] }
            establishSystemAppOrder(relaunchedExpectedOrder)
            let relaunchedLogSnapshot = makeRuntimeLogFileSnapshot()

            let relaunchedApp = makeRealRuntimeFlowTabApp(
                additionalArguments: launchArguments
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

            let rebuiltOrder = waitForWorkflowAppOrder(
                fixtureAppIDs,
                in: relaunchedApp,
                timeout: 10
            )
            XCTAssertEqual(rebuiltOrder, relaunchedExpectedOrder)
            XCTAssertNotEqual(rebuiltOrder, initialOrder)
            waitForRuntimeLogFiles(
                containing: ["collectAppRank", "bootstrapFallback=0"],
                since: relaunchedLogSnapshot,
                timeout: 10
            )

            for iteration in 1...10 {
                relaunchedApp.typeKey(.escape, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                    .global,
                    traceLabel: "system-app-mru.reopen.\(iteration)"
                )
                let reopenedOrder = waitForWorkflowAppOrder(
                    fixtureAppIDs,
                    in: relaunchedApp,
                    timeout: 10
                )
                XCTAssertEqual(reopenedOrder, relaunchedExpectedOrder)
            }
        }
    }

    private func configuredSystemAppMRUFixtureWorkflow() throws -> SpaceFixtureResolvedWorkflow {
        let environmentKey = "FLOWTAB_SYSTEM_APP_MRU_FIXTURE_WORKFLOW_PATH"
        let configuredPath = ProcessInfo.processInfo.environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let workflowURL = if let configuredPath, !configuredPath.isEmpty {
            URL(fileURLWithPath: configuredPath).standardizedFileURL
        } else {
            SpaceFixtureMultiAppWorkflowDefaults.defaultSystemAppMRUResolvedWorkflowURL
        }
        guard FileManager.default.fileExists(atPath: workflowURL.path) else {
            throw XCTSkip(
                "The eight-app system MRU fixture workflow is missing at \(workflowURL.path)."
            )
        }

        let workflow = try SpaceFixtureResolvedWorkflow.load(
            from: workflowURL
        )
        guard workflow.apps.count == 8 else {
            throw XCTSkip("The system MRU fixture workflow must contain eight applications.")
        }
        return workflow
    }

    private func establishSystemAppOrder(_ orderedAppIDs: [String]) {
        for bundleIdentifier in orderedAppIDs.reversed() {
            XCUIApplication(bundleIdentifier: bundleIdentifier).activate()
            XCTAssertTrue(
                waitForFrontmostBundleIdentifier(bundleIdentifier, timeout: 5),
                "Failed to establish the fixture application activation Oracle."
            )
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
