import Foundation
import XCTest

private enum SpaceFixtureEdgeInputsWorkflowDefaults {
    static let sharedWindowTitle = "Shared Docs"
    static let edgeWindowTitle =
        "报告 Docs: QA, punctuation & spaces - Long Title 2026 with extra searchable text for AX runtime coverage"

    static var workflowSourceURL: URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("space-fixture-switcher-edge-inputs-workflow.json")
    }

    private static var repositoryRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

extension FlowTabUITests {
    func testSwitcherPanelPreviewKeepsIdenticalRealWorkflowWindowsDistinct() throws {
        let workflow = try configuredSwitcherEdgeInputsWorkflow()
        let logSnapshot = makeRuntimeLogFileSnapshot()
        let targetApp = try XCTUnwrap(
            workflow.apps.first {
                $0.expectedWindowTitles.filter { $0 == SpaceFixtureEdgeInputsWorkflowDefaults.sharedWindowTitle }.count == 2
            },
            "Edge workflow must include one app with duplicate same-title windows."
        )

        try runRealSpaceFixtureEdgeInputsWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-listen-switcher-trigger"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            XCTAssertTrue(
                selectEdgeWorkflowAppInSwitcherAppLayer(
                    targetApp,
                    app: app,
                    diagnosticsSummary: diagnosticsSummary,
                    timeout: 10
                ),
                "Switcher did not select the duplicate-window workflow app before preview assertions."
            )

            app.typeKey(.downArrow, modifierFlags: [])
            let cards = waitForEdgeSwitcherWindowCards(
                in: app,
                expectedTitles: targetApp.expectedWindowTitles,
                timeout: 8
            )

            XCTAssertEqual(cards.count, targetApp.expectedWindowTitles.count)
            XCTAssertEqual(Set(cards.map(\.identifier)).count, cards.count)
            XCTAssertEqual(edgeTitleCounts(cards.map(\.title)), edgeTitleCounts(targetApp.expectedWindowTitles))
            let targetPID = try targetProcessIdentifier(for: targetApp)
            waitForRuntimeLogFiles(
                matching: #"binding-assignment public-state-tiebreak state=focused ax=ax:\#(targetPID):[0-9]+ cg=[0-9]+ axCandidates=[2-9][0-9]* cgCandidates=[2-9][0-9]*"#,
                since: logSnapshot,
                timeout: 8,
                description: "real edge workflow resolves identical AX/CG candidates through the target app's focused public AX state"
            )
        }
    }

    func testSwitcherPanelPreviewCapturesRealMinimizedPublicAXState() throws {
        let workflow = try configuredSwitcherEdgeInputsWorkflow()
        let logSnapshot = makeRuntimeLogFileSnapshot()
        let targetApp = try XCTUnwrap(
            workflow.apps.first {
                $0.expectedWindowTitles.filter { $0 == SpaceFixtureEdgeInputsWorkflowDefaults.sharedWindowTitle }.count == 2
            },
            "Edge workflow must include one app with duplicate same-title windows."
        )

        try runRealSpaceFixtureEdgeInputsWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-listen-switcher-trigger"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        ) { _, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            XCTAssertTrue(
                selectEdgeWorkflowAppInSwitcherAppLayer(
                    targetApp,
                    app: app,
                    diagnosticsSummary: diagnosticsSummary,
                    timeout: 10
                ),
                "Switcher did not select the duplicate-window workflow app before minimized-state assertions."
            )

            app.typeKey(.downArrow, modifierFlags: [])
            _ = waitForEdgeSwitcherWindowCards(
                in: app,
                expectedTitles: targetApp.expectedWindowTitles,
                timeout: 8
            )
            let targetPID = try targetProcessIdentifier(for: targetApp)
            waitForRuntimeLogFiles(
                matching: #"chrome-topology app=Chrome Fixture pid=\#(targetPID) .* ax=\[.*min=1.*\] cg=\[.*Shared Docs:off:spaces=\[[0-9,]*\]:frame="#,
                since: logSnapshot,
                timeout: 8,
                description: "real edge workflow exposes a minimized AX window with an offscreen CG counterpart"
            )
            waitForRuntimeLogFiles(
                matching: #"window-entries app=Chrome Fixture pid=\#(targetPID) .*off:minimized=1"#,
                since: logSnapshot,
                timeout: 8,
                description: "real edge workflow carries minimized public AX state into window-layer output"
            )
        }
    }

    func testSwitcherPanelWindowSearchKeepsDuplicateRealWorkflowTitlesDistinct() throws {
        let workflow = try configuredSwitcherEdgeInputsWorkflow()
        let sharedTitle = SpaceFixtureEdgeInputsWorkflowDefaults.sharedWindowTitle
        let expectedSharedCount = workflow.apps
            .flatMap(\.expectedWindowTitles)
            .filter { $0 == sharedTitle }
            .count
        let finderApp = try XCTUnwrap(workflow.apps.first { $0.appID == "finder" })
        let chromeApp = try XCTUnwrap(workflow.apps.first { $0.appID == "chrome" })

        try runRealSpaceFixtureEdgeInputsWorkflow(
            workflow,
            flowTabAdditionalArguments: runtimeTruthSwitcherLaunchArguments(
                additionalArguments: [
                    "-searchDefaultScope",
                    "window"
                ],
                suppressesPanelActivation: false
            )
        ) { _, app in
            let searchInput = openEdgeWorkflowWindowSearch(
                in: app,
                traceLabel: "edgeInputs.search.duplicates"
            )

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            app.typeText(sharedTitle)

            let results = waitForEdgeSearchWindowResultIdentifiers(
                in: app,
                expectedCount: expectedSharedCount,
                timeout: 8
            )
            let finderIdentifierFragment = edgeWorkflowSearchWindowIdentifierAppFragment(for: finderApp)
            let chromeIdentifierFragment = edgeWorkflowSearchWindowIdentifierAppFragment(for: chromeApp)

            XCTAssertEqual(Set(results).count, expectedSharedCount)
            XCTAssertEqual(
                results.filter { $0.contains(finderIdentifierFragment) }.count,
                1
            )
            XCTAssertEqual(
                results.filter { $0.contains(chromeIdentifierFragment) }.count,
                2
            )
        }
    }

    func testSwitcherPanelWindowSearchMatchesAndActivatesRealWorkflowEdgeTitle() throws {
        let workflow = try configuredSwitcherEdgeInputsWorkflow()
        let edgeTitle = SpaceFixtureEdgeInputsWorkflowDefaults.edgeWindowTitle
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.expectedWindowTitles.contains(edgeTitle) },
            "Edge workflow must include the non-ASCII punctuation and long-title window."
        )

        try runRealSpaceFixtureEdgeInputsWorkflow(
            workflow,
            flowTabAdditionalArguments: runtimeTruthSwitcherLaunchArguments(
                additionalArguments: [
                    "-searchDefaultScope",
                    "window"
                ],
                suppressesPanelActivation: false
            )
        ) { _, app in
            let searchInput = openEdgeWorkflowWindowSearch(
                in: app,
                traceLabel: "edgeInputs.search.edgeTitle"
            )

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            app.typeText("punctuation")

            let results = waitForEdgeSearchWindowResultIdentifiers(
                in: app,
                identifierFragment: edgeWorkflowSearchWindowIdentifierAppFragment(for: targetApp),
                expectedCount: 1,
                timeout: 8
            )
            XCTAssertEqual(results.count, 1)
            let targetWindowNumber = try XCTUnwrap(
                edgeWorkflowCGWindowID(fromSearchResultIdentifier: results[0]),
                "Edge-title search result did not include a recoverable CG window id."
            )

            XCTAssertTrue(
                triggerAndWaitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: edgeTitle,
                    app: targetApp,
                    timeout: 10,
                    trigger: {
                        confirmEdgeSwitcherSearchSelection(
                            in: app,
                            searchInput: searchInput
                        )
                    }
                ),
                "Search confirmation did not activate the edge-title fixture window id."
            )
        }
    }

    private func openEdgeWorkflowWindowSearch(
        in app: XCUIApplication,
        traceLabel: String
    ) -> XCUIElement {
        let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
        let deadline = Date().addingTimeInterval(10)
        var attempt = 1
        repeat {
            postFlowTabUITestSwitcherTrigger(
                .search,
                traceLabel: "\(traceLabel).attempt\(attempt)"
            )
            if searchInput.waitForExistence(timeout: 1.2) {
                return searchInput
            }
            attempt += 1
        } while Date() < deadline

        XCTFail("Edge workflow window Search did not present from committed runtime index.")
        return searchInput
    }

    private func configuredSwitcherEdgeInputsWorkflow(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SpaceFixtureResolvedWorkflow {
        do {
            let installedWorkflow = try SpaceFixtureResolvedWorkflow.configured(environment: environment)
            let workflow = try resolveSpaceFixtureWorkflowScenario(
                sourceWorkflowURL: SpaceFixtureEdgeInputsWorkflowDefaults.workflowSourceURL,
                using: installedWorkflow
            )
            try validateSwitcherEdgeInputsWorkflow(workflow)
            return workflow
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            switch error {
            case .missingWorkflowPath, .workflowScenarioMissingAppVariant, .workflowScenarioBundleIdentifierMismatch:
                throw XCTSkip(
                    multiAppWorkflowSetupMessage(
                        reason: error.localizedDescription,
                        scenarioSourceURL: SpaceFixtureEdgeInputsWorkflowDefaults.workflowSourceURL
                    )
                )
            default:
                XCTFail(error.localizedDescription)
                throw error
            }
        } catch {
            XCTFail(error.localizedDescription)
            throw error
        }
    }

    private func validateSwitcherEdgeInputsWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow
    ) throws {
        let sharedTitle = SpaceFixtureEdgeInputsWorkflowDefaults.sharedWindowTitle
        let sharedWindowCount = workflow.apps
            .flatMap(\.expectedWindowTitles)
            .filter { $0 == sharedTitle }
            .count
        guard sharedWindowCount >= 3 else {
            throw XCTSkip(edgeInputsWorkflowSetupMessage(reason: "Resolved workflow is missing duplicate Shared Docs windows."))
        }

        guard workflow.apps.contains(where: {
            $0.expectedWindowTitles.filter { $0 == sharedTitle }.count >= 2
        }) else {
            throw XCTSkip(edgeInputsWorkflowSetupMessage(reason: "Resolved workflow is missing same-app duplicate windows."))
        }

        guard workflow.allExpectedWindowTitles.contains(SpaceFixtureEdgeInputsWorkflowDefaults.edgeWindowTitle) else {
            throw XCTSkip(edgeInputsWorkflowSetupMessage(reason: "Resolved workflow is missing the edge-title window."))
        }
    }

    private func runRealSpaceFixtureEdgeInputsWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow,
        flowTabAdditionalArguments: [String],
        perform assertions: (SpaceFixtureResolvedWorkflow, XCUIApplication) throws -> Void
    ) throws {
        terminateEdgeWorkflowAppsIfRunning(workflow)
        let fixtureApps = launchResolvedEdgeInputsWorkflow(workflow)
        defer {
            terminateEdgeWorkflowApps(fixtureApps)
        }

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let app = makeRealRuntimeFlowTabApp(additionalArguments: flowTabAdditionalArguments)
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))
        try assertions(workflow, app)
    }

    private func launchResolvedEdgeInputsWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow
    ) -> [XCUIApplication] {
        var launchedApps: [XCUIApplication] = []
        let readinessOwner =
            makeSpaceFixtureWorkflowReadinessAggregateOwner(
                for: workflow
            )
        readinessOwner.start()
        defer { readinessOwner.cancel() }

        for workflowApp in workflow.apps {
            let app = makeEdgeWorkflowApplication(for: workflowApp.identity)
            app.launchArguments += [
                "--workflow-config", workflow.workflowURL.path,
                "--workflow-app-id", workflowApp.appID
            ]
            app.launchArguments +=
                readinessOwner.fixtureLaunchArguments(
                    for: workflowApp.appID
                )
            launchSpaceFixtureApplicationAndWaitForForeground(app)
            waitForSpaceFixtureWorkflowMetadata(
                in: app,
                expectedWindowTitles: workflowApp.expectedWindowTitles,
                fullscreenWindowIndex: nil
            )
            launchedApps.append(app)
        }

        guard let readinessSnapshot =
                readinessOwner.waitForReady(
                    timeout: workflow.readinessWatchdog
                )
        else {
            XCTFail(
                "Edge fixture workflow readiness watchdog expired: "
                    + readinessOwner.diagnosticSummary
            )
            return launchedApps
        }
        assertSpaceFixtureWorkflowReadinessAggregate(
            readinessSnapshot,
            workflow: workflow,
            launchedApps: launchedApps
        )
        if let desktopAnchorWorkflowApp =
                workflow.apps.first,
           let desktopAnchorApp = launchedApps.first
        {
            guard let readinessEvidence =
                    readinessSnapshot
                        .readyEvidenceByWorkflowAppID[
                            desktopAnchorWorkflowApp.appID
                        ]
            else {
                XCTFail(
                    "Missing edge desktop-anchor readiness identity for "
                        + desktopAnchorWorkflowApp.appID
                        + ": "
                        + readinessSnapshot.logFields
                )
                return launchedApps
            }
            _ = activateSpaceFixtureWorkflowDesktopAnchor(
                workflowApp: desktopAnchorWorkflowApp,
                application: desktopAnchorApp,
                readinessEvidence: readinessEvidence
            )
        }
        return launchedApps
    }

    private func makeEdgeWorkflowApplication(for identity: SpaceFixtureAppIdentity) -> XCUIApplication {
        if let appURL = identity.appURL {
            return XCUIApplication(url: appURL)
        }
        return XCUIApplication(bundleIdentifier: identity.bundleIdentifier)
    }

    private func terminateEdgeWorkflowAppsIfRunning(_ workflow: SpaceFixtureResolvedWorkflow) {
        terminateEdgeWorkflowApps(workflow.apps.map { makeEdgeWorkflowApplication(for: $0.identity) })
    }

    private func terminateEdgeWorkflowApps(_ apps: [XCUIApplication]) {
        for app in apps.reversed() where app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
            waitForSpaceFixtureApplicationToTerminate(app)
        }
    }

    private func targetProcessIdentifier(for workflowApp: SpaceFixtureResolvedWorkflow.App) throws -> pid_t {
        let runningApp = try XCTUnwrap(
            NSRunningApplication
                .runningApplications(withBundleIdentifier: workflowApp.identity.bundleIdentifier)
                .first,
            "Expected \(workflowApp.identity.bundleIdentifier) to be running for runtime-log PID assertions."
        )
        return runningApp.processIdentifier
    }

    private func edgeInputsWorkflowSetupMessage(reason: String) -> String {
        multiAppWorkflowSetupMessage(
            reason: reason,
            scenarioSourceURL: SpaceFixtureEdgeInputsWorkflowDefaults.workflowSourceURL
        )
    }
}
