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
            flowTabAdditionalArguments: runtimeTruthSwitcherLaunchArguments(),
            waitsForFullscreenMarkers: false,
            suppressesAppAccessibilityChildren: true,
            validatesPermissionsBeforeFixtureLaunch: true,
            preservesDesktopAfterFullscreen: false,
            prelaunchesFlowTabBeforeFixture: true,
            beforeFlowTabLaunch: { _ in
                self.logWorkflowSpaceObservation("option.beforeFlowTabLaunch", app: targetApp)
                _ = try XCTUnwrap(
                    self.waitForFrontmostWorkflowSpaceCGWindow(
                        title: fullscreenTitle,
                        app: targetApp,
                        timeout: 12
                    ),
                    "Option+Tab roundtrip must start with the fullscreen sibling frontmost."
                )
            },
            flowTabLaunchTraceLabel: "option",
            afterFlowTabLaunch: { _, _ in
                self.logWorkflowSpaceObservation("option.afterFlowTabLaunch", app: targetApp)
            }
        ) { _, app in
            logWorkflowSpaceObservation("option.beforeTrigger", app: targetApp)
            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.global, traceLabel: "option")
            var diagnosticsSummary = try assertGlobalSwitcherWindowStateReady(for: targetApp, in: app)
            logWorkflowSpaceObservation("option.afterWindowStateReady", app: targetApp)
            XCTAssertTrue(
                waitForActiveSpaceWorkflowCGWindow(
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: 4
                ),
                "Option+Tab first window-state phase must open from the fullscreen sibling's Space."
            )
            assertSwitcherSelectedWindowTitle(
                fullscreenTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                message: "Option+Tab roundtrip must enter the first window-state phase on the fullscreen sibling."
            )
            let standardSelection = try selectGlobalSwitcherWindow(
                title: standardTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary
            )

            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.confirm, traceLabel: "option.confirmStandard")
            XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
            logWorkflowSpaceObservation("option.afterStandardConfirm", app: targetApp)

            diagnosticsSummary = try relaunchGlobalSwitcher(app, for: targetApp)
            logWorkflowSpaceObservation("option.afterSecondWindowStateReady", app: targetApp)
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    timeout: 4
                ),
                "Option+Tab second window-state phase must open from the normal sibling's Space."
            )
            assertSwitcherSelectedWindowTitle(
                standardTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                message: "Option+Tab roundtrip must enter the second window-state phase on the normal sibling."
            )
            let fullscreenSelection = try selectGlobalSwitcherWindow(
                title: fullscreenTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary
            )

            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.confirm, traceLabel: "option.confirmFullscreen")
            XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: fullscreenSelection.windowNumber,
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
            logWorkflowSpaceObservation("option.afterFullscreenConfirm", app: targetApp)
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
            flowTabAdditionalArguments: runtimeTruthSwitcherLaunchArguments(
                additionalArguments: [
                    "-searchDefaultScope",
                    "window"
                ]
            ),
            waitsForFullscreenMarkers: false,
            suppressesAppAccessibilityChildren: true,
            validatesPermissionsBeforeFixtureLaunch: true,
            preservesDesktopAfterFullscreen: false,
            prelaunchesFlowTabBeforeFixture: true,
            beforeFlowTabLaunch: { _ in
                self.logWorkflowSpaceObservation("search.beforeFlowTabLaunch", app: targetApp)
                _ = try XCTUnwrap(
                    self.waitForFrontmostWorkflowSpaceCGWindow(
                        title: fullscreenTitle,
                        app: targetApp,
                        timeout: 12
                    ),
                    "Window search roundtrip must start with the fullscreen sibling frontmost."
                )
            },
            flowTabLaunchTraceLabel: "search",
            afterFlowTabLaunch: { _, _ in
                self.logWorkflowSpaceObservation("search.afterFlowTabLaunch", app: targetApp)
            }
        ) { _, app in
            logWorkflowSpaceObservation("search.beforeTrigger", app: targetApp)
            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.search, traceLabel: "search")
            var searchInput = assertWindowSearchReady(in: app)
            logWorkflowSpaceObservation("search.afterSearchReady", app: targetApp)
            XCTAssertTrue(
                waitForActiveSpaceWorkflowCGWindow(
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: 4
                ),
                "Window search first phase must open from the fullscreen sibling's Space."
            )
            let standardSelection = try searchAndSelectWorkflowWindow(
                title: standardTitle,
                app: targetApp,
                in: app
            )

            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.searchConfirm, traceLabel: "search.confirmStandard")
            XCTAssertTrue(waitForNonExistence(searchInput, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
            logWorkflowSpaceObservation("search.afterStandardConfirm", app: targetApp)

            searchInput = relaunchWindowSearch(app)
            logWorkflowSpaceObservation("search.afterSecondSearchReady", app: targetApp)
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    timeout: 4
                ),
                "Window search second phase must open from the normal sibling's Space."
            )
            let fullscreenSelection = try searchAndSelectWorkflowWindow(
                title: fullscreenTitle,
                app: targetApp,
                in: app
            )

            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.searchConfirm, traceLabel: "search.confirmFullscreen")
            XCTAssertTrue(waitForNonExistence(searchInput, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: fullscreenSelection.windowNumber,
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
            logWorkflowSpaceObservation("search.afterFullscreenConfirm", app: targetApp)
        }
    }

    private func assertGlobalSwitcherWindowStateReady(
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication
    ) throws -> XCUIElement {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForSwitcherAppsSummary(
                diagnosticsSummary,
                toContain: switcherAppStripSummary(for: workflowApp),
                timeout: 8
            )
        )

        logFlowTabUITestTrace(
            "[selectWorkflowApp.direct] target=\(workflowApp.identity.bundleIdentifier) selected=\(switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected"))"
        )
        try postFlowTabUITestSelectSwitcherAppAndWaitForDelivery(
            bundleIdentifier: workflowApp.identity.bundleIdentifier,
            traceLabel: "option.selectApp"
        )
        assertSwitcherSelectedApp(
            workflowApp,
            in: app,
            diagnosticsSummary: diagnosticsSummary,
            stage: "before entering Option+Tab window state"
        )

        logWorkflowSpaceObservation("option.beforeEnterWindowState", app: workflowApp)
        postFlowTabUITestSwitcherCommandAndWaitForDelivery(.advanceDown, traceLabel: "option.enterWindowState")
        logWorkflowSpaceObservation("option.afterEnterWindowState", app: workflowApp)
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
        assertSwitcherSelectedApp(
            workflowApp,
            in: app,
            diagnosticsSummary: diagnosticsSummary,
            stage: "after entering Option+Tab window state"
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

    private func assertSwitcherSelectedApp(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        stage: String
    ) {
        XCTAssertTrue(
            waitForSwitcherDiagnosticsValue(
                diagnosticsSummary,
                key: "selected",
                toEqual: workflowApp.identity.bundleIdentifier,
                timeout: 4
            ),
            """
            Option+Tab selected the wrong app \(stage). Expected \
            \(workflowApp.identity.bundleIdentifier).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
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

        for attempt in 0..<attempts {
            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.advanceRight, traceLabel: "option.selectWindow")
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            latestTitle = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindowTitle")
            latestWindowID = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindow")
            logFlowTabUITestTrace(
                "[option.selectAttempt.\(attempt + 1)] target=\(title) selected=\(latestTitle) windowID=\(latestWindowID)"
            )
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
        try postFlowTabUITestSwitcherSearchQueryAndWaitForDelivery(title, traceLabel: "search.query")

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

    private func runtimeTruthSwitcherLaunchArguments(
        additionalArguments: [String] = []
    ) -> [String] {
        [
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-suppress-home-on-launch",
            "--flowtab-ui-suppress-panel-activation",
            "--flowtab-ui-runtime-log-level", "DEBUG",
            "--flowtab-ui-enable-verbose-logs",
            "-windowLayerAutoEnterDelay", "30.0"
        ] + FlowTabUITestSwitcherCommandPayload.launchArguments + additionalArguments
    }

    private func relaunchGlobalSwitcher(
        _ app: XCUIApplication,
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) throws -> XCUIElement {
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.global, traceLabel: "option.relaunch")
        return try assertGlobalSwitcherWindowStateReady(for: workflowApp, in: app)
    }

    private func relaunchWindowSearch(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.search, traceLabel: "search.relaunch")
        return assertWindowSearchReady(in: app)
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

    private func waitForSwitcherDiagnosticsValue(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        toEqual expectedValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if switcherPanelDiagnosticsValue(diagnosticsSummary, key: key) == expectedValue {
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
