import AppKit
import CoreGraphics
import XCTest

extension FlowTabUITests {
    func testSwitcherPanelOptionTabAppCycleActivatesFullscreenOnlyWorkflowAppAcrossSpaces() throws {
        let workflow = try configuredFullscreenOnlySpaceFixtureWorkflow()
        try validateMultiAppHomeFullscreenOnlyWorkflow(workflow)
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.fullscreenWindowIndex == 1 }
        )
        let targetTitle = try XCTUnwrap(
            targetApp.fullscreenWindowTitles.first
        )

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level", "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments,
            validatesPermissionsBeforeFixtureLaunch: true,
            flowTabLaunchTraceLabel: "option.appCycle.publicActivation"
        ) { _, app in
            let allTargetWindows = workflowCGWindowObservations(
                bundleIdentifier: targetApp.identity.bundleIdentifier,
                options: [.optionAll, .excludeDesktopElements]
            )
            let targetWindow = try XCTUnwrap(
                allTargetWindows.first { $0.title == targetTitle }
                    ?? (allTargetWindows.count == 1
                        ? allTargetWindows.first
                        : nil),
                "Expected one stable CG window for the fullscreen-only fixture app."
            )
            let initialOnscreenTargetIDs = Set(
                workflowCGWindowObservations(
                    bundleIdentifier:
                        targetApp.identity.bundleIdentifier,
                    options: [
                        .optionOnScreenOnly,
                        .excludeDesktopElements
                    ]
                ).map(\.number)
            )
            XCTAssertFalse(
                initialOnscreenTargetIDs.contains(targetWindow.number),
                "The app-cycle scenario must begin with the target fullscreen window off the active Space."
            )

            let diagnosticsSummary = element(
                in: app,
                identifier: Identifier.switcherSummary
            )
            XCTAssertTrue(
                try performAndWaitForSwitcherAppSelection(
                    in: app,
                    bundleIdentifier:
                        targetApp.identity.bundleIdentifier,
                    appProjectionExpectation:
                        .exactEntry(
                            targetApp.identity.bundleIdentifier
                                + ":1"
                        ),
                    timeout:
                        FlowTabUITestRuntimeTruthWatchdogPolicy
                            .switcherDiagnosticsAppSelectionProjectionApplication,
                    presentationTrigger: {
                        self.postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                            .global,
                            traceLabel:
                                "option.appCycle.publicActivation"
                        )
                    },
                    trigger: {
                        try FlowTabUITestSwitcherCommandPayload.write(
                            targetApp.identity.bundleIdentifier
                        )
                        postFlowTabUITestSwitcherCommand(
                            .selectApp,
                            traceLabel:
                                "option.appCycle.publicActivation.selectApp"
                        )
                    }
                )
            )
            XCTAssertEqual(
                switcherPanelDiagnosticsValue(
                    diagnosticsSummary,
                    key: "mode"
                ),
                "appCycle"
            )

            let activationLogSnapshot = makeRuntimeLogFileSnapshot()
            defer { activationLogSnapshot.cancel() }
            confirmOptionTabSelectionAndWaitForEvidence(
                windowNumber: targetWindow.number,
                title: targetTitle,
                app: targetApp,
                diagnosticsSummary: diagnosticsSummary,
                activationWatchdog:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .optionTabConfirmedWindowActivation,
                dismissalWatchdog:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .optionTabSwitcherDismissal,
                traceLabel: "app-cycle public activation"
            )
            let escapedBundleIdentifier =
                NSRegularExpression.escapedPattern(
                    for: targetApp.identity.bundleIdentifier
                )
            waitForRuntimeLogFiles(
                matching:
                    "(?m)app-activation route=public appID="
                    + escapedBundleIdentifier
                    + " pid=[0-9]+ generation=[0-9]+ "
                    + "fallback=[^\\s]+ restore=[01]\\r?$",
                since: activationLogSnapshot,
                timeout:
                    FlowTabUITestRuntimeLogObservationPolicy
                        .defaultWatchdog,
                description:
                    "app-cycle confirmation uses public application activation with the selected window fallback"
            )

            let finalOnscreenTargetIDs = Set(
                workflowCGWindowObservations(
                    bundleIdentifier:
                        targetApp.identity.bundleIdentifier,
                    options: [
                        .optionOnScreenOnly,
                        .excludeDesktopElements
                    ]
                ).map(\.number)
            )
            XCTAssertEqual(
                NSWorkspace.shared.frontmostApplication?
                    .bundleIdentifier,
                targetApp.identity.bundleIdentifier
            )
            XCTAssertTrue(
                finalOnscreenTargetIDs.contains(targetWindow.number),
                "Public app activation must leave the real target CG window onscreen."
            )
        }
    }
}
