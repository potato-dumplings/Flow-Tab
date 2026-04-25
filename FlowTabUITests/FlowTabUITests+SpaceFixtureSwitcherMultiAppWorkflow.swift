import Foundation
import XCTest

extension FlowTabUITests {
    func testSwitcherPanelShowsAllWorkflowAppsInMultiAppFixtureStrip() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: "flowtab.testing.switcher.summary")

            for workflowApp in workflow.apps {
                assertSwitcherAppStripContainsWorkflowApp(
                    workflowApp,
                    in: app,
                    diagnosticsSummary: diagnosticsSummary
                )
                if diagnosticsSummary.exists {
                    XCTAssertTrue(
                        waitForSwitcherAppsSummary(
                            diagnosticsSummary,
                            toContain: switcherAppStripSummary(for: workflowApp),
                            timeout: 2
                        ),
                        """
                        FlowTab did not include \(workflowApp.appName) in the switcher diagnostics summary.

                        \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                        """
                    )
                }
            }
        }
    }

    private func assertSwitcherAppStripContainsWorkflowApp(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement
    ) {
        let appTile = element(in: app, identifier: workflowApp.identity.switcherAppAccessibilityIdentifier)
        XCTAssertTrue(
            appTile.waitForExistence(timeout: 8),
            """
            FlowTab did not expose \(workflowApp.appName) through \
            \(workflowApp.identity.switcherAppAccessibilityIdentifier).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
    }

    func testSwitcherPanelPreviewCyclesThroughWorkflowAppsWithoutMixingWindowCards() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { workflow, app in
            let diagnosticsSummary = element(in: app, identifier: "flowtab.testing.switcher.summary")
            XCTAssertTrue(
                element(
                    in: app,
                    identifier: workflow.apps[0].identity.switcherAppAccessibilityIdentifier
                ).waitForExistence(timeout: 8)
            )
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))

            var observedAppIDs: [String] = []
            for index in workflow.apps.indices {
                if index > 0 {
                    app.typeKey(.rightArrow, modifierFlags: [])
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                }

                app.typeKey(.downArrow, modifierFlags: [])
                let selectedApp = try XCTUnwrap(
                    matchedWorkflowAppForVisibleSwitcherPreview(
                        workflow,
                        diagnosticsSummaryElement: diagnosticsSummary,
                        excludingAppIDs: Set(observedAppIDs)
                    ),
                    """
                    Switcher preview did not stabilize to a single workflow app window set.

                    \(self.multiAppWorkflowSetupMessage(
                        reason: "Resolved switcher workflow window titles did not match a single app.",
                        scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.switcherWorkflowSourceURL
                    ))
                    """
                )
                XCTAssertFalse(
                    observedAppIDs.contains(selectedApp.appID),
                    "Switcher app cycle repeated \(selectedApp.appName) before visiting every workflow app"
                )
                observedAppIDs.append(selectedApp.appID)
                let visibleTitles = switcherPreviewTitles(from: diagnosticsSummary)
                XCTAssertEqual(Set(visibleTitles), Set(selectedApp.expectedWindowTitles))
                assertSwitcherPreviewShowsOnlyExpectedTitles(
                    selectedApp.expectedWindowTitles,
                    in: diagnosticsSummary,
                    timeout: 8
                )

                app.typeKey(.upArrow, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }

            XCTAssertEqual(Set(observedAppIDs), Set(workflow.apps.map(\.appID)))
        }
    }

    private func configuredSwitcherSpaceFixtureWorkflow(
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

    private func matchedWorkflowAppForVisibleSwitcherPreview(
        _ workflow: SpaceFixtureResolvedWorkflow,
        diagnosticsSummaryElement: XCUIElement,
        excludingAppIDs: Set<String> = []
    ) -> SpaceFixtureResolvedWorkflow.App? {
        let deadline = Date().addingTimeInterval(12)
        repeat {
            let selectedBundleIdentifier = switcherPanelDiagnosticsValue(
                diagnosticsSummaryElement,
                key: "selected"
            )
            let visibleTitles = switcherPreviewTitles(from: diagnosticsSummaryElement)
            for workflowApp in workflow.apps {
                guard !excludingAppIDs.contains(workflowApp.appID) else {
                    continue
                }
                guard selectedBundleIdentifier == workflowApp.identity.bundleIdentifier else {
                    continue
                }
                if Set(visibleTitles) == Set(workflowApp.expectedWindowTitles) {
                    return workflowApp
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    private func assertSwitcherPreviewShowsOnlyExpectedTitles(
        _ expectedTitles: [String],
        in diagnosticsSummaryElement: XCUIElement,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var visibleTitles: [String] = []
        repeat {
            visibleTitles = switcherPreviewTitles(from: diagnosticsSummaryElement)
            if Set(visibleTitles) == Set(expectedTitles) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTAssertEqual(
            Set(visibleTitles),
            Set(expectedTitles),
            """
            Expected switcher preview titles \(expectedTitles.sorted()), \
            found \(visibleTitles.sorted())
            """
        )
    }

    private func switcherAppStripSummary(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String {
        "\(workflowApp.identity.bundleIdentifier):\(workflowApp.windowCount)"
    }

    private func waitForSwitcherAppsSummary(
        _ diagnosticsSummaryElement: XCUIElement,
        toContain expectedEntry: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let entries = Set(
                switcherPanelDiagnosticsValue(diagnosticsSummaryElement, key: "apps")
                    .split(separator: "|")
                    .map(String.init)
            )
            if entries.contains(expectedEntry) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return false
    }

    private func switcherPreviewTitles(from diagnosticsSummaryElement: XCUIElement) -> [String] {
        let rawValue = switcherPanelDiagnosticsValue(diagnosticsSummaryElement, key: "preview")
        guard rawValue != "inactive" else { return [] }
        guard let separatorRange = rawValue.range(of: "::") else { return [] }
        let titles = rawValue[separatorRange.upperBound...]
        guard !titles.isEmpty else { return [] }
        return titles.split(separator: "|").map(String.init)
    }

    private func switcherPanelDiagnosticsValue(
        _ diagnosticsSummaryElement: XCUIElement,
        key: String
    ) -> String {
        let prefix = "\(key)="
        for source in [elementStringValue(diagnosticsSummaryElement), diagnosticsSummaryElement.debugDescription] {
            guard let valueStart = source.range(of: prefix)?.upperBound else { continue }
            let remaining = source[valueStart...]
            guard let valueEnd = remaining.firstIndex(of: ";") else { return String(remaining) }
            return String(remaining[..<valueEnd])
        }
        return ""
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

    private func switcherDebugSummary(
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
