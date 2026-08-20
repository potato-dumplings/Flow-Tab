import Foundation
import XCTest

private enum SpaceFixtureEdgeInputsWorkflowDefaults {
    static let sharedWindowTitle = "Shared Docs"
    static let edgeWindowTitle =
        "报告 Docs: QA, punctuation & spaces - Long Title 2026 with extra searchable text for AX runtime coverage"
    static let appNameFallbackSystemTitle = "Chrome Fixture"
    static let appNameFallbackContentTitle = "Project Alpha"
    static let appNameFallbackSiblingTitle = "Project Beta"

    static var workflowSourceURL: URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("space-fixture-switcher-edge-inputs-workflow.json")
    }

    static var appNameFallbackWorkflowSourceURL: URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent(
                "space-fixture-app-name-fallback-visible-frame-workflow.json"
            )
    }

    private static var repositoryRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

extension FlowTabUITests {
    func testHomeAndSwitcherKeepAppNameFallbackVisibleFrameWindowsDistinctAfterRefresh() throws {
        let workflow = try configuredAppNameFallbackVisibleFrameWorkflow()
        let targetApp = try XCTUnwrap(workflow.apps.first)
        let expectedTitles = [
            SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackSystemTitle,
            SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackSiblingTitle
        ]

        try runRealSpaceFixtureEdgeInputsWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-listen-switcher-trigger",
                "-windowLayerAutoEnterDelay",
                "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        ) { _, app in
            let fixtureApp = makeEdgeWorkflowApplication(
                for: targetApp.identity
            )
            let contentTitle = element(
                in: fixtureApp,
                identifier: "flowtab.spacefixture.window.title.1"
            )
            XCTAssertTrue(
                contentTitle.waitForExistence(timeout: 5),
                "Visible-frame fixture did not publish its first content title."
            )
            XCTAssertEqual(
                contentTitle.label,
                SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackContentTitle
            )

            let targetPID = try targetProcessIdentifier(for: targetApp)
            _ = openHomeTabAndSelectSpaceFixtureApp(
                in: app,
                identity: targetApp.identity,
                expectedValue: "2w"
            )
            for title in expectedTitles {
                assertHomeWindowTitle(
                    title,
                    in: app,
                    message: "Home lost the visible-frame window titled \(title) on the initial mapping"
                )
            }

            let secondMappingLogBaseline = makeRuntimeLogFileSnapshot()
            defer { secondMappingLogBaseline.cancel() }
            let refreshWindowRow = try XCTUnwrap(
                waitForHomeWindowRow(
                    in: app,
                    title: SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackSiblingTitle,
                    timeout: 5
                ),
                "Home did not expose the second visible-frame window before refresh activation."
            )
            refreshWindowRow.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).tap()
            XCTAssertTrue(
                fixtureApp.wait(for: .runningForeground, timeout: 5),
                "Visible-frame fixture did not become foreground before the second mapping."
            )
            app.activate()
            assertRealSpaceFixtureFlowTabIsForegroundReadyAfterFixtureLaunch(
                app,
                targetDescription: "app-name-fallback-second-mapping"
            )

            let escapedAppName = NSRegularExpression.escapedPattern(
                for: targetApp.appName
            )
            let escapedFallbackTitle = NSRegularExpression.escapedPattern(
                for: SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackSystemTitle
            )
            waitForRuntimeLogFiles(
                matching:
                    #"window-entries app=\#(escapedAppName) pid=\#(targetPID) ax=[1-9][0-9]* entries=2 [^\n]*detail=\[[^\n]*title=\#(escapedFallbackTitle):mode=[^,\n]*:source=privateExactBridge"#,
                since: secondMappingLogBaseline,
                description: "second mapping keeps the app-name fallback window private-exact"
            )

            _ = openHomeTabAndSelectSpaceFixtureApp(
                in: app,
                identity: targetApp.identity,
                expectedValue: "2w"
            )
            for title in expectedTitles {
                assertHomeWindowTitle(
                    title,
                    in: app,
                    message: "Home lost the visible-frame window titled \(title) after the second mapping"
                )
            }

            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                .global,
                traceLabel: "appNameFallback.secondMapping.switcher"
            )
            guard assertCurrentSwitcherAppProjection(
                in: app,
                exactEntry: "\(targetApp.identity.bundleIdentifier):2",
                timeout: FlowTabUITestSwitcherAppProjectionPolicy.edgeInputsInitialProjectionWatchdog
            ) else { return }
            XCTAssertTrue(
                selectEdgeWorkflowAppInSwitcherAppLayer(
                    targetApp,
                    app: app
                ),
                "Switcher did not select the app-name fallback fixture."
            )
            let cards = performAndWaitForSwitcherWindowCards(
                in: app,
                expectedTitles: expectedTitles,
                timeout: FlowTabUITestSwitcherWindowCardPolicy.edgeInputsProjectionWatchdog
            ) {
                app.typeKey(.downArrow, modifierFlags: [])
            }

            XCTAssertEqual(cards.count, 2)
            XCTAssertEqual(Set(cards.map(\.identifier)).count, 2)
            XCTAssertEqual(
                edgeTitleCounts(cards.map(\.title)),
                edgeTitleCounts(expectedTitles)
            )
        }
    }

    func testHomePageKeepsIdenticalRealWorkflowWindowsDistinct() throws {
        let workflow = try configuredSwitcherEdgeInputsWorkflow()
        let sharedTitle =
            SpaceFixtureEdgeInputsWorkflowDefaults.sharedWindowTitle
        let targetApp = try XCTUnwrap(
            workflow.apps.first {
                $0.expectedWindowTitles.filter { $0 == sharedTitle }.count
                    == 2
            },
            "Edge workflow must include one app with duplicate same-title windows."
        )

        try runRealSpaceFixtureEdgeInputsWorkflow(
            workflow,
            flowTabAdditionalArguments: []
        ) { _, app in
            _ = openHomeTabAndSelectSpaceFixtureApp(
                in: app,
                identity: targetApp.identity,
                expectedValue: "2w"
            )
            assertHomeWindowRowLabelPrefix(
                [sharedTitle, sharedTitle],
                in: app,
                timeout:
                    FlowTabUITestSpaceFixtureHomeProjectionPolicy
                        .defaultAppRowProjectionWatchdog,
                message:
                    "Home collapsed duplicate same-title fixture windows"
            )
        }
    }

    func testSwitcherPanelPreviewKeepsIdenticalRealWorkflowWindowsDistinct() throws {
        let workflow = try configuredSwitcherEdgeInputsWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first {
                $0.expectedWindowTitles.filter { $0 == SpaceFixtureEdgeInputsWorkflowDefaults.sharedWindowTitle }.count == 2
            },
            "Edge workflow must include one app with duplicate same-title windows."
        )
        let logBaseline = makeRuntimeLogFileSnapshot()
        let focusedPublicState =
            SpaceFixtureFocusedPublicStateObservationOwner(
                bundleIdentifier:
                    targetApp.identity.bundleIdentifier,
                baseline: logBaseline
            )
        focusedPublicState.start()
        defer {
            focusedPublicState.cancel()
            logBaseline.cancel()
        }

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
            let targetPID = try targetProcessIdentifier(
                for: targetApp
            )
            focusedPublicState.bindTarget(
                processIdentifier: targetPID
            )
            guard assertCurrentSwitcherAppProjection(
                in: app,
                exactEntry: "\(targetApp.identity.bundleIdentifier):2",
                timeout: FlowTabUITestSwitcherAppProjectionPolicy.edgeInputsInitialProjectionWatchdog
            ) else { return }
            XCTAssertTrue(
                selectEdgeWorkflowAppInSwitcherAppLayer(
                    targetApp,
                    app: app
                ),
                "Switcher did not select the duplicate-window workflow app before preview assertions."
            )

            let cards = performAndWaitForSwitcherWindowCards(
                in: app,
                expectedTitles: targetApp.expectedWindowTitles,
                timeout:
                    FlowTabUITestSwitcherWindowCardPolicy
                        .edgeInputsProjectionWatchdog
            ) {
                app.typeKey(.downArrow, modifierFlags: [])
            }

            XCTAssertEqual(cards.count, targetApp.expectedWindowTitles.count)
            XCTAssertEqual(Set(cards.map(\.identifier)).count, cards.count)
            XCTAssertEqual(edgeTitleCounts(cards.map(\.title)), edgeTitleCounts(targetApp.expectedWindowTitles))
            guard focusedPublicState.waitForResolution(
                timeout:
                    SpaceFixtureFocusedPublicStateObservationPolicy
                        .evidenceWatchdog
            ) != nil else {
                XCTFail(
                    "Focused public-state evidence watchdog expired. "
                        + focusedPublicState.diagnosticSummary
                )
                return
            }
        }
    }

    func testSwitcherPanelPreviewCapturesRealMinimizedPublicAXState() throws {
        let workflow = try configuredSwitcherEdgeInputsWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first {
                $0.expectedWindowTitles.filter { $0 == SpaceFixtureEdgeInputsWorkflowDefaults.sharedWindowTitle }.count == 2
            },
            "Edge workflow must include one app with duplicate same-title windows."
        )
        let logBaseline = makeRuntimeLogFileSnapshot()
        let minimizedAXPropagation =
            SpaceFixtureMinimizedAXPropagationObservationOwner(
                appName: targetApp.appName,
                expectedWindowTitle:
                    SpaceFixtureEdgeInputsWorkflowDefaults
                    .sharedWindowTitle,
                baseline: logBaseline
            )
        minimizedAXPropagation.start()
        defer {
            minimizedAXPropagation.cancel()
            logBaseline.cancel()
        }

        try runRealSpaceFixtureEdgeInputsWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-listen-switcher-trigger",
                "-windowLayerAutoEnterDelay",
                "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        ) { _, app in
            let targetPID = try targetProcessIdentifier(for: targetApp)
            minimizedAXPropagation.bindTarget(
                processIdentifier: targetPID
            )
            guard assertCurrentSwitcherAppProjection(
                in: app,
                exactEntry: "\(targetApp.identity.bundleIdentifier):2",
                timeout: FlowTabUITestSwitcherAppProjectionPolicy.edgeInputsInitialProjectionWatchdog
            ) else { return }
            XCTAssertTrue(
                selectEdgeWorkflowAppInSwitcherAppLayer(
                    targetApp,
                    app: app
                ),
                "Switcher did not select the duplicate-window workflow app before minimized-state assertions."
            )

            _ = performAndWaitForSwitcherWindowCards(
                in: app,
                expectedTitles: targetApp.expectedWindowTitles,
                timeout:
                    FlowTabUITestSwitcherWindowCardPolicy
                        .edgeInputsProjectionWatchdog
            ) {
                minimizedAXPropagation.performPreviewTrigger {
                    app.typeKey(.downArrow, modifierFlags: [])
                }
            }
            guard minimizedAXPropagation.waitForResolution(
                timeout:
                    SpaceFixtureMinimizedAXPropagationObservationPolicy
                    .evidenceWatchdog
            ) != nil else {
                XCTFail(
                    "Minimized AX propagation evidence watchdog expired. "
                        + minimizedAXPropagation.diagnosticSummary
                )
                return
            }
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

            let results =
                performAndWaitForSwitcherSearchWindowIdentifiers(
                    in: app,
                    scope: "window",
                    query: sharedTitle,
                    expectedCount: expectedSharedCount,
                    timeout:
                        FlowTabUITestSwitcherSearchResultObservationPolicy
                        .edgeInputsCommittedResultWatchdog
                ) {
                    app.typeText(sharedTitle)
                }
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

            let query = "punctuation"
            let results =
                performAndWaitForSwitcherSearchWindowIdentifiers(
                    in: app,
                    scope: "window",
                    query: query,
                    identifierFragment:
                        edgeWorkflowSearchWindowIdentifierAppFragment(
                            for: targetApp
                        ),
                    expectedCount: 1,
                    timeout:
                        FlowTabUITestSwitcherSearchResultObservationPolicy
                        .edgeInputsCommittedResultWatchdog
                ) {
                    app.typeText(query)
                }
            XCTAssertEqual(results.count, 1)
            let resultIdentifier = try XCTUnwrap(
                results.first,
                "Edge-title Search result evidence was unavailable."
            )
            let targetWindowNumber = try XCTUnwrap(
                edgeWorkflowCGWindowID(
                    fromSearchResultIdentifier:
                        resultIdentifier
                ),
                "Edge-title search result did not include a recoverable CG window id."
            )

            XCTAssertTrue(
                triggerAndWaitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: edgeTitle,
                    app: targetApp,
                    timeout:
                        FlowTabUITestWorkflowWindowActivationObservationPolicy
                        .edgeInputsExactWindowWatchdog,
                    trigger: {
                        confirmEdgeSwitcherSearchSelection(
                            in: app,
                            searchInput: searchInput,
                            expectedQuery: query
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
        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            .search,
            traceLabel: traceLabel
        )
        return requireInitialFlowTabSearchInput(
            in: app,
            observedBy: readiness
        )
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

    private func configuredAppNameFallbackVisibleFrameWorkflow(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SpaceFixtureResolvedWorkflow {
        let sourceURL =
            SpaceFixtureEdgeInputsWorkflowDefaults
            .appNameFallbackWorkflowSourceURL
        do {
            let installedWorkflow = try SpaceFixtureResolvedWorkflow.configured(
                environment: environment
            )
            let workflow = try resolveSpaceFixtureWorkflowScenario(
                sourceWorkflowURL: sourceURL,
                using: installedWorkflow
            )
            let expectedTitles = [
                SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackSystemTitle,
                SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackSiblingTitle
            ]
            guard workflow.apps.count == 1,
                  workflow.apps.first?.expectedWindowTitles == expectedTitles,
                  workflow.apps.first?.expectedContentTitles == [
                      SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackContentTitle,
                      SpaceFixtureEdgeInputsWorkflowDefaults.appNameFallbackSiblingTitle
                  ],
                  workflow.apps.first?.visibleFrameWindowIndices == [1, 2]
            else {
                throw XCTSkip(
                    multiAppWorkflowSetupMessage(
                        reason: "Resolved workflow does not contain the two app-name fallback windows.",
                        scenarioSourceURL: sourceURL
                    )
                )
            }
            return workflow
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            switch error {
            case .missingWorkflowPath,
                 .workflowScenarioMissingAppVariant,
                 .workflowScenarioBundleIdentifierMismatch:
                throw XCTSkip(
                    multiAppWorkflowSetupMessage(
                        reason: error.localizedDescription,
                        scenarioSourceURL: sourceURL
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

        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: nil,
            targetDescription: "edge-inputs-post-fixture-launch"
        )
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
        validateResolvedSpaceFixtureWorkflowMetadata(
            after: readinessSnapshot,
            workflow: workflow,
            applications: launchedApps,
            waitsForFullscreenMarkers: false,
            suppressesApplicationAccessibilityChildren:
                false
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
            terminateSpaceFixtureApplicationAndWait(app)
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
