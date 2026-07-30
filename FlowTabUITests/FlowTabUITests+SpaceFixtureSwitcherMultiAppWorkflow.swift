import AppKit
import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
    func testSwitcherPanelShowsAllWorkflowAppsInMultiAppFixtureStrip() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)

            for workflowApp in workflow.apps {
                assertSwitcherAppStripContainsWorkflowApp(
                    workflowApp,
                    in: app,
                    diagnosticsSummary: diagnosticsSummary
                )
                if diagnosticsSummary.exists {
                    XCTAssertTrue(
                        waitForSwitcherAppEntry(
                            diagnosticsSummary,
                            bundleIdentifier: workflowApp.identity.bundleIdentifier,
                            timeout: 2
                        ),
                        """
                        FlowTab did not include \(workflowApp.appName) in the switcher diagnostics summary.

                        \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                        """
                    )
                }
            }
        }
    }

    private func assertSwitcherAppStripContainsWorkflowApp(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement
    ) {
        let appTile = element(in: app, identifier: workflowApp.identity.switcherAppAccessibilityIdentifier)
        XCTAssertTrue(
            appTile.waitForExistence(timeout: 8),
            """
            FlowTab did not expose \(workflowApp.appName) through \
            \(workflowApp.identity.switcherAppAccessibilityIdentifier).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
    }

    func testSwitcherPanelPreviewCyclesThroughWorkflowAppsWithoutMixingWindowCards() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-listen-switcher-trigger",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(
                element(
                    in: app,
                    identifier: workflow.apps[0].identity.switcherAppAccessibilityIdentifier
                ).waitForExistence(timeout: 8)
            )
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            selectSwitcherWorkflowApp(workflow.apps[0], in: app, diagnosticsSummary: diagnosticsSummary)

            var observedAppIDs: [String] = []
            for workflowApp in workflow.apps {
                selectSwitcherWorkflowApp(workflowApp, in: app, diagnosticsSummary: diagnosticsSummary)
                app.typeKey(.downArrow, modifierFlags: [])
                let selectedApp = try XCTUnwrap(
                    matchedWorkflowAppForVisibleSwitcherPreview(
                        workflow,
                        diagnosticsSummaryElement: diagnosticsSummary,
                        excludingAppIDs: Set(observedAppIDs)
                    ),
                    """
                    Switcher preview did not stabilize to a single workflow app window set.

                    \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))

                    \(self.multiAppWorkflowSetupMessage(
                        reason: "Resolved switcher workflow window titles did not match a single app.",
                        scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
                    ))
                    """
                )
                XCTAssertFalse(
                    observedAppIDs.contains(selectedApp.appID),
                    "Switcher app cycle repeated \(selectedApp.appName) before visiting every workflow app"
                )
                observedAppIDs.append(selectedApp.appID)
                let visibleTitles = switcherPreviewTitles(from: diagnosticsSummary)
                XCTAssertEqual(Set(visibleTitles), Set(selectedApp.expectedWindowTitles))
                assertSwitcherPreviewShowsOnlyExpectedTitles(
                    selectedApp.expectedWindowTitles,
                    in: diagnosticsSummary,
                    timeout: 8
                )

                app.typeKey(.upArrow, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }

            XCTAssertEqual(Set(observedAppIDs), Set(workflow.apps.map(\.appID)))
        }
    }

    func testSwitcherPanelPreviewUsesRealWindowCardAnchorsForWorkflowAppIsolation() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(
                element(
                    in: app,
                    identifier: workflow.apps[0].identity.switcherAppAccessibilityIdentifier
                ).waitForExistence(timeout: 8)
            )
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            selectSwitcherWorkflowApp(workflow.apps[0], in: app, diagnosticsSummary: diagnosticsSummary)

            var observedAppIDs: [String] = []
            var previousWindowCardIdentifiers: Set<String> = []
            for workflowApp in workflow.apps {
                selectSwitcherWorkflowApp(workflowApp, in: app, diagnosticsSummary: diagnosticsSummary)
                let windowCards = try assertSwitcherPreviewWindowCards(
                    in: app,
                    diagnosticsSummary: diagnosticsSummary,
                    selectedApp: workflowApp,
                    excludedTitles: workflow.otherExpectedWindowTitles(
                        excluding: workflowApp.appID
                    ),
                    previousWindowCardIdentifiers:
                        previousWindowCardIdentifiers,
                    trigger: {
                        app.typeKey(
                            .downArrow,
                            modifierFlags: []
                        )
                    }
                )
                let selectedApp = try XCTUnwrap(
                    matchedWorkflowAppForVisibleSwitcherPreview(
                        workflow,
                        diagnosticsSummaryElement: diagnosticsSummary,
                        excludingAppIDs: Set(observedAppIDs)
                    ),
                    """
                    Switcher preview did not stabilize to a single workflow app window set.

                    \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))

                    \(self.multiAppWorkflowSetupMessage(
                        reason: "Resolved switcher workflow window titles did not match a single app.",
                        scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
                    ))
                    """
                )
                XCTAssertEqual(
                    selectedApp.appID,
                    workflowApp.appID,
                    "Switcher cards should belong to the explicitly selected workflow app"
                )
                XCTAssertFalse(
                    observedAppIDs.contains(selectedApp.appID),
                    "Switcher app cycle repeated \(selectedApp.appName) before visiting every workflow app"
                )
                observedAppIDs.append(selectedApp.appID)

                previousWindowCardIdentifiers = Set(windowCards.map(\.identifier))

                app.typeKey(.upArrow, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }

            XCTAssertEqual(Set(observedAppIDs), Set(workflow.apps.map(\.appID)))
        }
    }

    func testSwitcherPanelRefreshesOpenWorkflowAppWindowLayerAfterMultiAppWindowSetMutation() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.appID == "chrome" },
            "Switcher workflow must include the Chrome-style fixture app for multi-app mutation proof"
        )
        let remainingTitles = Array(targetApp.expectedWindowTitles.prefix(1))
        XCTAssertEqual(targetApp.expectedWindowTitles.count, 2)
        XCTAssertEqual(remainingTitles.count, 1)

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-listen-switcher-trigger",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments,
            workflowAppLaunchArguments: { workflowApp in
                guard workflowApp.appID == targetApp.appID else { return [] }
                return [
                    "--close-window-index", "2",
                    "--close-window-delay-ms", "30000"
                ]
            }
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            XCTAssertTrue(
                element(
                    in: app,
                    identifier: targetApp.identity.switcherAppAccessibilityIdentifier
                ).waitForExistence(timeout: 8)
            )

            let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
            selectSwitcherWorkflowApp(targetApp, in: app, diagnosticsSummary: diagnosticsSummary)
            app.activate()
            app.typeKey(.downArrow, modifierFlags: [])
            XCTAssertTrue(waitForSwitcherMode(diagnosticsSummary, modePrefix: "windowCycle", timeout: 5))
            assertSwitcherPreviewShowsOnlyExpectedTitles(
                targetApp.expectedWindowTitles,
                in: diagnosticsSummary,
                timeout: 8
            )

            assertSwitcherPreviewShowsOnlyExpectedTitles(
                remainingTitles,
                in: diagnosticsSummary,
                timeout: 40
            )
            XCTAssertTrue(waitForSwitcherMode(diagnosticsSummary, modePrefix: "windowCycle", timeout: 5))
            waitForRuntimeLogFiles(
                containing: [
                    "runtimeAXDestroyed appID=\(targetApp.identity.bundleIdentifier)",
                    "affectedCGWindowID="
                ],
                since: mutationLogSnapshot,
                timeout: 8
            )
            XCTAssertNotEqual(
                XCUIApplication(bundleIdentifier: targetApp.identity.bundleIdentifier).state,
                .notRunning
            )
            XCTAssertEqual(
                Set(switcherPreviewTitles(from: diagnosticsSummary)),
                Set(remainingTitles),
                """
                Multi-app open Switcher mutation should keep the selected app's window layer isolated.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
            XCTAssertTrue(
                Set(switcherPreviewTitles(from: diagnosticsSummary))
                    .isDisjoint(with: Set(workflow.otherExpectedWindowTitles(excluding: targetApp.appID))),
                """
                Multi-app open Switcher mutation exposed another app's window card.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
        }
    }

    func testSwitcherPanelRefreshesOpenFullscreenWorkflowAppWindowLayerAfterTargetWindowCloses() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.appID == "notes" },
            "Switcher workflow must include the Notes-style fixture app for fullscreen target-window mutation proof"
        )
        let fullscreenWindowIndex = try XCTUnwrap(targetApp.fullscreenWindowIndex)
        let fullscreenTitles = Set(targetApp.fullscreenWindowTitles)
        let remainingTitles = targetApp.expectedWindowTitles.filter { !fullscreenTitles.contains($0) }
        XCTAssertEqual(targetApp.expectedWindowTitles.count, 2)
        XCTAssertEqual(fullscreenTitles.count, 1)
        XCTAssertEqual(remainingTitles.count, 1)

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-listen-switcher-trigger",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments,
            workflowAppLaunchArguments: { workflowApp in
                guard workflowApp.appID == targetApp.appID else { return [] }
                return [
                    "--close-window-index", "\(fullscreenWindowIndex)",
                    "--close-window-delay-ms", "30000"
                ]
            }
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            XCTAssertTrue(
                element(
                    in: app,
                    identifier: targetApp.identity.switcherAppAccessibilityIdentifier
                ).waitForExistence(timeout: 8)
            )

            let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
            selectSwitcherWorkflowApp(targetApp, in: app, diagnosticsSummary: diagnosticsSummary)
            app.activate()
            app.typeKey(.downArrow, modifierFlags: [])
            XCTAssertTrue(waitForSwitcherMode(diagnosticsSummary, modePrefix: "windowCycle", timeout: 5))
            XCTAssertTrue(
                waitForNoisyFullscreenWorkflowPreviewTitles(
                    diagnosticsSummary,
                    for: targetApp,
                    timeout: 12
                ),
                """
                Expected the open Switcher window layer to expose the Notes fullscreen target before mutation.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
            let closedFullscreenTitle = try XCTUnwrap(
                visibleFullscreenWindowTitle(in: diagnosticsSummary, for: targetApp)
            )

            assertSwitcherPreviewShowsOnlyExpectedTitles(
                remainingTitles,
                in: diagnosticsSummary,
                timeout: 45
            )
            XCTAssertTrue(waitForSwitcherMode(diagnosticsSummary, modePrefix: "windowCycle", timeout: 5))
            waitForRuntimeLogFiles(
                containing: [
                    "runtimeAXDestroyed appID=\(targetApp.identity.bundleIdentifier)",
                    "affectedCGWindowID="
                ],
                since: mutationLogSnapshot,
                timeout: 8
            )
            XCTAssertNotEqual(
                XCUIApplication(bundleIdentifier: targetApp.identity.bundleIdentifier).state,
                .notRunning
            )
            XCTAssertFalse(
                switcherPreviewTitles(from: diagnosticsSummary).contains(closedFullscreenTitle),
                """
                Open Switcher window layer still exposed the closed fullscreen target window.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
            XCTAssertTrue(
                Set(switcherPreviewTitles(from: diagnosticsSummary))
                    .isDisjoint(with: Set(workflow.otherExpectedWindowTitles(excluding: targetApp.appID))),
                """
                Fullscreen target-window mutation exposed another app's window card.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
        }
    }

    func selectSwitcherWorkflowApp(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        maxMoves: Int = 40
    ) {
        if selectSwitcherWorkflowAppDirectly(workflowApp, diagnosticsSummary: diagnosticsSummary) {
            return
        }

        for attempt in 0..<maxMoves {
            let selectedAppID = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected")
            let selectedMode = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "mode")
            logFlowTabUITestTrace(
                "[selectWorkflowApp.\(attempt + 1)] target=\(workflowApp.identity.bundleIdentifier) selected=\(selectedAppID) mode=\(selectedMode)"
            )
            if selectedAppID
                == workflowApp.identity.bundleIdentifier {
                return
            }
            if selectedMode.hasPrefix("windowCycle(") {
                app.typeKey(.upArrow, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                continue
            }
            app.typeKey(.rightArrow, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        }

        XCTFail(
            """
            Failed to select switcher workflow app \(workflowApp.appName).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
    }

    private func selectSwitcherWorkflowAppDirectly(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval = 1.5
    ) -> Bool {
        do {
            try FlowTabUITestSwitcherCommandPayload.write(workflowApp.identity.bundleIdentifier)
        } catch {
            return false
        }

        postFlowTabUITestSwitcherCommand(
            .selectApp,
            traceLabel: "selectWorkflowApp.direct.\(workflowApp.appID)"
        )

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected")
                == workflowApp.identity.bundleIdentifier {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        } while Date() < deadline

        return false
    }

    func testSwitcherPanelWindowSearchFindsAndActivatesRealWorkflowWindow() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetWindowTitle = "Docs"
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.expectedWindowTitles.contains(targetWindowTitle) },
            "Switcher workflow must include a real fixture window titled \(targetWindowTitle)"
        )

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "window"
            ]
        ) { _, app in
            let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
            XCTAssertTrue(searchInput.waitForExistence(timeout: 8))

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            app.typeText(targetWindowTitle)

            guard let result = waitForSearchWindowResult(
                in: app,
                title: targetWindowTitle,
                appName: targetApp.appName,
                timeout: 8
            ) else { return }
            let targetWindowNumber = try XCTUnwrap(
                result.windowNumber,
                "Search result \(result.identifier) did not expose a CG window number."
            )

            XCTAssertTrue(
                triggerAndWaitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout: 10,
                    trigger: {
                        confirmSwitcherSearchSelection(
                            in: app,
                            searchInput: searchInput
                        )
                    }
                ),
                "Search confirmation did not activate the \(targetWindowTitle) fixture window."
            )
        }
    }

    func testSwitcherPanelAppSearchFindsAndActivatesRealWorkflowApp() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.appID == "chrome" },
            "Switcher workflow must include the Chrome-style fixture app for app-scope search"
        )

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "app"
            ]
        ) { _, app in
            let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
            XCTAssertTrue(searchInput.waitForExistence(timeout: 8))
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "The app-scope activation scenario must start outside the target fixture app."
            )

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            app.typeText(targetApp.identity.switcherSearchQuery)

            let result = element(
                in: app,
                identifier: targetApp.identity.switcherSearchAppAccessibilityIdentifier
            )
            XCTAssertTrue(
                result.waitForExistence(timeout: 8),
                "FlowTab did not expose \(targetApp.appName) as a real app-scope search result."
            )

            confirmSwitcherSearchSelection(in: app, searchInput: searchInput)
            XCTAssertTrue(
                waitForFrontmostWorkflowApp(targetApp, timeout: 10),
                "Search confirmation did not activate the \(targetApp.appName) fixture app."
            )
        }
    }

    func testSwitcherPanelWindowSearchActivatesFullscreenWorkflowWindowAcrossSpaces() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first { fullscreenWindowTitle(in: $0) != nil },
            "Switcher workflow must include an app with a fullscreen fixture window"
        )
        let targetWindowTitle = try XCTUnwrap(
            fullscreenWindowTitle(in: targetApp),
            "Switcher workflow must expose the fullscreen fixture window title"
        )

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "window"
            ]
        ) { _, app in
            let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(searchInput.waitForExistence(timeout: 8))
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "The fullscreen activation scenario must start outside the target fixture app."
            )

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            app.typeText(targetWindowTitle)

            guard let result = waitForSearchWindowResult(
                in: app,
                title: targetWindowTitle,
                appName: targetApp.appName,
                timeout: 8
            ) else { return }
            let targetWindowNumber = try XCTUnwrap(
                result.windowNumber,
                "Search result \(result.identifier) did not expose a CG window number."
            )

            XCTAssertTrue(
                triggerAndWaitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout: 12,
                    trigger: {
                        confirmSwitcherSearchSelection(
                            in: app,
                            searchInput: searchInput
                        )
                    }
                ),
                "Search confirmation did not activate the fullscreen \(targetWindowTitle) fixture window."
            )
            XCTAssertTrue(
                waitForNonExistence(diagnosticsSummary, timeout: 4),
                "FlowTab panel remained visible after confirming the fullscreen window target."
            )
        }
    }

    func configuredSwitcherSpaceFixtureWorkflow(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SpaceFixtureResolvedWorkflow {
        do {
            let installedWorkflow = try SpaceFixtureResolvedWorkflow.configured(environment: environment)
            let workflow = try resolveSpaceFixtureWorkflowScenario(
                sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL,
                using: installedWorkflow
            )
            try validateSwitcherMultiAppWorkflow(workflow)
            return workflow
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            switch error {
            case .missingWorkflowPath, .workflowScenarioMissingAppVariant, .workflowScenarioBundleIdentifierMismatch:
                throw XCTSkip(
                    multiAppWorkflowSetupMessage(
                        reason: error.localizedDescription,
                        scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
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

    func configuredSwitcherRuntimeTruthWorkflow(
        sourceWorkflowURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SpaceFixtureResolvedWorkflow {
        do {
            let installedWorkflow = try SpaceFixtureResolvedWorkflow.configured(environment: environment)
            let workflow = try resolveSpaceFixtureWorkflowScenario(
                sourceWorkflowURL: sourceWorkflowURL,
                using: installedWorkflow
            )
            try validateSwitcherRuntimeTruthWorkflow(workflow, scenarioSourceURL: sourceWorkflowURL)
            return workflow
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            switch error {
            case .missingWorkflowPath, .workflowScenarioMissingAppVariant, .workflowScenarioBundleIdentifierMismatch:
                throw XCTSkip(
                    multiAppWorkflowSetupMessage(
                        reason: error.localizedDescription,
                        scenarioSourceURL: sourceWorkflowURL
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

    func fullscreenWindowTitle(in workflowApp: SpaceFixtureResolvedWorkflow.App) -> String? {
        workflowApp.fullscreenWindowTitles.first
    }

    private func validateSwitcherMultiAppWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow
    ) throws {
        guard workflow.apps.count >= 3 else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow does not include at least three apps for the switcher scenario.",
                    scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
                )
            )
        }

        guard workflow.apps.allSatisfy({ $0.windowCount >= 2 }) else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow does not provide at least two windows per app for switcher preview assertions.",
                    scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
                )
            )
        }

        guard workflow.apps.contains(where: { $0.fullscreenWindowIndex != nil }) else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow is missing the fullscreen app fixture for switcher preview coverage.",
                    scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
                )
            )
        }

        guard workflow.hasUniqueExpectedWindowTitles else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow does not define unique resolved window titles for switcher isolation assertions.",
                    scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
                )
            )
        }
    }

    private func validateSwitcherRuntimeTruthWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow,
        scenarioSourceURL: URL
    ) throws {
        guard workflow.apps.count == 1 else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow must contain exactly one fixture app for this runtime-truth scenario.",
                    scenarioSourceURL: scenarioSourceURL
                )
            )
        }

        guard workflow.apps[0].windowCount >= 2 else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow must contain at least two windows for this runtime-truth scenario.",
                    scenarioSourceURL: scenarioSourceURL
                )
            )
        }

        guard workflow.apps[0].fullscreenWindowIndex != nil else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow is missing the fullscreen sibling for this runtime-truth scenario.",
                    scenarioSourceURL: scenarioSourceURL
                )
            )
        }

        guard workflow.hasUniqueExpectedWindowTitles else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow does not define unique window titles for this runtime-truth scenario.",
                    scenarioSourceURL: scenarioSourceURL
                )
            )
        }
    }

    private func matchedWorkflowAppForVisibleSwitcherPreview(
        _ workflow: SpaceFixtureResolvedWorkflow,
        diagnosticsSummaryElement: XCUIElement,
        excludingAppIDs: Set<String> = []
    ) -> SpaceFixtureResolvedWorkflow.App? {
        let deadline = Date().addingTimeInterval(12)
        repeat {
            let selectedBundleIdentifier = switcherPanelDiagnosticsValue(
                diagnosticsSummaryElement,
                key: "selected"
            )
            let visibleTitles = switcherPreviewTitles(from: diagnosticsSummaryElement)
            for workflowApp in workflow.apps {
                guard !excludingAppIDs.contains(workflowApp.appID) else {
                    continue
                }
                guard selectedBundleIdentifier == workflowApp.identity.bundleIdentifier else {
                    continue
                }
                if Set(visibleTitles) == Set(workflowApp.expectedWindowTitles) {
                    return workflowApp
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    private func waitForFrontmostWorkflowApp(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestFrontmostBundleIdentifier: String?
        repeat {
            latestFrontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if latestFrontmostBundleIdentifier == workflowApp.identity.bundleIdentifier {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected frontmost app \(workflowApp.appName), \
            found frontmost bundle \(latestFrontmostBundleIdentifier ?? "nil").
            """
        )
        return false
    }

    private func assertSwitcherPreviewShowsOnlyExpectedTitles(
        _ expectedTitles: [String],
        in diagnosticsSummaryElement: XCUIElement,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var visibleTitles: [String] = []
        repeat {
            visibleTitles = switcherPreviewTitles(from: diagnosticsSummaryElement)
            if Set(visibleTitles) == Set(expectedTitles) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTAssertEqual(
            Set(visibleTitles),
            Set(expectedTitles),
            """
            Expected switcher preview titles \(expectedTitles.sorted()), \
            found \(visibleTitles.sorted())
            """
        )
    }

    private func waitForSwitcherMode(
        _ diagnosticsSummaryElement: XCUIElement,
        modePrefix: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let mode = switcherPanelDiagnosticsValue(diagnosticsSummaryElement, key: "mode")
            if mode.hasPrefix(modePrefix) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return false
    }

    private func assertSwitcherPreviewWindowCards(
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        selectedApp: SpaceFixtureResolvedWorkflow.App,
        excludedTitles: [String],
        previousWindowCardIdentifiers: Set<String>,
        timeout: TimeInterval = 8,
        trigger: () -> Void
    ) throws -> [SwitcherWindowCardObservation] {
        let expectation =
            FlowTabUITestSwitcherWindowCardExpectation(
                expectedTitles: selectedApp.expectedWindowTitles,
                excludedTitles: excludedTitles,
                previousWindowCardIdentifiers:
                    previousWindowCardIdentifiers
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestSwitcherWindowCardObservationOwner(
                expectation: expectation,
                acceptsResolution: {
                    triggerDidComplete
                },
                readback: {
                    FlowTabUITestSwitcherWindowCardSnapshot(
                        cards:
                            self.switcherWindowCardObservations(
                                in: app
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        trigger()
        triggerDidComplete = true

        if let evidence = owner.waitForResolution(
            timeout: timeout
        ) {
            return evidence.value.cards
        }

        XCTFail(
            """
            Switcher window-card identity watchdog expired for \
            \(selectedApp.appName).

            \(owner.diagnosticSummary)

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return owner.latestSnapshot?.cards ?? []
    }

    func searchWindowResultObservations(
        in app: XCUIApplication
    ) -> [SwitcherSearchWindowResultObservation] {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let diagnosticResults = searchWindowResultObservations(from: diagnosticsSummary)
        if !diagnosticResults.isEmpty {
            return diagnosticResults
        }
        return searchWindowResultObservationsFromElements(in: app)
    }

    func searchWindowResultObservations(
        from diagnosticsSummaryElement: XCUIElement
    ) -> [SwitcherSearchWindowResultObservation] {
        let rawValue = switcherPanelDiagnosticsValue(diagnosticsSummaryElement, key: "searchResults")
        guard !rawValue.isEmpty, rawValue != "inactive" else { return [] }

        var seenResultIDs: Set<String> = []
        return rawValue
            .split(separator: "|", omittingEmptySubsequences: true)
            .compactMap { entry -> SwitcherSearchWindowResultObservation? in
                let fields = entry.split(separator: ",", omittingEmptySubsequences: false)
                guard fields.count == 6 else { return nil }
                guard fields[1] == "window" else { return nil }

                let resultID = switcherDiagnosticsUnescaped(fields[0])
                guard seenResultIDs.insert(resultID).inserted else { return nil }
                let appID = switcherDiagnosticsUnescaped(fields[2])
                let windowID = switcherDiagnosticsUnescaped(fields[3])
                let title = switcherDiagnosticsUnescaped(fields[4])
                let appName = switcherDiagnosticsUnescaped(fields[5])
                let identifier = "flowtab.switcher.search.window.\(resultID.flowTabUITestAccessibilityIdentifierComponent)"
                return SwitcherSearchWindowResultObservation(
                    identifier: identifier,
                    searchableText: [title, appName, appID, windowID].joined(separator: "\n"),
                    resultID: resultID,
                    title: title,
                    appName: appName,
                    appID: appID,
                    windowID: windowID
                )
            }
    }

    private func searchWindowResultObservationsFromElements(in app: XCUIApplication) -> [SwitcherSearchWindowResultObservation] {
        let identifierPrefix = "flowtab.switcher.search.window."
        var seenIdentifiers: Set<String> = []
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
            .allElementsBoundByIndex
            .compactMap { element -> SwitcherSearchWindowResultObservation? in
                guard element.exists else { return nil }
                let identifier = element.identifier
                guard seenIdentifiers.insert(identifier).inserted else { return nil }

                let searchableText = [element.label, elementStringValue(element)]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                return SwitcherSearchWindowResultObservation(
                    identifier: identifier,
                    searchableText: searchableText
                )
            }
    }

    private func switcherDiagnosticsUnescaped(_ value: Substring) -> String {
        let rawValue = String(value)
        return rawValue.removingPercentEncoding ?? rawValue
    }

    func confirmSwitcherSearchSelection(in app: XCUIApplication, searchInput: XCUIElement) {
        app.typeText("\r")
        if !waitForNonExistence(searchInput, timeout: 1.2) {
            app.typeText("\r")
        }
        XCTAssertTrue(waitForNonExistence(searchInput, timeout: 4))
    }

    func switcherAppStripSummary(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String {
        "\(workflowApp.identity.bundleIdentifier):\(workflowApp.windowCount)"
    }

    func waitForSwitcherAppsSummary(
        _ diagnosticsSummaryElement: XCUIElement,
        toContain expectedEntry: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let entries = Set(
                switcherPanelDiagnosticsValue(diagnosticsSummaryElement, key: "apps")
                    .split(separator: "|")
                    .map(String.init)
            )
            if entries.contains(expectedEntry) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return false
    }

    func waitForSwitcherAppEntry(
        _ diagnosticsSummary: XCUIElement,
        bundleIdentifier: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let entries = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "apps")
                .split(separator: "|")
                .map(String.init)
            if entries.contains(where: { entry in
                entry.split(separator: ":", maxSplits: 1).first.map(String.init) == bundleIdentifier
            }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    func switcherPreviewTitles(from diagnosticsSummaryElement: XCUIElement) -> [String] {
        let rawValue = switcherPanelDiagnosticsValue(diagnosticsSummaryElement, key: "preview")
        guard rawValue != "inactive" else { return [] }
        guard let separatorRange = rawValue.range(of: "::") else { return [] }
        let titles = rawValue[separatorRange.upperBound...]
        guard !titles.isEmpty else { return [] }
        return titles.split(separator: "|").map(String.init)
    }

    func assertSwitcherSelectedWindowTitle(
        _ expectedTitle: String,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval = 4,
        message: String
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var latestTitle = switcherPanelDiagnosticsValue(
            diagnosticsSummary,
            key: "selectedWindowTitle"
        )
        repeat {
            if latestTitle == expectedTitle {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            latestTitle = switcherPanelDiagnosticsValue(
                diagnosticsSummary,
                key: "selectedWindowTitle"
            )
        } while Date() < deadline

        XCTFail(
            """
            \(message)
            Expected selected window title \(expectedTitle), found \(latestTitle).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
    }

    func assertSwitcherSelectedWindowTitle(
        oneOf expectedTitles: Set<String>,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval = 4,
        message: String
    ) {
        XCTAssertFalse(expectedTitles.isEmpty, "Expected at least one allowed selected window title.")
        let deadline = Date().addingTimeInterval(timeout)
        var latestTitle = switcherPanelDiagnosticsValue(
            diagnosticsSummary,
            key: "selectedWindowTitle"
        )
        repeat {
            if expectedTitles.contains(latestTitle) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            latestTitle = switcherPanelDiagnosticsValue(
                diagnosticsSummary,
                key: "selectedWindowTitle"
            )
        } while Date() < deadline

        XCTFail(
            """
            \(message)
            Expected selected window title in \(expectedTitles.sorted()), found \(latestTitle).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
    }

    func noisyFullscreenWorkflowPreviewContainsRequiredRealWindows(
        _ diagnosticsSummary: XCUIElement,
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> Bool {
        let previewTitles = Set(switcherPreviewTitles(from: diagnosticsSummary))
        let fullscreenTitles = Set(workflowApp.fullscreenWindowTitles)
        let standardTitles = Set(workflowApp.expectedWindowTitles).subtracting(fullscreenTitles)
        guard !fullscreenTitles.isEmpty else {
            return Set(workflowApp.expectedWindowTitles).isSubset(of: previewTitles)
        }
        return standardTitles.isSubset(of: previewTitles)
            && !previewTitles.isDisjoint(with: fullscreenTitles)
    }

    func waitForNoisyFullscreenWorkflowPreviewTitles(
        _ diagnosticsSummary: XCUIElement,
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if noisyFullscreenWorkflowPreviewContainsRequiredRealWindows(diagnosticsSummary, for: workflowApp) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    func visibleFullscreenWindowTitle(
        in diagnosticsSummary: XCUIElement,
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String? {
        let previewTitles = Set(switcherPreviewTitles(from: diagnosticsSummary))
        return workflowApp.fullscreenWindowTitles.first { previewTitles.contains($0) }
    }

    private func switcherPanelDiagnosticsDebugSummary(_ diagnosticsSummaryElement: XCUIElement) -> String {
        guard diagnosticsSummaryElement.exists else {
            return "diagnosticsSummary=<missing>"
        }

        let debugDescription = diagnosticsSummaryElement.debugDescription
        let trimmedDescription = String(debugDescription.prefix(2_000))
        return """
        panelValue=\(elementStringValue(diagnosticsSummaryElement))
        panelDebugDescription=
        \(trimmedDescription)
        """
    }

    func switcherDebugSummary(
        _ app: XCUIApplication,
        diagnosticsSummary: XCUIElement
    ) -> String {
        let appDescription = String(app.debugDescription.prefix(2_000))
        return """
        \(switcherPanelDiagnosticsDebugSummary(diagnosticsSummary))
        switcherAppDebugDescription=
        \(appDescription)
        """
    }
}
