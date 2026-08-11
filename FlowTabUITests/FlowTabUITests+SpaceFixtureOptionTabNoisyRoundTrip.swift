import XCTest

private enum FlowTabUITestNoisyOptionTabPolicy {
    static let exactPreviewProjectionWatchdog: TimeInterval = 8
    static let switcherDismissalWatchdog: TimeInterval = 4
    static let exactSelectedWindowActivationWatchdog: TimeInterval = 12
    static let postConfirmReconciliationWatchdog: TimeInterval = 12
}

extension FlowTabUITests {
    func testNoisyOptionTabPolicyUsesNamedWatchdogs() {
        let watchdogs = [
            FlowTabUITestNoisyOptionTabPolicy.exactPreviewProjectionWatchdog,
            FlowTabUITestNoisyOptionTabPolicy.switcherDismissalWatchdog,
            FlowTabUITestNoisyOptionTabPolicy.exactSelectedWindowActivationWatchdog,
            FlowTabUITestNoisyOptionTabPolicy.postConfirmReconciliationWatchdog
        ]
        XCTAssertEqual(watchdogs[0], 8)
        XCTAssertEqual(watchdogs[1], 4)
        XCTAssertEqual(watchdogs[2], 12)
        XCTAssertEqual(watchdogs[3], 12)
        XCTAssertTrue(
            watchdogs.allSatisfy { $0.isFinite && $0 > 0 }
        )
    }

    func runNoisyOptionTabWindowStateRoundTrip(
        app: XCUIApplication,
        targetApp: SpaceFixtureResolvedWorkflow.App,
        initialDiagnosticsSummary: XCUIElement,
        primaryFullscreenTitle: String,
        traceLabel: String,
        runtimeLogSnapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) throws {
        let standardTitles = standardWorkflowWindowTitles(in: targetApp)
        let normalOneTitle = try XCTUnwrap(
            standardTitles.first,
            "Noisy Option+Tab workflow must include the first normal window."
        )
        let normalTwoTitle = try XCTUnwrap(
            standardTitles.dropFirst().first,
            "Noisy Option+Tab workflow must include a second normal window."
        )
        let fullscreenTwoTitle = try XCTUnwrap(
            targetApp.fullscreenWindowTitles.dropFirst().first,
            "Noisy Option+Tab workflow must include a second fullscreen window."
        )

        var diagnosticsSummary = initialDiagnosticsSummary
        var expectedCurrentSelection: RuntimeTruthWindowSelection?
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
                diagnosticsSummary = try relaunchGlobalSwitcher(
                    app,
                    for: targetApp,
                    traceLabel: traceLabel,
                    allowsNoisyCGSiblings: true
                )
            }

            assertNoisyOptionTabFilteredCGOnlyArtifactSource(
                since: runtimeLogSnapshot
            )
            XCTAssertTrue(
                waitForSwitcherPreviewTitles(
                    diagnosticsSummary,
                    toExactlyMatch: targetApp.expectedWindowTitles,
                    timeout:
                        FlowTabUITestNoisyOptionTabPolicy
                            .exactPreviewProjectionWatchdog
                ),
                """
                Noisy Option+Tab \(phase.trace) phase must expose exactly the four user windows.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
            let currentSelection = try assertOptionTabWindowStateCurrentSelection(
                phase.currentTitle,
                expectedSelection: expectedCurrentSelection,
                expectedPrefix: phase.expectedPrefix,
                app: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: traceLabel,
                phaseTrace: phase.trace
            )

            let selection = try selectNoisyOptionTabWindow(
                currentSelection: currentSelection,
                title: phase.targetTitle,
                expectedPrefix: phase.expectedPrefix,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: "\(traceLabel).\(phase.trace)"
            )
            assertNoisyOptionTabWindowLayerSource(
                selection,
                phaseTrace: phase.trace,
                since: runtimeLogSnapshot
            )

            let topologyLogSnapshot = makeRuntimeLogFileSnapshot()
            confirmNoisyOptionTabSelectionAndWaitForDismissal(
                diagnosticsSummary,
                traceLabel: "\(traceLabel).confirm.\(phase.trace)",
                phaseTrace: phase.trace
            )
            XCTAssertTrue(
                waitForExactFrontmostWorkflowCGWindow(
                    windowNumber: selection.windowNumber,
                    title: phase.targetTitle,
                    app: targetApp,
                    timeout:
                        FlowTabUITestNoisyOptionTabPolicy
                            .exactSelectedWindowActivationWatchdog
                ),
                "Noisy Option+Tab must activate the exact \(phase.targetTitle) CG window selected in \(phase.trace)."
            )
            assertNoisyOptionTabWindowRequestSource(
                selection,
                appID: targetApp.identity.bundleIdentifier,
                phaseTrace: phase.trace,
                since: topologyLogSnapshot
            )
            waitForRuntimeLogFiles(
                matching: #"collectCGWindows result=ready .* affected=[1-9][0-9]* signatureChanged=1 signatureDisplays=[1-9][0-9]* signatureSpaces=[1-9][0-9]* signatureWindows=[1-9][0-9]* signatureFullscreen=[0-9]+ signature=d=.*spaces=[1-9][0-9]*,windows=[1-9][0-9]*,fullscreen=[0-9]+"#,
                since: topologyLogSnapshot,
                timeout:
                    FlowTabUITestNoisyOptionTabPolicy
                        .postConfirmReconciliationWatchdog,
                description: "nonzero Space topology affected-window diff and signature diagnostics after \(phase.trace) confirm"
            )
            waitForRuntimeLogFiles(
                matching: "binding-confidence-change windowID=cg:[0-9]+:\(selection.windowNumber) cg=\(selection.windowNumber) .* source=.*->verifiedFocusReadback",
                since: topologyLogSnapshot,
                timeout:
                    FlowTabUITestNoisyOptionTabPolicy
                        .postConfirmReconciliationWatchdog,
                description: "verified-focus exact WindowRecord relearn after \(phase.trace) confirm"
            )
            topologyLogSnapshot.cancel()
            expectedCurrentSelection = selection
            logWorkflowSpaceObservation("\(traceLabel).afterConfirm.\(phase.trace)", app: targetApp)
        }
    }

    private func confirmNoisyOptionTabSelectionAndWaitForDismissal(
        _ diagnosticsSummary: XCUIElement,
        traceLabel: String,
        phaseTrace: String
    ) {
        let dismissalOwner =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: diagnosticsSummary.identifier,
                readback: { diagnosticsSummary.exists }
            )
        dismissalOwner.start()
        defer { dismissalOwner.cancel() }

        postFlowTabUITestSwitcherCommandAndWaitForDelivery(
            .confirm,
            traceLabel: traceLabel
        )
        dismissalOwner.markTriggerCompleted()

        guard
            let dismissalEvidence =
                dismissalOwner.waitForResolution(
                    timeout:
                        FlowTabUITestNoisyOptionTabPolicy
                            .switcherDismissalWatchdog
                )
        else {
            XCTFail(
                "Noisy Option+Tab \(phaseTrace) switcher dismissal "
                    + "watchdog expired. "
                    + dismissalOwner.diagnosticSummary
            )
            return
        }
        XCTAssertFalse(
            dismissalEvidence.value.exists,
            "Noisy Option+Tab \(phaseTrace) must dismiss the exact switcher diagnostics element."
        )
    }

    private func assertNoisyOptionTabFilteredCGOnlyArtifactSource(
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        waitForRuntimeLogFiles(
            matching: #"Chrome Fixture filtered-fullscreen-((sibling|host)-artifacts stage=(pre-dedupe|presentation)|duplicate-surfaces stage=presentation-final) dropped=[1-9][0-9]*"#,
            since: snapshot,
            timeout: 8,
            description: "Noisy Chrome Fixture filtered CG-only/fullscreen artifact or duplicate surface source"
        )
    }

    private func assertNoisyOptionTabWindowLayerSource(
        _ selection: RuntimeTruthWindowSelection,
        phaseTrace: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        let escapedTitle = NSRegularExpression.escapedPattern(for: selection.title)
        waitForRuntimeLogFiles(
            matching: #"window-entries app=Chrome Fixture .*id=cg:[0-9]+:\#(selection.windowNumber):title=\#(escapedTitle)[^\n]*source=stickyBinding:spaceEvidence=(observed|inferredFromTopology)"#,
            since: snapshot,
            timeout: 8,
            description: "sticky window-layer source for selected Noisy Option+Tab \(phaseTrace) window"
        )
    }

    private func assertNoisyOptionTabWindowRequestSource(
        _ selection: RuntimeTruthWindowSelection,
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
            timeout:
                FlowTabUITestNoisyOptionTabPolicy
                    .postConfirmReconciliationWatchdog,
            description: "sticky window request source for selected Noisy Option+Tab \(phaseTrace) window"
        )
    }

    private func assertOptionTabWindowStateCurrentSelection(
        _ expectedTitle: String,
        expectedSelection: RuntimeTruthWindowSelection?,
        expectedPrefix: [String],
        app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        traceLabel: String,
        phaseTrace: String
    ) throws -> RuntimeTruthWindowSelection {
        assertSwitcherSelectedWindowTitle(
            expectedTitle,
            in: app,
            diagnosticsSummary: diagnosticsSummary,
            message: "Noisy Option+Tab \(phaseTrace) phase must enter window state on \(expectedTitle)."
        )
        let latestTitle = switcherPanelDiagnosticsValue(
            diagnosticsSummary,
            key: "selectedWindowTitle"
        )
        let latestWindowID = switcherPanelDiagnosticsValue(
            diagnosticsSummary,
            key: "selectedWindow"
        )
        let selection = try runtimeTruthWindowSelection(title: latestTitle, windowID: latestWindowID)
        logFlowTabUITestTrace(
            "[\(traceLabel).current.\(phaseTrace)] selected=\(latestTitle) windowID=\(latestWindowID)"
        )
        XCTAssertEqual(
            Array(expectedPrefix.prefix(1)),
            [selection.title],
            "Noisy Option+Tab \(phaseTrace) phase must start with the first expected app-local recency window."
        )
        if let expectedSelection {
            XCTAssertEqual(
                selection,
                expectedSelection,
                """
                Noisy Option+Tab \(phaseTrace) phase must reopen from the previously activated window.
                Expected \(expectedSelection.title) / \(expectedSelection.windowNumber), \
                found \(selection.title) / \(selection.windowNumber).
                """
            )
        }
        return selection
    }

    private func selectNoisyOptionTabWindow(
        currentSelection: RuntimeTruthWindowSelection,
        title: String,
        expectedPrefix: [String],
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        traceLabel: String
    ) throws -> RuntimeTruthWindowSelection {
        var observedPrefix = [currentSelection.title]
        let maximumSelectionAdvances = max(
            1,
            switcherPreviewTitles(
                from: diagnosticsSummary
            ).count + 3
        )
        var latestSelection = currentSelection

        if latestSelection.title == title {
            assertNoisyOptionTabObservedPrefix(
                observedPrefix,
                expectedPrefix: expectedPrefix,
                traceLabel: traceLabel
            )
            return currentSelection
        }

        for attempt in 0..<maximumSelectionAdvances {
            latestSelection =
                try performAndWaitForSwitcherWindowSelectionTransition(
                    from: latestSelection,
                    in: app,
                    diagnosticsSummary: diagnosticsSummary,
                    traceLabel:
                        "\(traceLabel).selectAttempt.\(attempt + 1)",
                    trigger: {
                        postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                            .advanceRight,
                            traceLabel:
                                "\(traceLabel).selectWindow"
                        )
                    }
                )
            observedPrefix.append(latestSelection.title)
            logFlowTabUITestTrace(
                "[\(traceLabel).selectAttempt.\(attempt + 1)] "
                    + "target=\(title) "
                    + "selected=\(latestSelection.title) "
                    + "windowNumber="
                    + "\(latestSelection.windowNumber)"
            )
            assertNoisyOptionTabObservedPrefix(
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
            Option+Tab window state did not select \(title).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return latestSelection
    }

    private func assertNoisyOptionTabObservedPrefix(
        _ observedPrefix: [String],
        expectedPrefix: [String],
        traceLabel: String
    ) {
        let prefixLength = min(observedPrefix.count, expectedPrefix.count)
        XCTAssertEqual(
            Array(observedPrefix.prefix(prefixLength)),
            Array(expectedPrefix.prefix(prefixLength)),
            "Noisy Option+Tab \(traceLabel) window order must follow app-local recency before fallback."
        )
    }

}
