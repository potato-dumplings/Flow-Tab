import XCTest

extension FlowTabUITests {
    func testSwitcherPanelOptionTabReportsUnverifiedSpaceBackedCGOnlyWorkflowActivation() throws {
        let workflow = try configuredSpaceBackedRuntimeTruthWorkflow()
        let targetApp = try XCTUnwrap(workflow.apps.first)
        let targetTitle = "Recovered Window"
        var runtimeLogSnapshot = makeRuntimeLogFileSnapshot()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: runtimeTruthSwitcherLaunchArguments(),
            waitsForFullscreenMarkers: false,
            validatesPermissionsBeforeFixtureLaunch: true,
            beforeFlowTabLaunch: { _ in
                runtimeLogSnapshot = self.makeRuntimeLogFileSnapshot()
            },
            flowTabLaunchTraceLabel: "option.spaceBacked"
        ) { _, app in
            waitForSpaceBackedWindowLayerProjection(
                title: targetTitle,
                appName: targetApp.appName,
                since: runtimeLogSnapshot
            )
            let diagnosticsSummary = try assertGlobalSwitcherWindowStateReady(
                for: targetApp,
                in: app,
                traceLabel: "option.spaceBacked"
            )
            let selection = try selectGlobalSwitcherWindow(
                title: targetTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: "option.spaceBacked"
            )
            assertSpaceBackedWindowLayerSource(
                selection,
                appName: targetApp.appName,
                since: runtimeLogSnapshot
            )

            let activationLogSnapshot = makeRuntimeLogFileSnapshot()
            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.confirm, traceLabel: "option.spaceBacked.confirm")
            XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 4))
            assertSpaceBackedWindowRequestSource(
                selection,
                appID: targetApp.identity.bundleIdentifier,
                since: activationLogSnapshot
            )
            assertSpaceBackedCGActivationRoute(
                selection,
                since: activationLogSnapshot
            )
            assertSpaceBackedCGActivationReadbackFailure(
                selection,
                since: activationLogSnapshot
            )
        }
    }

    func testSwitcherPanelOptionTabHidesDesktopProvisionalCGOnlyWorkflowWindow() throws {
        let workflow = try configuredProvisionalHiddenRuntimeTruthWorkflow()
        let targetApp = try XCTUnwrap(workflow.apps.first)
        let hiddenTitle = "Hidden CG Window"
        var runtimeLogSnapshot = makeRuntimeLogFileSnapshot()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: runtimeTruthSwitcherLaunchArguments(),
            waitsForFullscreenMarkers: false,
            validatesPermissionsBeforeFixtureLaunch: true,
            beforeFlowTabLaunch: { _ in
                runtimeLogSnapshot = self.makeRuntimeLogFileSnapshot()
            },
            flowTabLaunchTraceLabel: "option.provisionalHidden"
        ) { _, app in
            assertHiddenProvisionalCGOnlyRuntimeLog(appName: targetApp.appName, since: runtimeLogSnapshot)
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)

            _ = try performAndWaitForSwitcherAppSelection(
                in: app,
                bundleIdentifier: targetApp.identity.bundleIdentifier,
                appProjectionExpectation:
                    .exactEntry(
                        targetApp.identity.bundleIdentifier
                            + ":1"
                    ),
                timeout:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .switcherDiagnosticsAppSelectionProjectionApplication,
                trigger: {
                    postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                        .global,
                        traceLabel:
                            "option.provisionalHidden"
                    )
                    try FlowTabUITestSwitcherCommandPayload.write(
                        targetApp.identity.bundleIdentifier
                    )
                    postFlowTabUITestSwitcherCommand(
                        .selectApp,
                        traceLabel:
                            "option.provisionalHidden.selectApp"
                    )
                }
            )

            let advanceEvidenceSnapshot =
                makeRuntimeLogFileSnapshot()
            postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                .advanceDown,
                traceLabel: "option.provisionalHidden.enterWindowState"
            )
            let escapedAppName =
                NSRegularExpression.escapedPattern(
                    for: targetApp.appName
                )
            waitForRuntimeLogFiles(
                matching:
                    "advance key=downArrow "
                    + "app=\(escapedAppName) "
                    + "windows=1 mode=appCycle",
                since: advanceEvidenceSnapshot,
                timeout: 4,
                description:
                    "single eligible window remains in app cycle "
                    + "after manual Down"
            )
            XCTAssertFalse(
                switcherPanelDiagnosticsValue(diagnosticsSummary, key: "mode").hasPrefix("windowCycle"),
                """
                Option+Tab must not enter a two-window cycle when the only second window is provisional CG-only.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
            XCTAssertEqual(
                switcherPanelDiagnosticsValue(diagnosticsSummary, key: "preview"),
                "inactive",
                """
                Provisional-only hidden windows must not create a visible switcher preview layer.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
            XCTAssertFalse(
                switcherPreviewTitles(from: diagnosticsSummary).contains(hiddenTitle),
                "Desktop provisional CG-only \(hiddenTitle) must not enter the main switcher window layer."
            )
        }
    }

    private func configuredSpaceBackedRuntimeTruthWorkflow() throws -> SpaceFixtureResolvedWorkflow {
        try configuredOptionTabRuntimeTruthWorkflow(
            sourceURL: SpaceFixtureMultiAppWorkflowDefaults.optionTabSpaceBackedRuntimeTruthWorkflowSourceURL
        )
    }

    private func configuredProvisionalHiddenRuntimeTruthWorkflow() throws -> SpaceFixtureResolvedWorkflow {
        try configuredOptionTabRuntimeTruthWorkflow(
            sourceURL: SpaceFixtureMultiAppWorkflowDefaults.optionTabProvisionalHiddenRuntimeTruthWorkflowSourceURL
        )
    }

    private func configuredOptionTabRuntimeTruthWorkflow(
        sourceURL: URL
    ) throws -> SpaceFixtureResolvedWorkflow {
        do {
            let installedWorkflow = try SpaceFixtureResolvedWorkflow.configured()
            let workflow = try resolveSpaceFixtureWorkflowScenario(
                sourceWorkflowURL: sourceURL,
                using: installedWorkflow
            )
            try validateAXSuppressedRuntimeTruthWorkflow(workflow)
            return workflow
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            switch error {
            case .missingWorkflowPath, .workflowScenarioMissingAppVariant, .workflowScenarioBundleIdentifierMismatch:
                throw XCTSkip(
                    """
                    \(error.localizedDescription)

                    Build or refresh the shared fixture app variants with:
                      ./scripts/testing/build-space-fixture-workflow.sh --workflow-config docs/fixtures/space-fixture-home-multi-app-workflow.json

                    Scenario source:
                      \(sourceURL.path)
                    """
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

    private func validateAXSuppressedRuntimeTruthWorkflow(_ workflow: SpaceFixtureResolvedWorkflow) throws {
        guard workflow.apps.count == 1 else {
            throw XCTSkip("AX-suppressed runtime truth workflow must contain exactly one fixture app.")
        }
        guard workflow.apps[0].windowCount >= 2 else {
            throw XCTSkip("AX-suppressed runtime truth workflow must contain a visible readiness window and a CG-only target window.")
        }
        guard workflow.hasUniqueExpectedWindowTitles else {
            throw XCTSkip("AX-suppressed runtime truth workflow must define unique expected window titles.")
        }
    }

    private func waitForSpaceBackedWindowLayerProjection(
        title: String,
        appName: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        let escapedAppName = NSRegularExpression.escapedPattern(for: appName)
        let escapedTitle = NSRegularExpression.escapedPattern(for: title)
        waitForRuntimeLogFiles(
            matching: #"window-entries app=\#(escapedAppName) .*title=\#(escapedTitle)[^\n]*ax=0[^\n]*sticky=0[^\n]*source=nil:spaceEvidence=(observed|inferredFromTopology|inferredFromFullscreenGeometry):publicAXRecovery=1"#,
            since: snapshot,
            timeout: 8,
            description: "space-backed CG-only window-layer projection before switcher trigger"
        )
    }

    private func assertSpaceBackedWindowLayerSource(
        _ selection: RuntimeTruthWindowSelection,
        appName: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        let escapedAppName = NSRegularExpression.escapedPattern(for: appName)
        let escapedTitle = NSRegularExpression.escapedPattern(for: selection.title)
        waitForRuntimeLogFiles(
            matching: #"window-entries app=\#(escapedAppName) .*id=cg:[0-9]+:\#(selection.windowNumber):title=\#(escapedTitle)[^\n]*ax=0:cg=\#(selection.windowNumber):sticky=0:source=nil:spaceEvidence=(observed|inferredFromTopology|inferredFromFullscreenGeometry):publicAXRecovery=1"#,
            since: snapshot,
            timeout: 8,
            description: "space-backed CG-only window-layer source"
        )
    }

    private func assertSpaceBackedWindowRequestSource(
        _ selection: RuntimeTruthWindowSelection,
        appID: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        let escapedAppID = NSRegularExpression.escapedPattern(for: appID)
        let escapedTitle = NSRegularExpression.escapedPattern(for: selection.title)
        waitForRuntimeLogFiles(
            matching: #"window-request appID=\#(escapedAppID) pid=[0-9]+ windowID=cg:[0-9]+:\#(selection.windowNumber) title=\#(escapedTitle)[^\n]*ax=0[^\n]*sticky=false source=nil publicAXRecovery=1"#,
            since: snapshot,
            timeout: 8,
            description: "space-backed CG-only window request source"
        )
    }

    private func assertSpaceBackedCGActivationRoute(
        _ selection: RuntimeTruthWindowSelection,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        waitForRuntimeLogFiles(
            matching: #"focus-attempt route=cg result=[a-zA-Z]+ pid=[0-9]+ windowID=cg:[0-9]+:\#(selection.windowNumber) targetCG=\#(selection.windowNumber)"#,
            since: snapshot,
            timeout: 8,
            description: "space-backed CG-only activation route"
        )
    }

    private func assertSpaceBackedCGActivationReadbackFailure(
        _ selection: RuntimeTruthWindowSelection,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        waitForRuntimeLogFiles(
            matching: #"binding-readback-mismatch route=cg pid=[0-9]+ windowID=cg:[0-9]+:\#(selection.windowNumber) reason=targetCGNotVisible targetCG=\#(selection.windowNumber)"#,
            since: snapshot,
            timeout: 8,
            description: "space-backed CG-only activation readback mismatch"
        )
        waitForRuntimeLogFiles(
            matching: #"focus-recovery exhausted generation=[0-9]+ attempts=[0-9]+ pid=[0-9]+ windowID=cg:[0-9]+:\#(selection.windowNumber) targetCG=\#(selection.windowNumber)"#,
            since: snapshot,
            timeout: 8,
            description: "space-backed CG-only activation recovery exhaustion"
        )
    }

    private func assertHiddenProvisionalCGOnlyRuntimeLog(
        appName: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        let escapedAppName = NSRegularExpression.escapedPattern(for: appName)
        waitForRuntimeLogFiles(
            matching: #"\#(escapedAppName) hidden-provisional-cg windows=1"#,
            since: snapshot,
            timeout: 8,
            description: "desktop provisional CG-only hidden from window layer"
        )
    }

}
