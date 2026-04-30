import AppKit
import Foundation
import XCTest

private struct SwitcherWindowCardObservation: Equatable {
    let identifier: String
    let title: String
    let appName: String
}

private struct SwitcherSearchWindowResultObservation: Equatable {
    let identifier: String
    let searchableText: String

    func matches(title: String, appName: String) -> Bool {
        searchableText.localizedCaseInsensitiveContains(title)
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
            let diagnosticsSummary = element(in: app, identifier: "flowtab.testing.switcher.summary")

            for workflowApp in workflow.apps {
                assertSwitcherAppStripContainsWorkflowApp(
                    workflowApp,
                    in: app,
                    diagnosticsSummary: diagnosticsSummary
                )
                if diagnosticsSummary.exists {
                    XCTAssertTrue(
                        waitForSwitcherAppsSummary(
                            diagnosticsSummary,
                            toContain: switcherAppStripSummary(for: workflowApp),
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
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: "flowtab.testing.switcher.summary")
            XCTAssertTrue(
                element(
                    in: app,
                    identifier: workflow.apps[0].identity.switcherAppAccessibilityIdentifier
                ).waitForExistence(timeout: 8)
            )
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))

            var observedAppIDs: [String] = []
            for index in workflow.apps.indices {
                if index > 0 {
                    app.typeKey(.rightArrow, modifierFlags: [])
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                }

                app.typeKey(.downArrow, modifierFlags: [])
                let selectedApp = try XCTUnwrap(
                    matchedWorkflowAppForVisibleSwitcherPreview(
                        workflow,
                        diagnosticsSummaryElement: diagnosticsSummary,
                        excludingAppIDs: Set(observedAppIDs)
                    ),
                    """
                    Switcher preview did not stabilize to a single workflow app window set.

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
            let diagnosticsSummary = element(in: app, identifier: "flowtab.testing.switcher.summary")
            XCTAssertTrue(
                element(
                    in: app,
                    identifier: workflow.apps[0].identity.switcherAppAccessibilityIdentifier
                ).waitForExistence(timeout: 8)
            )
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))

            var observedAppIDs: [String] = []
            var previousWindowCardIdentifiers: Set<String> = []
            for index in workflow.apps.indices {
                if index > 0 {
                    app.typeKey(.rightArrow, modifierFlags: [])
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                }

                app.typeKey(.downArrow, modifierFlags: [])
                let selectedApp = try XCTUnwrap(
                    matchedWorkflowAppForVisibleSwitcherPreview(
                        workflow,
                        diagnosticsSummaryElement: diagnosticsSummary,
                        excludingAppIDs: Set(observedAppIDs)
                    ),
                    """
                    Switcher preview did not stabilize to a single workflow app window set.

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

            let result = waitForSearchWindowResult(
                in: app,
                title: targetWindowTitle,
                appName: targetApp.appName,
                timeout: 8
            )
            XCTAssertNotNil(
                result,
                "FlowTab did not expose \(targetWindowTitle) as a real window-scope search result."
            )

            confirmSwitcherSearchSelection(in: app, searchInput: searchInput)
            XCTAssertTrue(
                waitForFocusedWorkflowWindow(
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
            let diagnosticsSummary = element(in: app, identifier: "flowtab.testing.switcher.summary")
            XCTAssertTrue(searchInput.waitForExistence(timeout: 8))
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "The fullscreen activation scenario must start outside the target fixture app."
            )

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            app.typeText(targetWindowTitle)

            let result = waitForSearchWindowResult(
                in: app,
                title: targetWindowTitle,
                appName: targetApp.appName,
                timeout: 8
            )
            XCTAssertNotNil(
                result,
                "FlowTab did not expose \(targetWindowTitle) as a fullscreen window-scope search result."
            )

            confirmSwitcherSearchSelection(in: app, searchInput: searchInput)
            XCTAssertTrue(
                waitForNonExistence(diagnosticsSummary, timeout: 4),
                "FlowTab panel remained visible after confirming the fullscreen window target."
            )
            XCTAssertTrue(
                waitForFocusedWorkflowWindow(
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout: 12
                ),
                "Search confirmation did not activate the fullscreen \(targetWindowTitle) fixture window."
            )
        }
    }

    private func configuredSwitcherSpaceFixtureWorkflow(
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

    private func fullscreenWindowTitle(in workflowApp: SpaceFixtureResolvedWorkflow.App) -> String? {
        guard let fullscreenWindowIndex = workflowApp.fullscreenWindowIndex else { return nil }
        let titleIndex = fullscreenWindowIndex - 1
        guard workflowApp.expectedWindowTitles.indices.contains(titleIndex) else { return nil }
        return workflowApp.expectedWindowTitles[titleIndex]
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
            let allCardsBelongToSelectedApp = latestCards.allSatisfy { $0.appName == selectedApp.appName }
            let excludedTitlesAreAbsent = latestTitles.isDisjoint(with: Set(excludedTitles))

            if latestTitles == expectedTitles,
               latestCards.count == selectedApp.expectedWindowTitles.count,
               allCardsBelongToSelectedApp,
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
            latestCards.allSatisfy { $0.appName == selectedApp.appName },
            """
            Expected real switcher window card anchors to belong to \(selectedApp.appName), \
            found \(latestCards.map { "\($0.title)=\($0.appName)" }.sorted()).

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

    private func switcherWindowCardObservations(in app: XCUIApplication) -> [SwitcherWindowCardObservation] {
        app.descendants(matching: .any).allElementsBoundByIndex.compactMap { element in
            guard element.identifier.hasPrefix("flowtab.switcher.window.") else { return nil }
            guard element.exists else { return nil }
            let title = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return SwitcherWindowCardObservation(
                identifier: element.identifier,
                title: title,
                appName: elementStringValue(element).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func waitForSearchWindowResult(
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
        app.descendants(matching: .any).allElementsBoundByIndex.compactMap { element in
            guard element.identifier.hasPrefix("flowtab.switcher.search.window.") else { return nil }
            guard element.exists else { return nil }
            let debugSummary = String(element.debugDescription.prefix(1_200))
            let searchableText = [
                element.label,
                elementStringValue(element),
                debugSummary
            ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

            return SwitcherSearchWindowResultObservation(
                identifier: element.identifier,
                searchableText: searchableText
            )
        }
    }

    private func confirmSwitcherSearchSelection(in app: XCUIApplication, searchInput: XCUIElement) {
        app.typeText("\r")
        if !waitForNonExistence(searchInput, timeout: 1.2) {
            app.typeText("\r")
        }
        XCTAssertTrue(waitForNonExistence(searchInput, timeout: 4))
    }

    private func switcherAppStripSummary(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String {
        "\(workflowApp.identity.bundleIdentifier):\(workflowApp.windowCount)"
    }

    private func waitForSwitcherAppsSummary(
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

    private func switcherPreviewTitles(from diagnosticsSummaryElement: XCUIElement) -> [String] {
        let rawValue = switcherPanelDiagnosticsValue(diagnosticsSummaryElement, key: "preview")
        guard rawValue != "inactive" else { return [] }
        guard let separatorRange = rawValue.range(of: "::") else { return [] }
        let titles = rawValue[separatorRange.upperBound...]
        guard !titles.isEmpty else { return [] }
        return titles.split(separator: "|").map(String.init)
    }

    private func switcherPanelDiagnosticsValue(
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

    private func switcherDebugSummary(
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
