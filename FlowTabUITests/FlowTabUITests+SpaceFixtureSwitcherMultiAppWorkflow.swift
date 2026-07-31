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
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level", "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.global, traceLabel: "multi-app-preview.initial")
            assertSwitcherAppStripContainsWorkflowApp(
                workflow.apps[0], in: app,
                diagnosticsSummary: diagnosticsSummary
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

                guard exitSwitcherPreview(selectedApp, in: app, diagnostics: diagnosticsSummary) else { return }
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

                guard exitSwitcherPreview(selectedApp, in: app, diagnostics: diagnosticsSummary) else { return }
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

            let targetProcessIdentifier =
                try runningWorkflowApplicationProcessIdentifier(targetApp)
            let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
            selectSwitcherWorkflowApp(targetApp, in: app, diagnosticsSummary: diagnosticsSummary)
            app.activate()
            guard enterSwitcherPreview(targetApp, in: app, diagnostics: diagnosticsSummary) else { return }
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
            guard requireActiveSwitcherPreview(targetApp, diagnostics: diagnosticsSummary) else { return }
            waitForRuntimeLogFiles(
                containing: [
                    "runtimeAXDestroyed appID=\(targetApp.identity.bundleIdentifier)",
                    "affectedCGWindowID="
                ],
                since: mutationLogSnapshot,
                timeout: 8
            )
            assertWorkflowApplicationProcessRemainsRunning(
                targetApp,
                processIdentifier: targetProcessIdentifier
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

            let targetProcessIdentifier =
                try runningWorkflowApplicationProcessIdentifier(targetApp)
            let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
            selectSwitcherWorkflowApp(targetApp, in: app, diagnosticsSummary: diagnosticsSummary)
            app.activate()
            guard enterSwitcherPreview(targetApp, in: app, diagnostics: diagnosticsSummary) else { return }
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
            guard requireActiveSwitcherPreview(targetApp, diagnostics: diagnosticsSummary) else { return }
            waitForRuntimeLogFiles(
                containing: [
                    "runtimeAXDestroyed appID=\(targetApp.identity.bundleIdentifier)",
                    "affectedCGWindowID="
                ],
                since: mutationLogSnapshot,
                timeout: 8
            )
            assertWorkflowApplicationProcessRemainsRunning(
                targetApp,
                processIdentifier: targetProcessIdentifier
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

    func testSwitcherPanelWindowSearchFindsAndActivatesRealWorkflowWindow() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetWindowTitle = "Docs"
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.expectedWindowTitles.contains(targetWindowTitle) },
            "Switcher workflow must include a real fixture window titled \(targetWindowTitle)"
        )

        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "window"
            ]
                + FlowTabUITestSearchInputReadinessPolicy
                    .applicationEvidenceLaunchArguments
        ) { _, app in
            let searchInput =
                requireInitialFlowTabSearchInput(
                    in: app,
                    observedBy: readiness
                )

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

        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "app"
            ]
                + FlowTabUITestSearchInputReadinessPolicy
                    .applicationEvidenceLaunchArguments
        ) { _, app in
            let searchInput =
                requireInitialFlowTabSearchInput(
                    in: app,
                    observedBy: readiness
                )
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "The app-scope activation scenario must start outside the target fixture app."
            )

            app.typeText(targetApp.identity.switcherSearchQuery)

            let result = element(
                in: app,
                identifier: targetApp.identity.switcherSearchAppAccessibilityIdentifier
            )
            XCTAssertTrue(
                result.waitForExistence(timeout: 8),
                "FlowTab did not expose \(targetApp.appName) as a real app-scope search result."
            )

            assertTriggerMakesApplicationFrontmost(
                targetApp.identity.bundleIdentifier,
                timeout: 10,
                message:
                    "Search confirmation did not activate "
                    + "the \(targetApp.appName) fixture app."
            ) {
                confirmSwitcherSearchSelection(
                    in: app,
                    searchInput: searchInput
                )
            }
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

        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "window"
            ]
                + FlowTabUITestSearchInputReadinessPolicy
                    .applicationEvidenceLaunchArguments
        ) { _, app in
            let searchInput =
                requireInitialFlowTabSearchInput(
                    in: app,
                    observedBy: readiness
                )
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "The fullscreen activation scenario must start outside the target fixture app."
            )

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
        searchWindowResultObservations(
            inDiagnosticsProjection:
                switcherPanelDiagnosticsValue(
                    diagnosticsSummaryElement,
                    key: "searchResults"
                )
        )
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
