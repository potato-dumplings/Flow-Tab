import AppKit
import CoreGraphics
import XCTest

private struct RuntimeTruthWindowSelection: Equatable {
    let title: String
    let windowNumber: CGWindowID
}

extension FlowTabUITests {
    func testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first { fullscreenWindowTitle(in: $0) != nil },
            "Switcher workflow must include an app with a fullscreen fixture window"
        )
        let fullscreenTitle = try XCTUnwrap(fullscreenWindowTitle(in: targetApp))
        let standardTitle = try XCTUnwrap(firstStandardWorkflowWindowTitle(in: targetApp))

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"],
            waitsForFullscreenMarkers: false,
            suppressesAppAccessibilityChildren: true
        ) { _, app in
            var diagnosticsSummary = assertGlobalSwitcherWindowStateReady(for: targetApp, in: app)
            let fullscreenSelection = try selectGlobalSwitcherWindow(
                title: fullscreenTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary
            )

            app.typeText("\r")
            XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: fullscreenSelection.windowNumber,
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: 12
                )
            )

            diagnosticsSummary = relaunchGlobalSwitcher(app, for: targetApp)
            let standardSelection = try selectGlobalSwitcherWindow(
                title: standardTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary
            )

            app.typeText("\r")
            XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
        }
    }

    func testSwitcherPanelWindowSearchRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first { fullscreenWindowTitle(in: $0) != nil },
            "Switcher workflow must include an app with a fullscreen fixture window"
        )
        let fullscreenTitle = try XCTUnwrap(fullscreenWindowTitle(in: targetApp))
        let standardTitle = try XCTUnwrap(firstStandardWorkflowWindowTitle(in: targetApp))

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "window"
            ],
            waitsForFullscreenMarkers: false,
            suppressesAppAccessibilityChildren: true
        ) { _, app in
            var searchInput = assertWindowSearchReady(in: app)
            let fullscreenSelection = try searchAndSelectWorkflowWindow(
                title: fullscreenTitle,
                app: targetApp,
                in: app
            )

            confirmSwitcherSearchSelection(in: app, searchInput: searchInput)
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: fullscreenSelection.windowNumber,
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: 12
                )
            )

            searchInput = relaunchWindowSearch(app)
            let standardSelection = try searchAndSelectWorkflowWindow(
                title: standardTitle,
                app: targetApp,
                in: app
            )

            confirmSwitcherSearchSelection(in: app, searchInput: searchInput)
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
        }
    }

    private func assertGlobalSwitcherWindowStateReady(
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication
    ) -> XCUIElement {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForSwitcherAppsSummary(
                diagnosticsSummary,
                toContain: switcherAppStripSummary(for: workflowApp),
                timeout: 8
            )
        )

        selectSwitcherWorkflowApp(workflowApp, in: app, diagnosticsSummary: diagnosticsSummary)

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForSwitcherDiagnosticsValue(
                diagnosticsSummary,
                key: "mode",
                toHavePrefix: "windowCycle",
                timeout: 4
            ),
            """
            Option+Tab switcher did not enter app window state.

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        XCTAssertTrue(
            waitForSwitcherPreviewTitles(
                diagnosticsSummary,
                toEqual: Set(workflowApp.expectedWindowTitles),
                timeout: 8
            ),
            """
            Option+Tab app window state did not expose the expected real windows.

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return diagnosticsSummary
    }

    private func selectGlobalSwitcherWindow(
        title: String,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement
    ) throws -> RuntimeTruthWindowSelection {
        let attempts = max(1, switcherPreviewTitles(from: diagnosticsSummary).count + 3)
        var latestTitle = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindowTitle")
        var latestWindowID = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindow")

        if latestTitle == title {
            return try runtimeTruthWindowSelection(title: latestTitle, windowID: latestWindowID)
        }

        for _ in 0..<attempts {
            app.typeKey(.rightArrow, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            latestTitle = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindowTitle")
            latestWindowID = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindow")
            if latestTitle == title {
                return try runtimeTruthWindowSelection(title: latestTitle, windowID: latestWindowID)
            }
        }

        XCTFail(
            """
            Option+Tab window state did not select \(title).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return try runtimeTruthWindowSelection(title: latestTitle, windowID: latestWindowID)
    }

    private func searchAndSelectWorkflowWindow(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication
    ) throws -> RuntimeTruthWindowSelection {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText(title)

        let result = try XCTUnwrap(
            waitForSearchWindowResult(
                in: app,
                title: title,
                appName: workflowApp.appName,
                timeout: 8
            )
        )
        let windowNumber = try XCTUnwrap(
            workflowCGWindowID(fromSearchResultIdentifier: result.identifier),
            "Search result \(result.identifier) did not expose a CG window number."
        )
        return RuntimeTruthWindowSelection(
            title: title,
            windowNumber: windowNumber
        )
    }

    private func runtimeTruthWindowSelection(
        title: String,
        windowID: String
    ) throws -> RuntimeTruthWindowSelection {
        let windowNumber: CGWindowID? = windowID.split(separator: ":").last.flatMap { UInt32($0) }
        return RuntimeTruthWindowSelection(
            title: title,
            windowNumber: try XCTUnwrap(
                windowNumber,
                "Selected window id \(windowID) did not expose a CG window number."
            )
        )
    }

    private func firstStandardWorkflowWindowTitle(
        in workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String? {
        let fullscreenTitle = fullscreenWindowTitle(in: workflowApp)
        return workflowApp.expectedWindowTitles.first { $0 != fullscreenTitle }
    }

    private func relaunchGlobalSwitcher(
        _ app: XCUIApplication,
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> XCUIElement {
        relaunchFlowTabUITestApplication(app)
        return assertGlobalSwitcherWindowStateReady(for: workflowApp, in: app)
    }

    private func relaunchWindowSearch(_ app: XCUIApplication) -> XCUIElement {
        relaunchFlowTabUITestApplication(app)
        return assertWindowSearchReady(in: app)
    }

    private func relaunchFlowTabUITestApplication(_ app: XCUIApplication) {
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
        }
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))
    }

    private func assertWindowSearchReady(in app: XCUIApplication) -> XCUIElement {
        let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(searchInput.waitForExistence(timeout: 8))
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
        return searchInput
    }

    private func waitForSwitcherDiagnosticsValue(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        toHavePrefix expectedValuePrefix: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if switcherPanelDiagnosticsValue(diagnosticsSummary, key: key).hasPrefix(expectedValuePrefix) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func waitForSwitcherPreviewTitles(
        _ diagnosticsSummary: XCUIElement,
        toEqual expectedTitles: Set<String>,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if Set(switcherPreviewTitles(from: diagnosticsSummary)) == expectedTitles {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }
}
