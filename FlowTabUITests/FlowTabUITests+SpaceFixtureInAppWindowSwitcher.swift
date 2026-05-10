import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

private struct InAppWindowSelection: Equatable {
    let title: String
    let windowID: String
    let windowNumber: CGWindowID
}

extension FlowTabUITests {
    func testInAppWindowSwitcherControlTabRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithoutAppAXWindows() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        try runInAppWindowSwitcherControlTabRoundTrip(
            workflow,
            traceLabel: "control"
        )
    }

    func testInAppWindowSwitcherControlTabRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows() throws {
        let workflow = try configuredNoisyCGSiblingsSwitcherSpaceFixtureWorkflow()
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
            var diagnosticsSummary = assertInAppWindowSwitcherReady(for: targetApp, in: app)
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
            assertSwitcherSelectedWindowTitle(
                fullscreenTitle,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                message: "Control+Tab roundtrip must enter the first focused-window phase on the fullscreen sibling."
            )
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

            diagnosticsSummary = relaunchInAppWindowSwitcher(app, for: targetApp)
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
            let secondLogSnapshot = makeRuntimeLogFileSnapshot()
            let fullscreenSelection = try selectInAppWindow(
                title: fullscreenTitle,
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
                    title: fullscreenTitle,
                    app: targetApp,
                    timeout: 12
                )
            )
            logWorkflowSpaceObservation("\(traceLabel).afterFullscreenConfirm", app: targetApp)
        }
    }

    func waitForApplicationAXWindowsSuppressed(
        bundleIdentifier: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestCounts: ApplicationAXWindowCounts?
        repeat {
            latestCounts = applicationAXWindowCounts(bundleIdentifier: bundleIdentifier)
            if latestCounts?.isSuppressed == true {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected application-level AX windows to be suppressed for \(bundleIdentifier), \
            found children=\(latestCounts?.childWindowCount.description ?? "nil"), \
            windows=\(latestCounts?.windowsAttributeCount.description ?? "nil").
            """
        )
        return false
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
        let fullscreenTitle = fullscreenWindowTitle(in: workflowApp)
        return workflowApp.expectedWindowTitles.first { $0 != fullscreenTitle }
    }

    private func assertInAppWindowSwitcherReady(
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication
    ) -> XCUIElement {
        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForSwitcherAppsSummary(
                diagnosticsSummary,
                toContain: switcherAppStripSummary(for: workflowApp),
                timeout: 8
            )
        )
        XCTAssertEqual(
            switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected"),
            workflowApp.identity.bundleIdentifier
        )
        XCTAssertEqual(Set(switcherPreviewTitles(from: diagnosticsSummary)), Set(workflowApp.expectedWindowTitles))
        return diagnosticsSummary
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
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> XCUIElement {
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.inApp, traceLabel: "control.reopen")
        return assertInAppWindowSwitcherReady(for: workflowApp, in: app)
    }

    private struct ApplicationAXWindowCounts {
        let childWindowCount: Int
        let windowsAttributeCount: Int

        var isSuppressed: Bool {
            childWindowCount == 0 && windowsAttributeCount == 0
        }
    }

    private func applicationAXWindowCounts(bundleIdentifier: String) -> ApplicationAXWindowCounts? {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        return ApplicationAXWindowCounts(
            childWindowCount: applicationAXWindowChildCount(in: appElement),
            windowsAttributeCount: applicationAXWindowsAttributeCount(in: appElement)
        )
    }

    private func applicationAXWindowChildCount(in appElement: AXUIElement) -> Int {
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success else {
            return 0
        }

        guard let children = childrenValue as? [AXUIElement] else {
            return 0
        }
        return children.filter { axRole(in: $0) == kAXWindowRole as String }.count
    }

    private func applicationAXWindowsAttributeCount(in appElement: AXUIElement) -> Int {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success else {
            return 0
        }

        return (windowsValue as? [AXUIElement])?.count ?? 0
    }

    private func axRole(in element: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success else {
            return nil
        }
        return roleValue as? String
    }
}
