import AppKit
import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
    func testSwitcherPanelShowsAllWorkflowAppsInMultiAppFixtureStrip() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { workflow, app in
            _ = waitForSpaceFixtureSwitcherAppStripProjection(
                workflow,
                in: app
            )
        }
    }

    func testSwitcherPanelPreviewCyclesThroughWorkflowAppsWithoutMixingWindowCards() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level", "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            guard waitForSpaceFixtureSwitcherAppStripProjection(
                workflow,
                in: app,
                trigger: {
                    self.postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                        .global,
                        traceLabel: "multi-app-preview.initial"
                    )
                }
            ) != nil else { return }
            selectSwitcherWorkflowApp(workflow.apps[0], in: app, diagnosticsSummary: diagnosticsSummary)

            var observedAppIDs: [String] = []
            for workflowApp in workflow.apps {
                selectSwitcherWorkflowApp(workflowApp, in: app, diagnosticsSummary: diagnosticsSummary)
                guard
                    performAndWaitForSwitcherSelectedAppPreviewTransition(
                        workflowApp,
                        in: app,
                        diagnosticsSummaryElement:
                            diagnosticsSummary,
                        trigger: {
                            app.typeKey(
                                .downArrow,
                                modifierFlags: []
                            )
                        }
                    ) != nil
                else {
                    return
                }
                XCTAssertFalse(
                    observedAppIDs.contains(workflowApp.appID),
                    "Switcher app cycle repeated \(workflowApp.appName) before visiting every workflow app"
                )
                observedAppIDs.append(workflowApp.appID)

                guard exitSwitcherPreview(workflowApp, in: app, diagnostics: diagnosticsSummary) else { return }
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
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            guard waitForSpaceFixtureSwitcherAppStripProjection(
                workflow,
                in: app
            ) != nil else { return }
            selectSwitcherWorkflowApp(workflow.apps[0], in: app, diagnosticsSummary: diagnosticsSummary)

            var observedAppIDs: [String] = []
            var previousWindowCardIdentifiers: Set<String> = []
            for workflowApp in workflow.apps {
                selectSwitcherWorkflowApp(workflowApp, in: app, diagnosticsSummary: diagnosticsSummary)
                let windowCards = try assertSwitcherPreviewWindowCards(
                    in: app,
                    diagnosticsSummary: diagnosticsSummary,
                    selectedApp: workflowApp,
                    excludedTitles: workflow.otherExpectedWindowTitles(
                        excluding: workflowApp.appID
                    ),
                    previousWindowCardIdentifiers:
                        previousWindowCardIdentifiers,
                    trigger: {
                        app.typeKey(
                            .downArrow,
                            modifierFlags: []
                        )
                    }
                )
                let selectedApp = try XCTUnwrap(
                    matchedWorkflowAppForVisibleSwitcherPreview(
                        workflow,
                        diagnosticsSummaryElement: diagnosticsSummary,
                        excludingAppIDs: Set(observedAppIDs)
                    ),
                    """
                    Switcher preview did not stabilize to a single workflow app window set.

                    \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))

                    \(self.multiAppWorkflowSetupMessage(
                        reason: "Resolved switcher workflow window titles did not match a single app.",
                        scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
                    ))
                    """
                )
                XCTAssertEqual(
                    selectedApp.appID,
                    workflowApp.appID,
                    "Switcher cards should belong to the explicitly selected workflow app"
                )
                XCTAssertFalse(
                    observedAppIDs.contains(selectedApp.appID),
                    "Switcher app cycle repeated \(selectedApp.appName) before visiting every workflow app"
                )
                observedAppIDs.append(selectedApp.appID)

                previousWindowCardIdentifiers = Set(windowCards.map(\.identifier))

                guard exitSwitcherPreview(selectedApp, in: app, diagnostics: diagnosticsSummary) else { return }
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

        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "window"
            ]
                + FlowTabUITestSwitcherSearchConfirmationPolicy
                    .applicationEvidenceLaunchArguments
        ) { _, app in
            let searchInput =
                requireInitialFlowTabSearchInput(
                    in: app,
                    observedBy: readiness
                )

            guard let result = performAndWaitForCommittedSearchWindowResult(
                in: app,
                scope: "window",
                query: targetWindowTitle,
                title: targetWindowTitle,
                appName: targetApp.appName,
                timeout:
                    FlowTabUITestWindowSearchQueryProjectionPolicy
                        .multiAppResultPublicationWatchdog,
                trigger: {
                    app.typeText(targetWindowTitle)
                }
            ) else { return }
            let targetWindowNumber = try XCTUnwrap(
                result.windowNumber,
                "Search result \(result.identifier) did not expose a CG window number."
            )

            XCTAssertTrue(
                triggerAndWaitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout:
                        FlowTabUITestWorkflowWindowActivationObservationPolicy
                            .multiAppWindowSearchActivationWatchdog,
                    trigger: {
                        confirmSwitcherSearchSelection(
                            in: app,
                            searchInput: searchInput,
                            expectedQuery: targetWindowTitle
                        )
                    }
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

        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "app"
            ]
                + FlowTabUITestSwitcherSearchConfirmationPolicy
                    .applicationEvidenceLaunchArguments
        ) { _, app in
            let searchInput =
                requireInitialFlowTabSearchInput(
                    in: app,
                    observedBy: readiness
                )
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "The app-scope activation scenario must start outside the target fixture app."
            )

            XCTAssertTrue(
                performAndWaitForCommittedSearchResultRow(
                    in: app,
                    scope: "app",
                    query:
                        targetApp.identity.switcherSearchQuery,
                    resultID:
                        "app:"
                        + targetApp.identity.bundleIdentifier,
                    rowIdentifier:
                        targetApp.identity
                            .switcherSearchAppAccessibilityIdentifier,
                    timeout:
                        FlowTabUITestSwitcherSearchResultObservationPolicy
                            .multiAppAppSearchResultPublicationWatchdog,
                    trigger: {
                        app.typeText(
                            targetApp.identity.switcherSearchQuery
                        )
                    }
                ),
                "FlowTab did not publish \(targetApp.appName) as the "
                    + "exact committed App Search result."
            )

            assertTriggerMakesApplicationFrontmost(
                targetApp.identity.bundleIdentifier,
                timeout: 10,
                message:
                    "Search confirmation did not activate "
                    + "the \(targetApp.appName) fixture app."
            ) {
                confirmSwitcherSearchSelection(
                    in: app,
                    searchInput: searchInput,
                    expectedQuery:
                        targetApp.identity.switcherSearchQuery
                )
            }
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

        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "-searchDefaultScope",
                "window"
            ]
                + FlowTabUITestSwitcherSearchConfirmationPolicy
                    .applicationEvidenceLaunchArguments
        ) { _, app in
            let searchInput =
                requireInitialFlowTabSearchInput(
                    in: app,
                    observedBy: readiness
                )
            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "The fullscreen activation scenario must start outside the target fixture app."
            )

            guard let result = performAndWaitForCommittedSearchWindowResult(
                in: app,
                scope: "window",
                query: targetWindowTitle,
                title: targetWindowTitle,
                appName: targetApp.appName,
                timeout:
                    FlowTabUITestWindowSearchQueryProjectionPolicy
                        .multiAppResultPublicationWatchdog,
                trigger: {
                    app.typeText(targetWindowTitle)
                }
            ) else { return }
            let targetWindowNumber = try XCTUnwrap(
                result.windowNumber,
                "Search result \(result.identifier) did not expose a CG window number."
            )

            let panelDismissal =
                FlowTabUITestElementNonExistenceObservationOwner(
                    elementIdentifier: diagnosticsSummary.identifier,
                    readback: {
                        diagnosticsSummary.exists
                    }
                )
            panelDismissal.start()
            defer { panelDismissal.cancel() }
            guard panelDismissal.latestEvidence?.value.exists == true else {
                XCTFail(
                    "Fullscreen Window Search panel baseline mismatch; "
                        + "expectedExists=1. "
                        + panelDismissal.diagnosticSummary
                )
                return
            }

            guard
                triggerAndWaitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout:
                        FlowTabUITestWorkflowWindowActivationObservationPolicy
                            .fullscreenMultiAppWindowSearchActivationWatchdog,
                    trigger: {
                        confirmSwitcherSearchSelection(
                            in: app,
                            searchInput: searchInput,
                            expectedQuery: targetWindowTitle
                        )
                        panelDismissal.markTriggerCompleted()
                    }
                )
            else { return }
            guard
                panelDismissal.waitForResolution(
                    timeout:
                        FlowTabUITestElementNonExistenceObservationPolicy
                            .fullscreenMultiAppWindowSearchPanelDismissalWatchdog
                ) != nil
            else {
                XCTFail(
                    "FlowTab panel remained visible after confirming the "
                        + "fullscreen window target. "
                        + panelDismissal.diagnosticSummary
                )
                return
            }
        }
    }

    func configuredSwitcherSpaceFixtureWorkflow(
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

    func configuredSwitcherRuntimeTruthWorkflow(
        sourceWorkflowURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SpaceFixtureResolvedWorkflow {
        do {
            let installedWorkflow = try SpaceFixtureResolvedWorkflow.configured(environment: environment)
            let workflow = try resolveSpaceFixtureWorkflowScenario(
                sourceWorkflowURL: sourceWorkflowURL,
                using: installedWorkflow
            )
            try validateSwitcherRuntimeTruthWorkflow(workflow, scenarioSourceURL: sourceWorkflowURL)
            return workflow
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            switch error {
            case .missingWorkflowPath, .workflowScenarioMissingAppVariant, .workflowScenarioBundleIdentifierMismatch:
                throw XCTSkip(
                    multiAppWorkflowSetupMessage(
                        reason: error.localizedDescription,
                        scenarioSourceURL: sourceWorkflowURL
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

    func fullscreenWindowTitle(in workflowApp: SpaceFixtureResolvedWorkflow.App) -> String? {
        workflowApp.fullscreenWindowTitles.first
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

    private func validateSwitcherRuntimeTruthWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow,
        scenarioSourceURL: URL
    ) throws {
        guard workflow.apps.count == 1 else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow must contain exactly one fixture app for this runtime-truth scenario.",
                    scenarioSourceURL: scenarioSourceURL
                )
            )
        }

        guard workflow.apps[0].windowCount >= 2 else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow must contain at least two windows for this runtime-truth scenario.",
                    scenarioSourceURL: scenarioSourceURL
                )
            )
        }

        guard workflow.apps[0].fullscreenWindowIndex != nil else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow is missing the fullscreen sibling for this runtime-truth scenario.",
                    scenarioSourceURL: scenarioSourceURL
                )
            )
        }

        guard workflow.hasUniqueExpectedWindowTitles else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow does not define unique window titles for this runtime-truth scenario.",
                    scenarioSourceURL: scenarioSourceURL
                )
            )
        }
    }

    private func assertSwitcherPreviewWindowCards(
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        selectedApp: SpaceFixtureResolvedWorkflow.App,
        excludedTitles: [String],
        previousWindowCardIdentifiers: Set<String>,
        trigger: () -> Void
    ) throws -> [SwitcherWindowCardObservation] {
        let expectation =
            FlowTabUITestSwitcherWindowCardExpectation(
                expectedTitles: selectedApp.expectedWindowTitles,
                excludedTitles: excludedTitles,
                previousWindowCardIdentifiers:
                    previousWindowCardIdentifiers
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestSwitcherWindowCardObservationOwner(
                expectation: expectation,
                acceptsResolution: {
                    triggerDidComplete
                },
                readback: {
                    FlowTabUITestSwitcherWindowCardSnapshot(
                        cards:
                            self.switcherWindowCardObservations(
                                in: app
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)

        if let evidence = owner.waitForResolution(
            timeout: FlowTabUITestSwitcherWindowCardPolicy.multiAppCardIdentityProjectionWatchdog
        ) {
            return evidence.value.cards
        }

        XCTFail(
            """
            Switcher window-card identity watchdog expired for \
            \(selectedApp.appName).

            \(owner.diagnosticSummary)

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return owner.latestSnapshot?.cards ?? []
    }

    func searchWindowResultObservations(
        in app: XCUIApplication
    ) -> [SwitcherSearchWindowResultObservation] {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let diagnosticResults = searchWindowResultObservations(from: diagnosticsSummary)
        if !diagnosticResults.isEmpty {
            return diagnosticResults
        }
        return searchWindowResultObservationsFromElements(in: app)
    }

    func searchWindowResultObservations(
        from diagnosticsSummaryElement: XCUIElement
    ) -> [SwitcherSearchWindowResultObservation] {
        searchWindowResultObservations(
            inDiagnosticsProjection:
                switcherPanelDiagnosticsValue(
                    diagnosticsSummaryElement,
                    key: "searchResults"
                )
        )
    }

    private func searchWindowResultObservationsFromElements(in app: XCUIApplication) -> [SwitcherSearchWindowResultObservation] {
        let identifierPrefix = "flowtab.switcher.search.window."
        var seenIdentifiers: Set<String> = []
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
            .allElementsBoundByIndex
            .compactMap { element -> SwitcherSearchWindowResultObservation? in
                guard element.exists else { return nil }
                let identifier = element.identifier
                guard seenIdentifiers.insert(identifier).inserted else { return nil }

                let searchableText = [element.label, elementStringValue(element)]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                return SwitcherSearchWindowResultObservation(
                    identifier: identifier,
                    searchableText: searchableText
                )
            }
    }

    func switcherAppStripSummary(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String {
        "\(workflowApp.identity.bundleIdentifier):\(workflowApp.windowCount)"
    }

    func visibleFullscreenWindowTitle(
        in diagnosticsSummary: XCUIElement,
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String? {
        let previewTitles = Set(switcherPreviewTitles(from: diagnosticsSummary))
        return workflowApp.fullscreenWindowTitles.first { previewTitles.contains($0) }
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

    func switcherDebugSummary(
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
