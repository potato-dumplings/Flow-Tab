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
        defer { runtimeLogSnapshot.cancel() }
        var filteredArtifactObservationOwner:
            FlowTabUITestInAppFilteredArtifactObservationOwner?
        defer { filteredArtifactObservationOwner?.cancel() }
        var targetProcessIdentifier: pid_t?

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
                    let runningProcessIdentifier = try self
                        .runningWorkflowApplicationProcessIdentifier(
                            targetApp
                        )
                    targetProcessIdentifier = runningProcessIdentifier
                    let owner =
                        FlowTabUITestInAppFilteredArtifactObservationOwner(
                            expectedAppName: targetApp.appName,
                            expectedProcessIdentifier:
                                runningProcessIdentifier,
                            baseline: runtimeLogSnapshot
                        )
                    owner.start()
                    filteredArtifactObservationOwner = owner
                    XCTAssertTrue(
                        self.waitForWorkflowSpaceContainingCGWindow(
                            title: fullscreenTitle,
                            app: targetApp,
                            timeout:
                                FlowTabUITestInAppWorkflowWindowObservationPolicy
                                .initialTopologyReadinessWatchdog
                        ),
                        "Control+Tab noisy roundtrip must start on a Space containing the fullscreen sibling."
                    )
                } else {
                    _ = try XCTUnwrap(
                        self.waitForFrontmostWorkflowSpaceCGWindow(
                            title: fullscreenTitle,
                            app: targetApp,
                            timeout:
                                FlowTabUITestInAppWorkflowWindowObservationPolicy
                                .initialTopologyReadinessWatchdog
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
            var diagnosticsSummary =
                performAndWaitForInAppSwitcherPanelProjection(
                    for: targetApp,
                    in: app,
                    trigger: {
                        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                            .inApp,
                            traceLabel: traceLabel
                        )
                    }
            )
            logWorkflowSpaceObservation("\(traceLabel).afterPanelReady", app: targetApp)
            if allowsNoisyCGSiblings {
                let owner = try XCTUnwrap(
                    filteredArtifactObservationOwner,
                    "Noisy Control+Tab filtered-artifact observation must start before the In-App trigger."
                )
                let evidence = try XCTUnwrap(
                    owner.waitForResolution(
                        timeout:
                            FlowTabUITestInAppFilteredArtifactObservationPolicy
                            .watchdog
                    ),
                    "Noisy Control+Tab exact filtered-artifact watchdog expired. \(owner.diagnosticSummary)"
                )
                XCTAssertEqual(
                    evidence.value.appName,
                    targetApp.appName
                )
                XCTAssertGreaterThan(
                    evidence.value.droppedCount,
                    0
                )
            }
            XCTAssertTrue(
                allowsNoisyCGSiblings
                    ? waitForWorkflowSpaceContainingCGWindow(
                        title: fullscreenTitle,
                        app: targetApp,
                        timeout:
                            FlowTabUITestInAppWorkflowWindowObservationPolicy
                            .currentTopologyReadinessWatchdog
                    )
                    : waitForActiveSpaceWorkflowCGWindow(
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout:
                        FlowTabUITestInAppWorkflowWindowObservationPolicy
                        .currentTopologyReadinessWatchdog
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
                    runtimeLogSnapshot: runtimeLogSnapshot,
                    targetProcessIdentifier: try XCTUnwrap(
                        targetProcessIdentifier,
                        "Noisy Control+Tab fixture PID must be captured before FlowTab launch."
                    )
                )
                return
            }

            let standardSelection = try selectInAppWindow(
                title: standardTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                requiresControlTab: true
            )

            guard
                confirmInAppSelectionAndWaitForEvidence(
                    windowNumber:
                        standardSelection.windowNumber,
                    title: standardTitle,
                    app: targetApp,
                    diagnosticsSummary: diagnosticsSummary,
                    traceLabel:
                        "\(traceLabel).confirmStandard"
                ) != nil
            else {
                return
            }
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
                    timeout:
                        FlowTabUITestInAppWorkflowWindowObservationPolicy
                        .currentTopologyReadinessWatchdog
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
            let fullscreenSelection = try selectInAppWindow(
                title: targetFullscreenTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                requiresControlTab: true
            )

            guard
                confirmInAppSelectionAndWaitForEvidence(
                    windowNumber:
                        fullscreenSelection.windowNumber,
                    title: targetFullscreenTitle,
                    app: targetApp,
                    diagnosticsSummary: diagnosticsSummary,
                    traceLabel:
                        "\(traceLabel).confirmFullscreen"
                ) != nil
            else {
                return
            }
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
            FlowTabUITestRuntimeLogObservationBaseline,
        targetProcessIdentifier: pid_t
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
                    focusedWindow: currentSelection
                )
                XCTAssertTrue(
                    waitForExactFrontmostWorkflowCGWindow(
                        windowNumber: currentSelection.windowNumber,
                        title: currentSelection.title,
                        app: targetApp,
                        timeout:
                            FlowTabUITestInAppWorkflowWindowObservationPolicy
                            .currentTopologyReadinessWatchdog
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

            let selection = try selectNoisyInAppWindowWithLayerEvidence(
                currentSelection: currentSelection,
                title: phase.targetTitle,
                expectedPrefix: phase.expectedPrefix,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: "\(traceLabel).\(phase.trace)",
                targetApp: targetApp,
                targetProcessIdentifier:
                    targetProcessIdentifier,
                phaseTrace: phase.trace,
                runtimeLogSnapshot: runtimeLogSnapshot
            )
            do {
                let activationLogSnapshot = makeRuntimeLogFileSnapshot()
                defer { activationLogSnapshot.cancel() }
                let requestOwner =
                    FlowTabUITestInAppWindowRequestObservationOwner(
                        expectedAppID:
                            targetApp.identity.bundleIdentifier,
                        expectedProcessIdentifier:
                            targetProcessIdentifier,
                        expectedWindowID: selection.windowID,
                        expectedWindowNumber:
                            selection.windowNumber,
                        expectedTitle: selection.title,
                        baseline: activationLogSnapshot
                    )
                requestOwner.start()
                defer { requestOwner.cancel() }
                let verifiedFocusOwner =
                    FlowTabUITestInAppVerifiedFocusReadbackObservationOwner(
                        expectedProcessIdentifier:
                            targetProcessIdentifier,
                        expectedWindowID: selection.windowID,
                        expectedWindowNumber:
                            selection.windowNumber,
                        baseline: activationLogSnapshot
                    )
                verifiedFocusOwner.start()
                defer { verifiedFocusOwner.cancel() }

                guard
                    let confirmationEvidence =
                        confirmInAppSelectionAndWaitForEvidence(
                            windowNumber: selection.windowNumber,
                            title: phase.targetTitle,
                            app: targetApp,
                            diagnosticsSummary: diagnosticsSummary,
                            traceLabel:
                                "\(traceLabel).confirm.\(phase.trace)",
                            additionalTriggerLifecycle:
                                verifiedFocusOwner
                        )
                else {
                    return
                }
                guard verifiedFocusOwner.baselineIssue == nil else {
                    XCTFail(
                        "Noisy Control+Tab verified-focus baseline rejected for \(phase.trace). \(verifiedFocusOwner.diagnosticSummary)"
                    )
                    return
                }
                let requestEvidence = try XCTUnwrap(
                    requestOwner.waitForResolution(
                        timeout:
                            FlowTabUITestInAppWindowRequestObservationPolicy
                            .watchdog
                    ),
                    "Noisy Control+Tab reusable window-request evidence "
                        + "watchdog expired for \(phase.trace). "
                        + requestOwner.diagnosticSummary
                )
                XCTAssertEqual(
                    requestEvidence.value.windowID,
                    selection.windowID
                )
                XCTAssertEqual(
                    requestEvidence.value.processIdentifier,
                    targetProcessIdentifier
                )
                let verifiedFocusEvidence = try XCTUnwrap(
                    verifiedFocusOwner.waitForResolution(
                        timeout:
                            FlowTabUITestInAppVerifiedFocusReadbackObservationPolicy
                            .watchdog
                    ),
                    "Noisy Control+Tab exact verified-focus readback watchdog expired for \(phase.trace). \(verifiedFocusOwner.diagnosticSummary)"
                )
                XCTAssertEqual(
                    verifiedFocusEvidence.value.windowID,
                    selection.windowID
                )
                XCTAssertEqual(
                    verifiedFocusEvidence.value.processIdentifier,
                    targetProcessIdentifier
                )
                XCTAssertTrue(
                    confirmationEvidence.activation.value.matches(
                        bundleIdentifier:
                            targetApp.identity.bundleIdentifier,
                        windowNumber: selection.windowNumber
                    ),
                    "Noisy Control+Tab exact activation readback must agree with verified-focus evidence for \(phase.trace)."
                )
            }
            currentSelection = selection
            logWorkflowSpaceObservation("\(traceLabel).afterConfirm.\(phase.trace)", app: targetApp)
        }
    }

    private func selectNoisyInAppWindowWithLayerEvidence(
        currentSelection: InAppWindowSelection,
        title: String,
        expectedPrefix: [String],
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        traceLabel: String,
        targetApp: SpaceFixtureResolvedWorkflow.App,
        targetProcessIdentifier: pid_t,
        phaseTrace: String,
        runtimeLogSnapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) throws -> InAppWindowSelection {
        let owner = FlowTabUITestInAppWindowLayerObservationOwner(
            expectedAppName: targetApp.appName,
            expectedProcessIdentifier:
                targetProcessIdentifier,
            expectedTitle: title,
            baseline: runtimeLogSnapshot
        )
        owner.start()
        defer { owner.cancel() }

        let selection = try selectNoisyInAppWindow(
            currentSelection: currentSelection,
            title: title,
            expectedPrefix: expectedPrefix,
            in: app,
            diagnosticsSummary: diagnosticsSummary,
            traceLabel: traceLabel
        )
        let evidence = try XCTUnwrap(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestInAppWindowLayerObservationPolicy
                    .watchdog
            ),
            "Noisy Control+Tab reusable Window-layer evidence watchdog "
                + "expired for \(phaseTrace). "
                + owner.diagnosticSummary
        )
        XCTAssertEqual(
            evidence.value.windowID,
            selection.windowID
        )
        XCTAssertEqual(
            evidence.value.windowNumber,
            selection.windowNumber
        )
        XCTAssertEqual(evidence.value.title, selection.title)
        return selection
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
        var latestSelection = currentSelection

        if latestSelection.title == title {
            assertNoisyInAppObservedPrefix(
                observedPrefix,
                expectedPrefix: expectedPrefix,
                traceLabel: traceLabel
            )
            return currentSelection
        }

        for attempt in 0..<attempts {
            let result =
                try performAndWaitForInAppForwardSelectionTransition(
                    fromWindowID:
                        latestSelection.windowID,
                    fromWindowNumber:
                        latestSelection.windowNumber,
                    in: app,
                    diagnosticsSummary: diagnosticsSummary,
                    traceLabel:
                        "\(traceLabel).selectAttempt.\(attempt + 1)"
                )
            latestSelection = InAppWindowSelection(
                title: result.title,
                windowID: result.windowID,
                windowNumber: result.windowNumber
            )
            observedPrefix.append(latestSelection.title)
            assertNoisyInAppObservedPrefix(
                observedPrefix,
                expectedPrefix: expectedPrefix,
                traceLabel: traceLabel
            )
            if latestSelection.title == title {
                return latestSelection
            }
        }

        XCTFail(
            """
            Noisy Control+Tab did not select \(title).
            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return latestSelection
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
        var latestSelection =
            try inAppWindowSelection(
                title:
                    switcherPanelDiagnosticsValue(
                        diagnosticsSummary,
                        key: "selectedWindowTitle"
                    ),
                windowID:
                    switcherPanelDiagnosticsValue(
                        diagnosticsSummary,
                        key: "selectedWindow"
                    )
            )

        if !requiresControlTab,
           latestSelection.title == title
        {
            return latestSelection
        }

        for attempt in 0..<attempts {
            let result =
                try performAndWaitForInAppForwardSelectionTransition(
                    fromWindowID:
                        latestSelection.windowID,
                    fromWindowNumber:
                        latestSelection.windowNumber,
                    in: app,
                    diagnosticsSummary: diagnosticsSummary,
                    traceLabel:
                        "control.selectAttempt.\(attempt + 1)"
                )
            latestSelection = InAppWindowSelection(
                title: result.title,
                windowID: result.windowID,
                windowNumber: result.windowNumber
            )
            if latestSelection.title == title {
                return latestSelection
            }
        }

        XCTFail(
            """
            Control+Tab did not select \(title). \
            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return latestSelection
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
        focusedWindow: InAppWindowSelection
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
                timeout:
                    FlowTabUITestInAppWorkflowWindowObservationPolicy
                    .fixtureReactivationWatchdog,
                trigger: {
                    fixtureApplication.activate()
                }
            )
        )
        return performAndWaitForInAppSwitcherPanelProjection(
            for: workflowApp,
            in: app,
            trigger: {
                postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                    .inApp,
                    traceLabel: "control.reopen"
                )
            }
        )
    }

}
