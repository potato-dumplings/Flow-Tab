import AppKit
import CoreGraphics
import XCTest

private struct InAppWindowSelection: Equatable {
    let title: String
    let windowID: String
    let windowNumber: CGWindowID
}

extension FlowTabUITests {
    func testInAppWindowSwitcherControlTabRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherRuntimeTruthWorkflow(
            sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.controlTabRuntimeTruthWorkflowSourceURL
        )
        try runInAppWindowSwitcherControlTabRoundTrip(
            workflow,
            traceLabel: "control"
        )
    }

    func testInAppWindowSwitcherControlTabRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherRuntimeTruthWorkflow(
            sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.controlTabNoisyRuntimeTruthWorkflowSourceURL
        )
        try runInAppWindowSwitcherControlTabRoundTrip(
            workflow,
            traceLabel: "control.noisy",
            allowsNoisyCGSiblings: true
        )
    }

    private func runInAppWindowSwitcherControlTabRoundTrip(
        _ workflow: SpaceFixtureResolvedWorkflow,
        traceLabel: String,
        allowsNoisyCGSiblings: Bool = false
    ) throws {
        let targetApp = try XCTUnwrap(
            workflow.apps.first { fullscreenWindowTitle(in: $0) != nil },
            "Switcher workflow must include an app with a fullscreen fixture window"
        )
        let fullscreenTitle = try XCTUnwrap(fullscreenWindowTitle(in: targetApp))
        let standardTitle = try XCTUnwrap(firstStandardWindowTitle(in: targetApp))
        let runtimeLogSnapshot = makeRuntimeLogFileSnapshot()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: inAppSwitcherLaunchArguments(for: targetApp),
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
                            timeout: 12
                        ),
                        "Control+Tab noisy roundtrip must start on a Space containing the fullscreen sibling."
                    )
                } else {
                    _ = try XCTUnwrap(
                        self.waitForFrontmostWorkflowSpaceCGWindow(
                            title: fullscreenTitle,
                            app: targetApp,
                            timeout: 12
                        ),
                        "Control+Tab roundtrip must start with the fullscreen sibling frontmost."
                    )
                }
            },
            flowTabLaunchTraceLabel: traceLabel,
            afterFlowTabLaunch: { _, _ in
                self.logWorkflowSpaceObservation("\(traceLabel).afterFlowTabLaunch", app: targetApp)
            }
        ) { _, app in
            logWorkflowSpaceObservation("\(traceLabel).beforeTrigger", app: targetApp)
            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.inApp, traceLabel: traceLabel)
            var diagnosticsSummary = assertInAppWindowSwitcherReady(
                for: targetApp,
                in: app,
                allowsNoisyCGSiblings: allowsNoisyCGSiblings
            )
            logWorkflowSpaceObservation("\(traceLabel).afterPanelReady", app: targetApp)
            XCTAssertTrue(
                allowsNoisyCGSiblings
                    ? waitForWorkflowSpaceContainingCGWindow(
                        title: fullscreenTitle,
                        app: targetApp,
                        timeout: 4
                    )
                    : waitForActiveSpaceWorkflowCGWindow(
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: 4
                ),
                "Control+Tab first phase must open from the fullscreen sibling's Space."
            )
            if allowsNoisyCGSiblings {
                assertSwitcherSelectedWindowTitle(
                    oneOf: Set(targetApp.fullscreenWindowTitles),
                    in: app,
                    diagnosticsSummary: diagnosticsSummary,
                    message: "Control+Tab roundtrip must enter the first focused-window phase on a real fullscreen sibling."
                )
            } else {
                assertSwitcherSelectedWindowTitle(
                    fullscreenTitle,
                    in: app,
                    diagnosticsSummary: diagnosticsSummary,
                    message: "Control+Tab roundtrip must enter the first focused-window phase on the fullscreen sibling."
                )
            }

            if allowsNoisyCGSiblings {
                try runNoisyInAppWindowSwitcherControlTabRoundTrip(
                    app: app,
                    targetApp: targetApp,
                    diagnosticsSummary: diagnosticsSummary,
                    primaryFullscreenTitle: fullscreenTitle,
                    traceLabel: traceLabel,
                    runtimeLogSnapshot: runtimeLogSnapshot
                )
                return
            }

            let firstLogSnapshot = makeRuntimeLogFileSnapshot()
            let standardSelection = try selectInAppWindow(
                title: standardTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                requiresControlTab: true
            )
            waitForRuntimeLogFiles(
                containing: ["inAppHotkeyPressed dir=forward panelVisible=1", "advance key=tabForward"],
                since: firstLogSnapshot,
                timeout: 8
            )

            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.confirm, traceLabel: "\(traceLabel).confirmStandard")
            XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
            logWorkflowSpaceObservation("\(traceLabel).afterStandardConfirm", app: targetApp)

            diagnosticsSummary = relaunchInAppWindowSwitcher(
                app,
                for: targetApp,
                focusedWindow: standardSelection
            )
            logWorkflowSpaceObservation("\(traceLabel).afterSecondPanelReady", app: targetApp)
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    timeout: 4
                ),
                "Control+Tab second phase must open from the focused normal sibling."
            )
            assertSwitcherSelectedWindowTitle(
                standardTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                message: "Control+Tab roundtrip must enter the second focused-window phase on the normal sibling."
            )
            let targetFullscreenTitle = allowsNoisyCGSiblings
                ? try XCTUnwrap(
                    visibleFullscreenWindowTitle(in: diagnosticsSummary, for: targetApp),
                    """
                    Control+Tab noisy second phase did not expose a real fullscreen sibling.

                    \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                    """
                )
                : fullscreenTitle
            let secondLogSnapshot = makeRuntimeLogFileSnapshot()
            let fullscreenSelection = try selectInAppWindow(
                title: targetFullscreenTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                requiresControlTab: true
            )
            waitForRuntimeLogFiles(
                containing: ["inAppHotkeyPressed dir=forward panelVisible=1", "advance key=tabForward"],
                since: secondLogSnapshot,
                timeout: 8
            )

            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.confirm, traceLabel: "\(traceLabel).confirmFullscreen")
            XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: fullscreenSelection.windowNumber,
                    title: targetFullscreenTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
            logWorkflowSpaceObservation("\(traceLabel).afterFullscreenConfirm", app: targetApp)
        }
    }

    private func runNoisyInAppWindowSwitcherControlTabRoundTrip(
        app: XCUIApplication,
        targetApp: SpaceFixtureResolvedWorkflow.App,
        diagnosticsSummary initialDiagnosticsSummary: XCUIElement,
        primaryFullscreenTitle: String,
        traceLabel: String,
        runtimeLogSnapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) throws {
        let standardTitles = standardWindowTitles(in: targetApp)
        let normalOneTitle = try XCTUnwrap(
            standardTitles.first,
            "Noisy Control+Tab workflow must include the first normal window."
        )
        let normalTwoTitle = try XCTUnwrap(
            standardTitles.dropFirst().first,
            "Noisy Control+Tab workflow must include a second normal window."
        )
        let fullscreenTwoTitle = try XCTUnwrap(
            targetApp.fullscreenWindowTitles.dropFirst().first,
            "Noisy Control+Tab workflow must include a second fullscreen window."
        )

        XCTAssertTrue(
            waitForSwitcherPreviewTitles(
                initialDiagnosticsSummary,
                toExactlyMatch: targetApp.expectedWindowTitles,
                timeout: 4
            ),
            """
            Noisy Control+Tab must expose exactly the four user windows, without CG-only fullscreen hosts.
            \(switcherDebugSummary(app, diagnosticsSummary: initialDiagnosticsSummary))
            """
        )
        let initialSelection = try assertNoisyInAppWindowSwitcherCurrentSelection(
            primaryFullscreenTitle,
            expectedSelection: nil,
            expectedPrefix: [primaryFullscreenTitle],
            app: app,
            diagnosticsSummary: initialDiagnosticsSummary,
            traceLabel: traceLabel,
            phaseTrace: "initial"
        )

        var diagnosticsSummary = initialDiagnosticsSummary
        var currentSelection = initialSelection
        let phases: [
            (
                currentTitle: String,
                targetTitle: String,
                expectedPrefix: [String],
                trace: String
            )
        ] = [
            (
                primaryFullscreenTitle,
                normalOneTitle,
                [primaryFullscreenTitle],
                "normal1"
            ),
            (
                normalOneTitle,
                primaryFullscreenTitle,
                [normalOneTitle],
                "fullscreen1"
            ),
            (
                primaryFullscreenTitle,
                normalTwoTitle,
                [primaryFullscreenTitle],
                "normal2"
            ),
            (
                normalTwoTitle,
                fullscreenTwoTitle,
                [normalTwoTitle],
                "fullscreen2"
            )
        ]

        for (index, phase) in phases.enumerated() {
            if index > 0 {
                diagnosticsSummary = relaunchInAppWindowSwitcher(
                    app,
                    for: targetApp,
                    focusedWindow: currentSelection,
                    allowsNoisyCGSiblings: true
                )
                XCTAssertTrue(
                    waitForSwitcherPreviewTitles(
                        diagnosticsSummary,
                        toExactlyMatch: targetApp.expectedWindowTitles,
                        timeout: 4
                    ),
                    """
                    Noisy Control+Tab reopened with unexpected window entries before \(phase.trace).
                    \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                    """
                )
                XCTAssertTrue(
                    waitForExactFrontmostWorkflowCGWindow(
                        windowNumber: currentSelection.windowNumber,
                        title: currentSelection.title,
                        app: targetApp,
                        timeout: 4
                    ),
                    "Noisy Control+Tab \(phase.trace) phase must reopen from \(currentSelection.title)."
                )
                currentSelection = try assertNoisyInAppWindowSwitcherCurrentSelection(
                    phase.currentTitle,
                    expectedSelection: currentSelection,
                    expectedPrefix: phase.expectedPrefix,
                    app: app,
                    diagnosticsSummary: diagnosticsSummary,
                    traceLabel: traceLabel,
                    phaseTrace: phase.trace
                )
            }

            let logSnapshot = makeRuntimeLogFileSnapshot()
            let selection = try selectNoisyInAppWindow(
                currentSelection: currentSelection,
                title: phase.targetTitle,
                expectedPrefix: phase.expectedPrefix,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: "\(traceLabel).\(phase.trace)"
            )
            assertNoisyInAppFilteredCGOnlyArtifactSource(
                since: runtimeLogSnapshot
            )
            assertNoisyInAppWindowLayerSource(
                selection,
                phaseTrace: phase.trace,
                since: runtimeLogSnapshot
            )
            waitForRuntimeLogFiles(
                containing: ["inAppHotkeyPressed dir=forward panelVisible=1", "advance key=tabForward"],
                since: logSnapshot,
                timeout: 8
            )

            let activationLogSnapshot = makeRuntimeLogFileSnapshot()
            postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                .confirm,
                traceLabel: "\(traceLabel).confirm.\(phase.trace)"
            )
            XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 4))
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: selection.windowNumber,
                    title: phase.targetTitle,
                    app: targetApp,
                    timeout: 12
                ),
                "Noisy Control+Tab must activate the exact \(phase.targetTitle) CG window selected in \(phase.trace)."
            )
            assertNoisyInAppWindowRequestSource(
                selection,
                appID: targetApp.identity.bundleIdentifier,
                phaseTrace: phase.trace,
                since: activationLogSnapshot
            )
            assertNoisyInAppVerifiedFocusReadback(
                selection,
                phaseTrace: phase.trace,
                since: activationLogSnapshot
            )
            currentSelection = selection
            logWorkflowSpaceObservation("\(traceLabel).afterConfirm.\(phase.trace)", app: targetApp)
        }
    }

    private func assertNoisyInAppFilteredCGOnlyArtifactSource(
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        waitForRuntimeLogFiles(
            matching: #"Chrome Fixture (filtered-fullscreen-((sibling|host)-artifacts stage=(pre-dedupe|presentation|window-record-projection|read-model-current-app-normalization)|duplicate-surfaces stage=(presentation-final|window-record-projection|read-model-current-app-normalization))|filtered-cg-only-covered-by-activation stage=read-model-current-app-normalization) dropped=[1-9][0-9]*"#,
            since: snapshot,
            timeout: 8,
            description: "Noisy Control+Tab filtered CG-only/fullscreen artifact or duplicate surface source"
        )
    }

    private func assertNoisyInAppWindowLayerSource(
        _ selection: InAppWindowSelection,
        phaseTrace: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        let escapedTitle = NSRegularExpression.escapedPattern(for: selection.title)
        waitForRuntimeLogFiles(
            matching: #"window-entries app=Chrome Fixture .*id=cg:[0-9]+:\#(selection.windowNumber):title=\#(escapedTitle)[^\n]*source=stickyBinding:spaceEvidence=(observed|inferredFromTopology)"#,
            since: snapshot,
            timeout: 8,
            description: "sticky current-app window-layer source for selected Noisy Control+Tab \(phaseTrace) window"
        )
    }

    private func assertNoisyInAppWindowRequestSource(
        _ selection: InAppWindowSelection,
        appID: String,
        phaseTrace: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        let escapedAppID = NSRegularExpression.escapedPattern(for: appID)
        let escapedTitle = NSRegularExpression.escapedPattern(for: selection.title)
        waitForRuntimeLogFiles(
            matching: #"window-request appID=\#(escapedAppID) pid=[0-9]+ windowID=cg:[0-9]+:\#(selection.windowNumber) title=\#(escapedTitle)[^\n]* sticky=true source=stickyBinding"#,
            since: snapshot,
            timeout: 8,
            description: "sticky current-app window request source for selected Noisy Control+Tab \(phaseTrace) window"
        )
    }

    private func assertNoisyInAppVerifiedFocusReadback(
        _ selection: InAppWindowSelection,
        phaseTrace: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        waitForRuntimeLogFiles(
            matching: "binding-confidence-change windowID=cg:[0-9]+:\(selection.windowNumber) cg=\(selection.windowNumber) .* source=.*->verifiedFocusReadback",
            since: snapshot,
            timeout: 8,
            description: "verified-focus exact WindowRecord relearn after Noisy Control+Tab \(phaseTrace) confirm"
        )
    }

    private func inAppSwitcherLaunchArguments(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> [String] {
        [
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-suppress-home-on-launch",
            "--flowtab-ui-suppress-panel-activation",
            "--flowtab-ui-frontmost-bundle-id", workflowApp.identity.bundleIdentifier,
            "--flowtab-ui-runtime-log-level", "DEBUG",
            "--flowtab-ui-enable-verbose-logs"
        ]
    }

    private func firstStandardWindowTitle(
        in workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String? {
        standardWindowTitles(in: workflowApp).first
    }

    private func standardWindowTitles(
        in workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> [String] {
        let fullscreenTitles = Set(workflowApp.fullscreenWindowTitles)
        return workflowApp.expectedWindowTitles.filter { !fullscreenTitles.contains($0) }
    }

    private func assertInAppWindowSwitcherReady(
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        allowsNoisyCGSiblings: Bool = false
    ) -> XCUIElement {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))

        if allowsNoisyCGSiblings {
            XCTAssertTrue(
                waitForInAppSwitcherAppEntry(
                    diagnosticsSummary,
                    bundleIdentifier: workflowApp.identity.bundleIdentifier,
                    timeout: 8
                )
            )
        } else {
            XCTAssertTrue(
                waitForSwitcherAppsSummary(
                    diagnosticsSummary,
                    toContain: switcherAppStripSummary(for: workflowApp),
                    timeout: 8
                )
            )
        }
        XCTAssertEqual(
            switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected"),
            workflowApp.identity.bundleIdentifier
        )
        if allowsNoisyCGSiblings {
            XCTAssertTrue(
                waitForSwitcherPreviewTitles(
                    diagnosticsSummary,
                    toExactlyMatch: workflowApp.expectedWindowTitles,
                    timeout: 8
                ),
                """
                Control+Tab noisy window state did not expose exactly the expected user windows.
                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
        } else {
            XCTAssertEqual(Set(switcherPreviewTitles(from: diagnosticsSummary)), Set(workflowApp.expectedWindowTitles))
        }
        return diagnosticsSummary
    }

    private func assertNoisyInAppWindowSwitcherCurrentSelection(
        _ expectedTitle: String,
        expectedSelection: InAppWindowSelection?,
        expectedPrefix: [String],
        app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        traceLabel: String,
        phaseTrace: String
    ) throws -> InAppWindowSelection {
        assertSwitcherSelectedWindowTitle(
            expectedTitle,
            in: app,
            diagnosticsSummary: diagnosticsSummary,
            message: "Noisy Control+Tab \(phaseTrace) phase must enter window state on \(expectedTitle)."
        )
        let latestTitle = switcherPanelDiagnosticsValue(
            diagnosticsSummary,
            key: "selectedWindowTitle"
        )
        let latestWindowID = switcherPanelDiagnosticsValue(
            diagnosticsSummary,
            key: "selectedWindow"
        )
        let selection = try inAppWindowSelection(title: latestTitle, windowID: latestWindowID)
        logFlowTabUITestTrace(
            "[\(traceLabel).current.\(phaseTrace)] selected=\(latestTitle) windowID=\(latestWindowID)"
        )
        XCTAssertEqual(
            Array(expectedPrefix.prefix(1)),
            [selection.title],
            "Noisy Control+Tab \(phaseTrace) phase must start from the activated current window."
        )
        if let expectedSelection {
            XCTAssertEqual(
                selection,
                expectedSelection,
                """
                Noisy Control+Tab \(phaseTrace) phase must reopen from the previously activated window.
                Expected \(expectedSelection.title) / \(expectedSelection.windowNumber), \
                found \(selection.title) / \(selection.windowNumber).
                """
            )
        }
        return selection
    }

    private func selectNoisyInAppWindow(
        currentSelection: InAppWindowSelection,
        title: String,
        expectedPrefix: [String],
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        traceLabel: String
    ) throws -> InAppWindowSelection {
        var observedPrefix = [currentSelection.title]
        let attempts = workflowWindowCycleAttemptCount(diagnosticsSummary)
        var latestTitle = currentSelection.title
        var latestWindowID = currentSelection.windowID

        if latestTitle == title {
            assertNoisyInAppObservedPrefix(
                observedPrefix,
                expectedPrefix: expectedPrefix,
                traceLabel: traceLabel
            )
            return currentSelection
        }

        for attempt in 0..<attempts {
            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.inAppForward, traceLabel: "control.select")
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            latestTitle = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindowTitle")
            latestWindowID = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindow")
            observedPrefix.append(latestTitle)
            logFlowTabUITestTrace(
                "[\(traceLabel).selectAttempt.\(attempt + 1)] target=\(title) selected=\(latestTitle) windowID=\(latestWindowID)"
            )
            assertNoisyInAppObservedPrefix(
                observedPrefix,
                expectedPrefix: expectedPrefix,
                traceLabel: traceLabel
            )
            if latestTitle == title {
                return try inAppWindowSelection(title: latestTitle, windowID: latestWindowID)
            }
        }

        XCTFail(
            """
            Noisy Control+Tab did not select \(title).
            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return try inAppWindowSelection(title: latestTitle, windowID: latestWindowID)
    }

    private func assertNoisyInAppObservedPrefix(
        _ observedPrefix: [String],
        expectedPrefix: [String],
        traceLabel: String
    ) {
        let prefixLength = min(observedPrefix.count, expectedPrefix.count)
        XCTAssertEqual(
            Array(observedPrefix.prefix(prefixLength)),
            Array(expectedPrefix.prefix(prefixLength)),
            "Noisy Control+Tab \(traceLabel) must preserve the activated current window before cycling fallback."
        )
    }

    private func selectInAppWindow(
        title: String,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        requiresControlTab: Bool
    ) throws -> InAppWindowSelection {
        let attempts = max(1, workflowWindowCycleAttemptCount(diagnosticsSummary))
        var latestTitle = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindowTitle")
        var latestWindowID = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindow")

        if !requiresControlTab, latestTitle == title {
            return try inAppWindowSelection(title: latestTitle, windowID: latestWindowID)
        }

        for attempt in 0..<attempts {
            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.inAppForward, traceLabel: "control.select")
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            latestTitle = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindowTitle")
            latestWindowID = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindow")
            logFlowTabUITestTrace(
                "[control.selectAttempt.\(attempt + 1)] target=\(title) selected=\(latestTitle) windowID=\(latestWindowID)"
            )
            if latestTitle == title {
                return try inAppWindowSelection(title: latestTitle, windowID: latestWindowID)
            }
        }

        XCTFail(
            """
            Control+Tab did not select \(title). \
            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return try inAppWindowSelection(title: latestTitle, windowID: latestWindowID)
    }

    private func workflowWindowCycleAttemptCount(_ diagnosticsSummary: XCUIElement) -> Int {
        max(1, switcherPreviewTitles(from: diagnosticsSummary).count + 3)
    }

    private func inAppWindowSelection(
        title: String,
        windowID: String
    ) throws -> InAppWindowSelection {
        let windowNumber: CGWindowID? = windowID.split(separator: ":").last.flatMap { UInt32($0) }
        return InAppWindowSelection(
            title: title,
            windowID: windowID,
            windowNumber: try XCTUnwrap(
                windowNumber,
                "Selected window id \(windowID) did not expose a CG window number."
            )
        )
    }

    private func relaunchInAppWindowSwitcher(
        _ app: XCUIApplication,
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        focusedWindow: InAppWindowSelection,
        allowsNoisyCGSiblings: Bool = false
    ) -> XCUIElement {
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        let fixtureApplication =
            makeSpaceFixtureWorkflowApplication(
                for: workflowApp.identity
            )
        XCTAssertTrue(
            triggerAndWaitForFrontmostWorkflowWindow(
                windowNumber: focusedWindow.windowNumber,
                title: focusedWindow.title,
                app: workflowApp,
                timeout: 12,
                trigger: {
                    fixtureApplication.activate()
                }
            )
        )
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.inApp, traceLabel: "control.reopen")
        return assertInAppWindowSwitcherReady(
            for: workflowApp,
            in: app,
            allowsNoisyCGSiblings: allowsNoisyCGSiblings
        )
    }

    private func waitForInAppSwitcherAppEntry(
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

}
