import AppKit
import CoreGraphics
import Foundation
import XCTest

struct SwitcherSearchWindowResultObservation: Equatable {
    let identifier: String
    let searchableText: String
    let resultID: String?
    let title: String?
    let appName: String?
    let appID: String?
    let windowID: String?

    init(
        identifier: String,
        searchableText: String,
        resultID: String? = nil,
        title: String? = nil,
        appName: String? = nil,
        appID: String? = nil,
        windowID: String? = nil
    ) {
        self.identifier = identifier
        self.searchableText = searchableText
        self.resultID = resultID
        self.title = title
        self.appName = appName
        self.appID = appID
        self.windowID = windowID
    }

    var windowNumber: CGWindowID? {
        if let windowID, let rawWindowID = windowID.split(separator: ":").last, let parsed = UInt32(rawWindowID) {
            return CGWindowID(parsed)
        }
        guard let rawWindowID = identifier.split(separator: "-").last else { return nil }
        guard let parsed = UInt32(rawWindowID) else { return nil }
        return CGWindowID(parsed)
    }

    func matches(title: String, appName: String) -> Bool {
        if let observedTitle = self.title, let observedAppName = self.appName {
            return observedTitle == title && observedAppName == appName
        }
        return searchableText.localizedCaseInsensitiveContains(title)
            && searchableText.localizedCaseInsensitiveContains(appName)
    }
}

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

                let windowCards = try assertSwitcherPreviewWindowCards(
                    in: app,
                    diagnosticsSummary: diagnosticsSummary,
                    selectedApp: selectedApp,
                    excludedTitles: workflow.otherExpectedWindowTitles(excluding: selectedApp.appID),
                    previousWindowCardIdentifiers: previousWindowCardIdentifiers
                )
                previousWindowCardIdentifiers = Set(windowCards.map(\.identifier))

                app.typeKey(.upArrow, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }

            XCTAssertEqual(Set(observedAppIDs), Set(workflow.apps.map(\.appID)))
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

            confirmSwitcherSearchSelection(in: app, searchInput: searchInput)
            XCTAssertTrue(
                waitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout: 10
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

            confirmSwitcherSearchSelection(in: app, searchInput: searchInput)
            XCTAssertTrue(
                waitForNonExistence(diagnosticsSummary, timeout: 4),
                "FlowTab panel remained visible after confirming the fullscreen window target."
            )
            XCTAssertTrue(
                waitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout: 12
                ),
                "Search confirmation did not activate the fullscreen \(targetWindowTitle) fixture window."
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

    private func assertSwitcherPreviewWindowCards(
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        selectedApp: SpaceFixtureResolvedWorkflow.App,
        excludedTitles: [String],
        previousWindowCardIdentifiers: Set<String>,
        timeout: TimeInterval = 8
    ) throws -> [SwitcherWindowCardObservation] {
        let deadline = Date().addingTimeInterval(timeout)
        var latestCards: [SwitcherWindowCardObservation] = []
        repeat {
            latestCards = switcherWindowCardObservations(in: app)
            let latestTitles = Set(latestCards.map(\.title))
            let expectedTitles = Set(selectedApp.expectedWindowTitles)
            let currentCardIdentifiers = Set(latestCards.map(\.identifier))
            let oldCardsWereRemoved = previousWindowCardIdentifiers.isEmpty
                || currentCardIdentifiers.isDisjoint(with: previousWindowCardIdentifiers)
            let excludedTitlesAreAbsent = latestTitles.isDisjoint(with: Set(excludedTitles))

            if latestTitles == expectedTitles,
               latestCards.count == selectedApp.expectedWindowTitles.count,
               excludedTitlesAreAbsent,
               oldCardsWereRemoved {
                return latestCards
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTAssertEqual(
            Set(latestCards.map(\.title)),
            Set(selectedApp.expectedWindowTitles),
            """
            Expected real switcher window card anchors for \(selectedApp.appName) to expose \
            \(selectedApp.expectedWindowTitles.sorted()), found \(latestCards.map(\.title).sorted()).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        XCTAssertTrue(
            Set(latestCards.map(\.title)).isDisjoint(with: Set(excludedTitles)),
            """
            Switcher preview kept window card anchors from another workflow app.

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        XCTAssertTrue(
            previousWindowCardIdentifiers.isEmpty
                || Set(latestCards.map(\.identifier)).isDisjoint(with: previousWindowCardIdentifiers),
            """
            Switcher preview kept stale window card anchors after switching apps.

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )

        return latestCards
    }

    func waitForSearchWindowResult(
        in app: XCUIApplication,
        title: String,
        appName: String,
        timeout: TimeInterval
    ) -> SwitcherSearchWindowResultObservation? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestResults: [SwitcherSearchWindowResultObservation] = []
        repeat {
            latestResults = searchWindowResultObservations(in: app)
            if let result = latestResults.first(where: { $0.matches(title: title, appName: appName) }) {
                return result
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected a window-scope search result for \(appName) / \(title), \
            found \(latestResults.map(\.identifier).sorted()).
            """
        )
        return nil
    }

    private func searchWindowResultObservations(in app: XCUIApplication) -> [SwitcherSearchWindowResultObservation] {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let diagnosticResults = searchWindowResultObservations(from: diagnosticsSummary)
        if !diagnosticResults.isEmpty {
            return diagnosticResults
        }
        return searchWindowResultObservationsFromHierarchy(in: app)
    }

    private func searchWindowResultObservations(
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
                let identifier = "flowtab.switcher.search.window.\(searchResultAccessibilitySlug(resultID))"
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

    private func searchWindowResultObservationsFromHierarchy(in app: XCUIApplication) -> [SwitcherSearchWindowResultObservation] {
        let hierarchyDescription = app.debugDescription
        let lines = hierarchyDescription.components(separatedBy: .newlines)
        let identifierPrefix = "flowtab.switcher.search.window."
        let escapedPrefix = NSRegularExpression.escapedPattern(for: identifierPrefix)
        let identifierPattern = "identifier: ['\"](" + escapedPrefix + "[^'\"]*)['\"]"
        guard let identifierRegex = try? NSRegularExpression(pattern: identifierPattern) else {
            return []
        }

        var seenIdentifiers: Set<String> = []
        return lines.indices.compactMap { index in
            guard let identifier = searchWindowResultIdentifier(in: lines[index], regex: identifierRegex) else {
                return nil
            }
            guard seenIdentifiers.insert(identifier).inserted else { return nil }

            let contextStart = max(0, index - 2)
            let contextEnd = min(lines.count - 1, index + 6)
            let searchableText = lines[contextStart...contextEnd]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return SwitcherSearchWindowResultObservation(
                identifier: identifier,
                searchableText: searchableText
            )
        }
    }

    private func searchWindowResultIdentifier(
        in line: String,
        regex: NSRegularExpression
    ) -> String? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let identifierRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[identifierRange])
    }

    private func switcherDiagnosticsUnescaped(_ value: Substring) -> String {
        let rawValue = String(value)
        return rawValue.removingPercentEncoding ?? rawValue
    }

    private func searchResultAccessibilitySlug(_ value: String) -> String {
        let replaced = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return replaced.isEmpty ? "item" : replaced
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

    func waitForSwitcherSearchSelectedResult(
        _ expectedResultID: String,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let latestValue = switcherPanelDiagnosticsValue(
                diagnosticsSummary,
                key: "searchSelectedResult"
            )
            let decoded = latestValue.removingPercentEncoding ?? latestValue
            if decoded == expectedResultID {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    func switcherPanelDiagnosticsValue(
        _ diagnosticsSummaryElement: XCUIElement,
        key: String
    ) -> String {
        let prefix = "\(key)="
        for source in [elementStringValue(diagnosticsSummaryElement), diagnosticsSummaryElement.debugDescription] {
            guard let valueStart = source.range(of: prefix)?.upperBound else { continue }
            let remaining = source[valueStart...]
            guard let valueEnd = remaining.firstIndex(of: ";") else { return String(remaining) }
            return String(remaining[..<valueEnd])
        }
        return ""
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
