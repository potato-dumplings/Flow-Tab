import AppKit
import CoreGraphics
import XCTest

struct RuntimeTruthWindowSelection: Equatable {
    let title: String
    let windowNumber: CGWindowID
}

extension FlowTabUITests {
    func testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherRuntimeTruthWorkflow(
            sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.optionTabWindowStateRuntimeTruthWorkflowSourceURL
        )
        try runSwitcherPanelOptionTabWindowStateRoundTrip(
            workflow,
            traceLabel: "option"
        )
    }

    func testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherRuntimeTruthWorkflow(
            sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.optionTabWindowStateNoisyRuntimeTruthWorkflowSourceURL
        )
        try runSwitcherPanelOptionTabWindowStateRoundTrip(
            workflow,
            traceLabel: "option.noisy",
            allowsNoisyCGSiblings: true
        )
    }

    private func runSwitcherPanelOptionTabWindowStateRoundTrip(
        _ workflow: SpaceFixtureResolvedWorkflow,
        traceLabel: String,
        allowsNoisyCGSiblings: Bool = false
    ) throws {
        let targetApp = try XCTUnwrap(
            workflow.apps.first { fullscreenWindowTitle(in: $0) != nil },
            "Switcher workflow must include an app with a fullscreen fixture window"
        )
        let fullscreenTitle = try XCTUnwrap(fullscreenWindowTitle(in: targetApp))
        let standardTitle = try XCTUnwrap(firstStandardWorkflowWindowTitle(in: targetApp))
        let runtimeLogSnapshot = makeRuntimeLogFileSnapshot()
        defer { runtimeLogSnapshot.cancel() }
        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: runtimeTruthSwitcherLaunchArguments(),
            waitsForFullscreenMarkers: false,
            suppressesAppAccessibilityChildren: true,
            validatesPermissionsBeforeFixtureLaunch: true,
            preservesDesktopAfterFullscreen: false,
            prelaunchesFlowTabBeforeFixture: true,
            beforeFlowTabLaunch: { _ in
                self.logWorkflowSpaceObservation("\(traceLabel).beforeFlowTabLaunch", app: targetApp)
                if allowsNoisyCGSiblings {
                    XCTAssertTrue(
                        self.waitForWorkflowSpaceContainingCGWindow(
                            title: fullscreenTitle,
                            app: targetApp,
                            timeout: FlowTabUITestRuntimeTruthWatchdogPolicy.optionTabInitialTopology
                        ),
                        "Option+Tab noisy roundtrip must start on a Space containing the fullscreen sibling."
                    )
                } else {
                    _ = try XCTUnwrap(
                        self.waitForFrontmostWorkflowSpaceCGWindow(
                            title: fullscreenTitle,
                            app: targetApp,
                            timeout: FlowTabUITestRuntimeTruthWatchdogPolicy.optionTabInitialTopology
                        ),
                        "Option+Tab roundtrip must start with the fullscreen sibling frontmost."
                    )
                }
            },
            flowTabLaunchTraceLabel: traceLabel,
            afterFlowTabLaunch: { _, _ in
                self.logWorkflowSpaceObservation("\(traceLabel).afterFlowTabLaunch", app: targetApp)
            }
        ) { _, app in
            logWorkflowSpaceObservation("\(traceLabel).beforeTrigger", app: targetApp)
            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.global, traceLabel: traceLabel)
            var diagnosticsSummary = try assertGlobalSwitcherWindowStateReady(
                for: targetApp,
                in: app,
                traceLabel: traceLabel,
                allowsNoisyCGSiblings: allowsNoisyCGSiblings
            )
            if allowsNoisyCGSiblings {
                try runNoisyOptionTabWindowStateRoundTrip(
                    app: app,
                    targetApp: targetApp,
                    initialDiagnosticsSummary: diagnosticsSummary,
                    primaryFullscreenTitle: fullscreenTitle,
                    traceLabel: traceLabel,
                    runtimeLogSnapshot: runtimeLogSnapshot
                )
                return
            }

            logWorkflowSpaceObservation("\(traceLabel).afterWindowStateReady", app: targetApp)
            XCTAssertTrue(
                waitForActiveSpaceWorkflowCGWindow(
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: FlowTabUITestRuntimeTruthWatchdogPolicy.optionTabInitialWindowStateTopology
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
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: traceLabel
            )
            confirmOptionTabSelectionAndWaitForEvidence(
                windowNumber: standardSelection.windowNumber,
                title: standardTitle,
                app: targetApp,
                diagnosticsSummary: diagnosticsSummary,
                activationWatchdog: FlowTabUITestRuntimeTruthWatchdogPolicy.optionTabConfirmedWindowActivation,
                dismissalWatchdog: FlowTabUITestRuntimeTruthWatchdogPolicy.optionTabSwitcherDismissal,
                traceLabel: "\(traceLabel).confirmStandard"
            )
            logWorkflowSpaceObservation("\(traceLabel).afterStandardConfirm", app: targetApp)

            diagnosticsSummary = try relaunchGlobalSwitcherAndWaitForFrontmostWorkflowWindow(
                app,
                for: targetApp,
                windowNumber: standardSelection.windowNumber,
                title: standardTitle,
                traceLabel: traceLabel,
                allowsNoisyCGSiblings: allowsNoisyCGSiblings,
                activationWatchdog: FlowTabUITestRuntimeTruthWatchdogPolicy.optionTabRelaunchWindowTopology
            )
            logWorkflowSpaceObservation("\(traceLabel).afterSecondWindowStateReady", app: targetApp)
            assertSwitcherSelectedWindowTitle(
                standardTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                message: "Option+Tab roundtrip must enter the second window-state phase on the normal sibling."
            )
            let targetFullscreenTitle = allowsNoisyCGSiblings
                ? try XCTUnwrap(
                    visibleFullscreenWindowTitle(in: diagnosticsSummary, for: targetApp),
                    """
                    Option+Tab noisy second phase did not expose a real fullscreen sibling.

                    \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                    """
                )
                : fullscreenTitle
            let fullscreenSelection = try selectGlobalSwitcherWindow(
                title: targetFullscreenTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: traceLabel
            )
            confirmOptionTabSelectionAndWaitForEvidence(
                windowNumber: fullscreenSelection.windowNumber,
                title: targetFullscreenTitle,
                app: targetApp,
                diagnosticsSummary: diagnosticsSummary,
                activationWatchdog: FlowTabUITestRuntimeTruthWatchdogPolicy.optionTabConfirmedWindowActivation,
                dismissalWatchdog: FlowTabUITestRuntimeTruthWatchdogPolicy.optionTabSwitcherDismissal,
                traceLabel: "\(traceLabel).confirmFullscreen"
            )
            logWorkflowSpaceObservation("\(traceLabel).afterFullscreenConfirm", app: targetApp)
        }
    }

    func testSwitcherPanelWindowSearchRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherRuntimeTruthWorkflow(
            sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.windowSearchRuntimeTruthWorkflowSourceURL
        )
        try runSwitcherPanelWindowSearchRoundTrip(
            workflow,
            traceLabel: "search"
        )
    }

    func testSwitcherPanelWindowSearchRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherRuntimeTruthWorkflow(
            sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.windowSearchNoisyRuntimeTruthWorkflowSourceURL
        )
        try runSwitcherPanelWindowSearchRoundTrip(
            workflow,
            traceLabel: "search.noisy",
            allowsNoisyCGSiblings: true
        )
    }

    private func runSwitcherPanelWindowSearchRoundTrip(
        _ workflow: SpaceFixtureResolvedWorkflow,
        traceLabel: String,
        allowsNoisyCGSiblings: Bool = false
    ) throws {
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
                ],
                suppressesPanelActivation: false
            ),
            waitsForFullscreenMarkers: false,
            suppressesAppAccessibilityChildren: true,
            validatesPermissionsBeforeFixtureLaunch: true,
            preservesDesktopAfterFullscreen: false,
            prelaunchesFlowTabBeforeFixture: true,
            beforeFlowTabLaunch: { _ in
                self.logWorkflowSpaceObservation("\(traceLabel).beforeFlowTabLaunch", app: targetApp)
                if allowsNoisyCGSiblings {
                    XCTAssertTrue(
                        self.waitForWorkflowSpaceContainingCGWindow(
                            title: fullscreenTitle,
                            app: targetApp,
                            timeout: FlowTabUITestRuntimeTruthWatchdogPolicy.windowSearchInitialTopology
                        ),
                        "Window search noisy roundtrip must start on a Space containing the fullscreen sibling."
                    )
                } else {
                    _ = try XCTUnwrap(
                        self.waitForFrontmostWorkflowSpaceCGWindow(
                            title: fullscreenTitle,
                            app: targetApp,
                            timeout: FlowTabUITestRuntimeTruthWatchdogPolicy.windowSearchInitialTopology
                        ),
                        "Window search roundtrip must start with the fullscreen sibling frontmost."
                    )
                }
            },
            flowTabLaunchTraceLabel: traceLabel,
            afterFlowTabLaunch: { _, _ in
                self.logWorkflowSpaceObservation("\(traceLabel).afterFlowTabLaunch", app: targetApp)
            }
        ) { _, app in
            logWorkflowSpaceObservation("\(traceLabel).beforeTrigger", app: targetApp)
            let readiness =
                prepareWindowSearchPresentationReadiness(
                    in: app,
                    workflowApp: targetApp,
                    allowsNoisyCGSiblings:
                        allowsNoisyCGSiblings
                )
            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.search, traceLabel: traceLabel)
            var searchInput = requireWindowSearchPresentation(
                in: app,
                observedBy: readiness
            )
            logWorkflowSpaceObservation("\(traceLabel).afterSearchReady", app: targetApp)
            XCTAssertTrue(
                allowsNoisyCGSiblings
                    ? waitForWorkflowSpaceContainingCGWindow(
                        title: fullscreenTitle,
                        app: targetApp,
                        timeout: FlowTabUITestRuntimeTruthWatchdogPolicy.windowSearchInitialPresentationTopology
                    )
                    : waitForActiveSpaceWorkflowCGWindow(
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: FlowTabUITestRuntimeTruthWatchdogPolicy.windowSearchInitialPresentationTopology
                ),
                "Window search first phase must open from the fullscreen sibling's Space."
            )

            if allowsNoisyCGSiblings {
                try runNoisyWindowSearchRoundTrip(
                    app: app,
                    targetApp: targetApp,
                    initialSearchInput: searchInput,
                    primaryFullscreenTitle: fullscreenTitle,
                    traceLabel: traceLabel
                )
                return
            }

            let standardSelection = try searchAndSelectWorkflowWindow(
                title: standardTitle,
                app: targetApp,
                in: app,
                traceLabel: traceLabel
            )

            confirmWindowSearchSelectionAndWaitForEvidence(
                windowNumber: standardSelection.windowNumber,
                title: standardTitle,
                app: targetApp,
                searchInput: searchInput,
                traceLabel: "\(traceLabel).confirmStandard"
            )
            logWorkflowSpaceObservation("\(traceLabel).afterStandardConfirm", app: targetApp)

            searchInput = try relaunchWindowSearchAndWaitForFrontmostWorkflowWindow(
                windowNumber: standardSelection.windowNumber,
                title: standardTitle,
                app: targetApp,
                traceLabel: "\(traceLabel).secondSearch"
            ) {
                let relaunchedSearchInput = relaunchWindowSearch(
                    app,
                    workflowApp: targetApp,
                    allowsNoisyCGSiblings:
                        allowsNoisyCGSiblings,
                    traceLabel: traceLabel
                )
                logWorkflowSpaceObservation("\(traceLabel).afterSecondSearchReady", app: targetApp)
                return relaunchedSearchInput
            }
            let fullscreenSelection = try searchAndSelectWorkflowWindow(
                title: fullscreenTitle,
                app: targetApp,
                in: app,
                traceLabel: traceLabel
            )

            confirmWindowSearchSelectionAndWaitForEvidence(
                windowNumber: fullscreenSelection.windowNumber,
                title: fullscreenSelection.title,
                app: targetApp,
                searchInput: searchInput,
                traceLabel: "\(traceLabel).confirmFullscreen"
            )
            logWorkflowSpaceObservation("\(traceLabel).afterFullscreenConfirm", app: targetApp)
        }
    }

    private func runNoisyWindowSearchRoundTrip(
        app: XCUIApplication,
        targetApp: SpaceFixtureResolvedWorkflow.App,
        initialSearchInput: XCUIElement,
        primaryFullscreenTitle: String,
        traceLabel: String
    ) throws {
        let standardTitles = standardWorkflowWindowTitles(in: targetApp)
        let normalOneTitle = try XCTUnwrap(
            standardTitles.first,
            "Noisy window search workflow must include the first normal window."
        )
        let normalTwoTitle = try XCTUnwrap(
            standardTitles.dropFirst().first,
            "Noisy window search workflow must include a second normal window."
        )
        let fullscreenTwoTitle = try XCTUnwrap(
            targetApp.fullscreenWindowTitles.dropFirst().first,
            "Noisy window search workflow must include a second fullscreen window."
        )

        var searchInput = initialSearchInput
        var currentSelection: RuntimeTruthWindowSelection?
        let phases: [(title: String, trace: String)] = [
            (normalOneTitle, "normal1"),
            (primaryFullscreenTitle, "fullscreen1"),
            (normalTwoTitle, "normal2"),
            (fullscreenTwoTitle, "fullscreen2")
        ]

        for (index, phase) in phases.enumerated() {
            if index > 0 {
                let previousSelection = try XCTUnwrap(
                    currentSelection,
                    "Noisy Window Search relaunch requires the preceding exact window selection."
                )
                searchInput = try relaunchWindowSearchAndWaitForFrontmostWorkflowWindow(
                    windowNumber: previousSelection.windowNumber,
                    title: previousSelection.title,
                    app: targetApp,
                    traceLabel: "\(traceLabel).relaunch.\(phase.trace)"
                ) {
                    let relaunchedSearchInput = relaunchWindowSearch(
                        app,
                        workflowApp: targetApp,
                        allowsNoisyCGSiblings: true,
                        traceLabel: traceLabel
                    )
                    return relaunchedSearchInput
                }
            }

            let selection = try searchAndSelectWorkflowWindow(
                title: phase.title,
                app: targetApp,
                in: app,
                traceLabel: "\(traceLabel).\(phase.trace)"
            )

            confirmWindowSearchSelectionAndWaitForEvidence(
                windowNumber: selection.windowNumber,
                title: phase.title,
                app: targetApp,
                searchInput: searchInput,
                traceLabel: "\(traceLabel).confirm.\(phase.trace)"
            )
            currentSelection = selection
            logWorkflowSpaceObservation("\(traceLabel).afterConfirm.\(phase.trace)", app: targetApp)
        }
    }

    func assertGlobalSwitcherWindowStateReady(
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        traceLabel: String,
        allowsNoisyCGSiblings: Bool = false
    ) throws -> XCUIElement {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))

        logFlowTabUITestTrace(
            "[\(traceLabel).selectWorkflowApp.direct] target=\(workflowApp.identity.bundleIdentifier) selected=\(switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected"))"
        )
        try postFlowTabUITestSelectSwitcherAppAndWaitForDelivery(
            bundleIdentifier: workflowApp.identity.bundleIdentifier,
            traceLabel: "\(traceLabel).selectApp"
        )
        assertSwitcherSelectedApp(
            workflowApp,
            in: app,
            diagnosticsSummary: diagnosticsSummary,
            stage: "before entering Option+Tab window state"
        )
        if allowsNoisyCGSiblings {
            XCTAssertTrue(
                waitForSwitcherAppEntry(
                    diagnosticsSummary,
                    bundleIdentifier: workflowApp.identity.bundleIdentifier,
                    timeout: 4
                ),
                """
                Option+Tab switcher did not include \(workflowApp.appName) after selecting it.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
        } else {
            XCTAssertTrue(
                waitForSwitcherAppsSummary(
                    diagnosticsSummary,
                    toContain: switcherAppStripSummary(for: workflowApp),
                    timeout: 4
                ),
                """
                Option+Tab switcher did not include \(workflowApp.appName) after selecting it.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
        }

        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "mode",
                hasPrefix: "windowCycle",
                timeout: 4,
                trigger: {
                    self.logWorkflowSpaceObservation(
                        "\(traceLabel).beforeEnterWindowState",
                        app: workflowApp
                    )
                    self
                        .postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                            .advanceDown,
                            traceLabel:
                                "\(traceLabel).enterWindowState"
                        )
                    self.logWorkflowSpaceObservation(
                        "\(traceLabel).afterEnterWindowState",
                        app: workflowApp
                    )
                }
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
        if allowsNoisyCGSiblings {
            XCTAssertTrue(
                waitForNoisyFullscreenWorkflowPreviewTitles(
                    diagnosticsSummary,
                    for: workflowApp,
                    timeout: 8
                ),
                """
                Option+Tab noisy app window state did not include the required real windows.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
        } else {
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
        }
        return diagnosticsSummary
    }

    private func assertSwitcherSelectedApp(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        stage: String
    ) {
        XCTAssertTrue(
            waitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "selected",
                equals: workflowApp.identity.bundleIdentifier,
                timeout: 4
            ),
            """
            Option+Tab selected the wrong app \(stage). Expected \
            \(workflowApp.identity.bundleIdentifier).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
    }

    private func searchAndSelectWorkflowWindow(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        traceLabel: String
    ) throws -> RuntimeTruthWindowSelection {
        let result = try XCTUnwrap(
            try performAndWaitForCommittedSearchWindowResult(
                in: app,
                scope: "window",
                query: title,
                title: title,
                appName: workflowApp.appName,
                timeout:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .windowSearchQueryProjectionPublication,
                trigger: {
                    try self.postFlowTabUITestSwitcherSearchQueryAndWaitForDelivery(
                        title,
                        traceLabel: "\(traceLabel).query"
                    )
                }
            )
        )
        let windowNumber = try XCTUnwrap(
            result.windowNumber,
            "Search result \(result.identifier) did not expose a CG window number."
        )
        try selectSearchResultForConfirmation(result, in: app, traceLabel: traceLabel)
        return RuntimeTruthWindowSelection(
            title: title,
            windowNumber: windowNumber
        )
    }

    private func selectSearchResultForConfirmation(
        _ result: SwitcherSearchWindowResultObservation,
        in app: XCUIApplication,
        traceLabel: String
    ) throws {
        let resultID = try XCTUnwrap(
            result.resultID,
            "Search result \(result.identifier) did not expose a stable result id."
        )
        try postFlowTabUITestSelectSearchResultAndWaitForDelivery(
            resultID: resultID,
            traceLabel: "\(traceLabel).selectSearchResult"
        )

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(
            waitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "searchSelectedResult", equals: resultID,
                decodesPercentEncoding: true, timeout: 2
            ),
            """
            Search result command did not select \(resultID).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
    }

    func runtimeTruthWindowSelection(
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
        standardWorkflowWindowTitles(in: workflowApp).first
    }

    func standardWorkflowWindowTitles(
        in workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> [String] {
        let fullscreenTitles = Set(workflowApp.fullscreenWindowTitles)
        return workflowApp.expectedWindowTitles.filter { !fullscreenTitles.contains($0) }
    }

    func runtimeTruthSwitcherLaunchArguments(
        additionalArguments: [String] = [],
        suppressesPanelActivation: Bool = true
    ) -> [String] {
        var arguments = [
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-suppress-home-on-launch",
            "--flowtab-ui-runtime-log-level", "DEBUG",
            "--flowtab-ui-enable-verbose-logs",
            "-windowLayerAutoEnterDelay", "30.0"
        ] + FlowTabUITestSwitcherCommandPayload.launchArguments + additionalArguments

        if suppressesPanelActivation {
            arguments.append("--flowtab-ui-suppress-panel-activation")
        }

        return arguments
    }

    func relaunchGlobalSwitcher(
        _ app: XCUIApplication,
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        traceLabel: String,
        allowsNoisyCGSiblings: Bool = false
    ) throws -> XCUIElement {
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.global, traceLabel: "\(traceLabel).relaunch")
        return try assertGlobalSwitcherWindowStateReady(
            for: workflowApp,
            in: app,
            traceLabel: traceLabel,
            allowsNoisyCGSiblings: allowsNoisyCGSiblings
        )
    }

    private func relaunchWindowSearch(
        _ app: XCUIApplication,
        workflowApp: SpaceFixtureResolvedWorkflow.App,
        allowsNoisyCGSiblings: Bool,
        traceLabel: String
    ) -> XCUIElement {
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        let readiness =
            prepareWindowSearchPresentationReadiness(
                in: app,
                workflowApp: workflowApp,
                allowsNoisyCGSiblings:
                    allowsNoisyCGSiblings
            )
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.search, traceLabel: "\(traceLabel).relaunch")
        return requireWindowSearchPresentation(
            in: app,
            observedBy: readiness
        )
    }

}
