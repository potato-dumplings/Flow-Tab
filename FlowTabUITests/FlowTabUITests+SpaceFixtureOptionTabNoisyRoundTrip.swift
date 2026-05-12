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
        let phases: [(currentTitle: String, targetTitle: String, trace: String)] = [
            (primaryFullscreenTitle, normalOneTitle, "normal1"),
            (normalOneTitle, primaryFullscreenTitle, "fullscreen1"),
            (primaryFullscreenTitle, normalTwoTitle, "normal2"),
            (normalTwoTitle, fullscreenTwoTitle, "fullscreen2")
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
            _ = try assertOptionTabWindowStateCurrentSelection(
                phase.currentTitle,
                expectedSelection: expectedCurrentSelection,
                app: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: traceLabel,
                phaseTrace: phase.trace
            )

            let selection = try selectGlobalSwitcherWindow(
                title: phase.targetTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: "\(traceLabel).\(phase.trace)"
            )

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
            expectedCurrentSelection = selection
            logWorkflowSpaceObservation("\(traceLabel).afterConfirm.\(phase.trace)", app: targetApp)
        }
    }

    private func assertOptionTabWindowStateCurrentSelection(
        _ expectedTitle: String,
        expectedSelection: RuntimeTruthWindowSelection?,
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
