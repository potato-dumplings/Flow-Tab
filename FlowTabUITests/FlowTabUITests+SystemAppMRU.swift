import AppKit
import XCTest

private enum FlowTabUITestSystemAppMRUPolicy {
    static let switcherDismissalWatchdog: TimeInterval = 4
}

struct FlowTabUITestWorkflowAppOrderEvidence: Equatable {
    let diagnosticsValue: String?
    let order: [String]

    init(
        diagnosticsValue: String?,
        expectedAppIdentifiers: Set<String>
    ) {
        self.diagnosticsValue = diagnosticsValue
        order = diagnosticsValue?
            .split(separator: "|")
            .compactMap { entry in
                entry
                    .split(separator: ":", maxSplits: 1)
                    .first
                    .map(String.init)
            }
            .filter(expectedAppIdentifiers.contains) ?? []
    }

    var diagnosticSummary: String {
        "summaryExists=\(diagnosticsValue != nil) "
            + "order=\(order) "
            + "appsValue=\(diagnosticsValue ?? "nil")"
    }

    func matches(_ expectedOrder: [String]) -> Bool {
        order == expectedOrder
    }
}

extension FlowTabUITests {
    func testSystemAppMRURebuildsForEveryFlowTabProcessSession() throws {
        let workflow = try configuredSystemAppMRUFixtureWorkflow()
        var initialLaunchLogSnapshot: [String: UInt64] = [:]
        let launchArguments = [
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
            let initialOrder = triggerAndWaitForWorkflowAppOrder(
                fixtureAppIDs,
                in: app,
                timeout: 10,
                traceLabel: "system-app-mru.initial"
            )
            XCTAssertEqual(initialOrder, fixtureAppIDs)
            waitForRuntimeLogFiles(
                containing: ["collectAppRank", "bootstrapFallback=0"],
                since: initialLaunchLogSnapshot,
                timeout: 10
            )

            terminateFlowTabUITestApplicationAndWait(
                app,
                timeout: 5
            )
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

            let rebuiltOrder = triggerAndWaitForWorkflowAppOrder(
                relaunchedExpectedOrder,
                in: relaunchedApp,
                timeout: 10,
                traceLabel: "system-app-mru.relaunch-order"
            )
            XCTAssertEqual(rebuiltOrder, relaunchedExpectedOrder)
            XCTAssertNotEqual(rebuiltOrder, initialOrder)
            waitForRuntimeLogFiles(
                containing: ["collectAppRank", "bootstrapFallback=0"],
                since: relaunchedLogSnapshot,
                timeout: 10
            )

            for iteration in 1...10 {
                dismissSwitcherAndWait(
                    in: relaunchedApp,
                    timeout:
                        FlowTabUITestSystemAppMRUPolicy
                            .switcherDismissalWatchdog
                )
                let reopenedOrder = triggerAndWaitForWorkflowAppOrder(
                    relaunchedExpectedOrder,
                    in: relaunchedApp,
                    timeout: 10,
                    traceLabel:
                        "system-app-mru.reopen.\(iteration)"
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
            assertTriggerMakesApplicationFrontmost(
                bundleIdentifier,
                timeout: 5,
                message: "Failed to establish the fixture application activation Oracle."
            ) {
                XCUIApplication(
                    bundleIdentifier: bundleIdentifier
                ).activate()
            }
        }
    }

    private func triggerAndWaitForWorkflowAppOrder(
        _ expectedAppIDs: [String],
        in app: XCUIApplication,
        timeout: TimeInterval,
        traceLabel: String
    ) -> [String] {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let expectedSet = Set(expectedAppIDs)
        let owner = FlowTabUITestConditionObservationOwner(
            observationRegistration:
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
            readback: {
                FlowTabUITestWorkflowAppOrderEvidence(
                    diagnosticsValue: diagnosticsSummary.exists
                        ? self.switcherPanelDiagnosticsValue(
                            diagnosticsSummary,
                            key: "apps"
                        )
                        : nil,
                    expectedAppIdentifiers: expectedSet
                )
            },
            isSatisfied: { evidence in
                evidence.matches(expectedAppIDs)
            },
            describe: \.diagnosticSummary
        )
        owner.start()
        defer { owner.cancel() }

        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            .global,
            traceLabel: traceLabel
        )
        if let evidence = owner.waitForResolution(timeout: timeout) {
            return evidence.value.order
        }

        XCTFail(
            "Expected workflow app order \(expectedAppIDs). "
                + "\(owner.diagnosticSummary). "
                + switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary)
        )
        return owner.latestEvidence?.value.order ?? []
    }

    private func dismissSwitcherAndWait(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: diagnosticsSummary
        )
        expectation.expectationDescription =
            "System MRU switcher summary disappears after Escape"

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertEqual(
            XCTWaiter.wait(
                for: [expectation],
                timeout: timeout
            ),
            .completed,
            "Switcher did not dismiss after Escape. "
                + switcherDebugSummary(
                    app,
                    diagnosticsSummary: diagnosticsSummary
                )
        )
    }

    private func terminateFlowTabUITestApplicationAndWait(
        _ app: XCUIApplication,
        timeout: TimeInterval
    ) {
        app.terminate()
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: timeout),
            "FlowTab did not terminate before the MRU relaunch phase. "
                + "lastState=\(String(describing: app.state))"
        )
    }
}
