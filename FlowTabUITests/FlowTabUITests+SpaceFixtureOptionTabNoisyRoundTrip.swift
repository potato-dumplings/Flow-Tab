import XCTest

extension FlowTabUITests {
    func runNoisyOptionTabWindowStateRoundTrip(
        app: XCUIApplication,
        targetApp: SpaceFixtureResolvedWorkflow.App,
        initialDiagnosticsSummary: XCUIElement,
        primaryFullscreenTitle: String,
        traceLabel: String
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
                [normalOneTitle, primaryFullscreenTitle],
                "fullscreen1"
            ),
            (
                primaryFullscreenTitle,
                normalTwoTitle,
                [primaryFullscreenTitle, normalOneTitle, normalTwoTitle],
                "normal2"
            ),
            (
                normalTwoTitle,
                fullscreenTwoTitle,
                [normalTwoTitle, primaryFullscreenTitle, normalOneTitle, fullscreenTwoTitle],
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

            XCTAssertTrue(
                waitForExactNoisyOptionTabPreviewTitles(
                    diagnosticsSummary,
                    for: targetApp,
                    timeout: 8
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

            let topologyLogSnapshot = makeRuntimeLogFileSnapshot()
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
                "Noisy Option+Tab must activate the exact \(phase.targetTitle) CG window selected in \(phase.trace)."
            )
            waitForRuntimeLogFiles(
                matching: #"collectCGWindows result=ready .* affected=[1-9][0-9]*"#,
                since: topologyLogSnapshot,
                timeout: 8,
                description: "nonzero Space topology affected-window diff after \(phase.trace) confirm"
            )
            waitForRuntimeLogFiles(
                matching: "binding-confidence-change windowID=cg:[0-9]+:\(selection.windowNumber) cg=\(selection.windowNumber) .* source=.*->verifiedFocusReadback",
                since: topologyLogSnapshot,
                timeout: 8,
                description: "verified-focus exact WindowRecord relearn after \(phase.trace) confirm"
            )
            expectedCurrentSelection = selection
            logWorkflowSpaceObservation("\(traceLabel).afterConfirm.\(phase.trace)", app: targetApp)
        }
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
        let attempts = max(1, switcherPreviewTitles(from: diagnosticsSummary).count + 3)
        var latestTitle = currentSelection.title
        var latestWindowID = "cg:\(currentSelection.windowNumber)"

        if latestTitle == title {
            assertNoisyOptionTabObservedPrefix(
                observedPrefix,
                expectedPrefix: expectedPrefix,
                traceLabel: traceLabel
            )
            return currentSelection
        }

        for attempt in 0..<attempts {
            postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                .advanceRight,
                traceLabel: "\(traceLabel).selectWindow"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            latestTitle = switcherPanelDiagnosticsValue(
                diagnosticsSummary,
                key: "selectedWindowTitle"
            )
            latestWindowID = switcherPanelDiagnosticsValue(
                diagnosticsSummary,
                key: "selectedWindow"
            )
            observedPrefix.append(latestTitle)
            logFlowTabUITestTrace(
                "[\(traceLabel).selectAttempt.\(attempt + 1)] target=\(title) selected=\(latestTitle) windowID=\(latestWindowID)"
            )
            assertNoisyOptionTabObservedPrefix(
                observedPrefix,
                expectedPrefix: expectedPrefix,
                traceLabel: traceLabel
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

    private func waitForExactNoisyOptionTabPreviewTitles(
        _ diagnosticsSummary: XCUIElement,
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let expectedTitles = Set(workflowApp.expectedWindowTitles)
        let expectedCount = workflowApp.expectedWindowTitles.count
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let previewTitles = switcherPreviewTitles(from: diagnosticsSummary)
            if previewTitles.count == expectedCount && Set(previewTitles) == expectedTitles {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }
}
