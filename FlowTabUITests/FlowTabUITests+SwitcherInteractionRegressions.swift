import XCTest

private enum FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy {
    static let foregroundReadiness: TimeInterval = 10
}

private enum FlowTabUITestDelayedWindowLayerEntryEvidence {
    static let prewarmBeforeEntryPattern =
        #"\[AutoEnter\] pending targetAppID="#
        + #"com\.flowtab\.mock\.browser[^\n]*prewarmed=5"#
        + #"[\s\S]*\[AutoEnter\] entered source=\S+[^\n]*"#
        + #"mode=windowCycle\(com\.flowtab\.mock\.browser\)"#
    static let prewarmBeforeEntryDescription =
        "exact preview prewarm precedes target window-layer entry"
    static let logWatchdog: TimeInterval = 8
}

extension FlowTabUITests {
    func testSwitcherInteractionRegressionWatchdogPolicyPreservesCompatibleBound() {
        let foregroundReadiness =
            FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy
                .foregroundReadiness
        XCTAssertEqual(foregroundReadiness, 10)
        XCTAssertTrue(
            foregroundReadiness.isFinite && foregroundReadiness > 0
        )
    }

    func testHomeAndFreshOptionTabUseSameRuntimeAppOrder() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-enable-mock-hotkey-effects",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES",
                "-showPermissionReminder",
                "NO",
            ]
        )
        launchFlowTabUITestApplication(app)
        assertSwitcherInteractionApplicationIsForegroundReady(
            app,
            scenario: "Home and fresh Option+Tab runtime order"
        )
        let homeTabButtons = app.buttons.matching(
            identifier: Identifier.homeTabButton
        )
        let homeTabButton = homeTabButtons.firstMatch
        let homeContent = element(
            in: app,
            identifier: Identifier.homeTabContent
        )
        XCTAssertTrue(
            tapFirstHittableAndWaitForExistence(
                in: homeTabButtons,
                content: homeContent,
                contentDescription: Identifier.homeTabContent,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .tabNavigation
            ),
            "Home runtime-order navigation watchdog expired. "
                + "candidateCount=\(homeTabButtons.count) "
                + "firstExists=\(homeTabButton.exists) "
                + "firstHittable=\(homeTabButton.isHittable) "
                + "contentExists=\(homeContent.exists)"
        )

        let appIDs = [
            "com.flowtab.mock.mail",
            "com.flowtab.mock.browser",
            "com.flowtab.mock.flow-search",
            "com.xxx.test",
            "com.xxx.csgo",
            "com.flowtab.mock.file-transfer-assistant",
        ]
        let homeRows = appIDs.map { appID in
            (
                appID,
                element(
                    in: app,
                    identifier: "flowtab.home.app.\(appID.flowTabUITestAccessibilityIdentifierComponent)"
                )
            )
        }
        for (_, row) in homeRows {
            XCTAssertTrue(row.waitForExistence(timeout: 6))
        }
        let homeOrder = homeRows
            .sorted { $0.1.frame.minY < $1.1.frame.minY }
            .map(\.0)

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        app.activate()
        XCUIElement.perform(withKeyModifiers: .option) {
            app.typeKey(.tab, modifierFlags: .option)

            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
            let switcherOrder = switcherPanelDiagnosticsValue(
                diagnosticsSummary,
                key: "apps"
            )
            .split(separator: "|")
            .compactMap { entry in
                entry.split(separator: ":", maxSplits: 1).first.map(String.init)
            }
            XCTAssertEqual(switcherOrder, homeOrder)
        }
    }

    func testControlTabFirstPhysicalGestureSelectsNextWindowWithVisiblePreview() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-window-previews",
                "--flowtab-ui-mock-window-preview-delay-ms",
                "80",
                "--flowtab-ui-mock-runtime-variant",
                "focused-current-app",
                "--flowtab-ui-frontmost-bundle-id",
                FlowTabUITestAppIdentity.configured().bundleIdentifier,
                "--flowtab-ui-enable-mock-hotkey-effects",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES",
                "-showPermissionReminder",
                "NO",
            ]
        )
        launchFlowTabUITestApplication(app)
        assertSwitcherInteractionApplicationIsForegroundReady(
            app,
            scenario: "first physical Control+Tab gesture"
        )

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let secondaryWindowID =
            "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        let secondaryPreviewID = previewImageIdentifier(for: secondaryWindowID)
        let logSnapshot = makeRuntimeLogFileSnapshot()

        app.activate()
        XCUIElement.perform(withKeyModifiers: .control) {
            XCTAssertTrue(
                performAndWaitForSwitcherDiagnostics(
                    [
                        FlowTabUITestSwitcherDiagnosticsExpectation(
                            key: "selectedWindow",
                            expectedValue:
                                "mock-current-secondary"
                        ),
                        FlowTabUITestSwitcherDiagnosticsExpectation(
                            key: "previewImages",
                            expectedValue: "2"
                        )
                    ],
                    in: diagnosticsSummary,
                    timeout: 5,
                    trigger: {
                        app.typeKey(
                            .tab,
                            modifierFlags: .control
                        )
                    }
                ),
                "The first physical Control+Tab gesture should select the next current-app window with both previews."
            )
            XCTAssertTrue(
                element(in: app, identifier: secondaryPreviewID).waitForExistence(timeout: 5),
                "The selected window should expose a real preview marker while Control remains held."
            )
            XCTAssertTrue(
                waitForSwitcherWindowCards(
                    in: app,
                    expectedTitles: ["Current Primary", "Current Secondary"],
                    timeout: 5
                )
            )
            let cards = switcherWindowCardObservations(in: app)
            let cardBounds = cards.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            XCTAssertGreaterThan(
                cardBounds.width,
                800,
                "Control+Tab should use the large window-preview canvas."
            )
            XCTAssertTrue(cards.allSatisfy(\.hasImage))

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Control Tab first physical gesture"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        waitForRuntimeLogFiles(
            containing: [
                "mock window preview latency",
                "outcome=elapsed delayMs=80",
                "inAppHotkeyPressed dir=forward panelVisible=0 action=show",
                "show kind=inApp action=initialAdvance key=tabForward",
                "initial window-only panel revealed reason=preview_batch_completed previewsReady=1",
            ],
            since: logSnapshot,
            timeout: 8
        )
    }

    func testOptionTabDelayedWindowLayerEntryShowsPrewarmedPreviewAtTransition() throws {
        let app = makeDelayedWindowLayerEntryApp()
        launchFlowTabUITestApplication(app)
        assertSwitcherInteractionApplicationIsForegroundReady(
            app,
            scenario: "delayed Option+Tab window-layer entry"
        )

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let firstWindowID =
            "flowtab.switcher.window.\("mock-browser-normal-1".flowTabUITestAccessibilityIdentifierComponent)"
        let firstPreviewID =
            previewImageIdentifier(for: firstWindowID)
        let firstPreview = element(
            in: app,
            identifier: firstPreviewID
        )
        let logSnapshot = makeRuntimeLogFileSnapshot()

        app.activate()
        XCUIElement.perform(withKeyModifiers: .option) {
            XCTAssertTrue(
                performAndWaitForWindowLayerPreviewTransition(
                    diagnosticsSummary: diagnosticsSummary,
                    previewElement: firstPreview,
                    expectedPreviewIdentifier: firstPreviewID,
                    trigger: {
                        app.typeKey(
                            .tab,
                            modifierFlags: .option
                        )
                    }
                ),
                "The delayed Option+Tab window layer should expose its prewarmed preview with the mode transition."
            )

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Option Tab prewarmed delayed window layer"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        waitForRuntimeLogFiles(
            matching:
                FlowTabUITestDelayedWindowLayerEntryEvidence
                    .prewarmBeforeEntryPattern,
            since: logSnapshot,
            timeout:
                FlowTabUITestDelayedWindowLayerEntryEvidence
                    .logWatchdog,
            description:
                FlowTabUITestDelayedWindowLayerEntryEvidence
                    .prewarmBeforeEntryDescription
        )
    }

    func testOptionTabDelayedWindowLayerEntryRepeatedPresentationPressure() throws {
        let app = makeDelayedWindowLayerEntryApp()
        launchFlowTabUITestApplication(app)
        assertSwitcherInteractionApplicationIsForegroundReady(
            app,
            scenario: "delayed Option+Tab repeated-presentation Pressure"
        )

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let firstWindowID =
            "flowtab.switcher.window.\("mock-browser-normal-1".flowTabUITestAccessibilityIdentifierComponent)"
        let firstPreviewID =
            previewImageIdentifier(for: firstWindowID)
        let firstPreview = element(
            in: app,
            identifier: firstPreviewID
        )
        let presentationCount = 12

        for iteration in 1...presentationCount {
            let traceLabel = "delayed-entry-pressure.\(iteration)"
            let logSnapshot = makeRuntimeLogFileSnapshot()
            app.activate()
            XCTAssertTrue(
                performAndWaitForWindowLayerPreviewTransition(
                    diagnosticsSummary: diagnosticsSummary,
                    previewElement: firstPreview,
                    expectedPreviewIdentifier: firstPreviewID,
                    trigger: {
                        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                            .global,
                            traceLabel: traceLabel
                        )
                    }
                ),
                "Delayed-entry pressure iteration \(iteration) must expose the prewarmed preview."
            )
            waitForRuntimeLogFiles(
                matching:
                    FlowTabUITestDelayedWindowLayerEntryEvidence
                        .prewarmBeforeEntryPattern,
                since: logSnapshot,
                timeout:
                    FlowTabUITestDelayedWindowLayerEntryEvidence
                        .logWatchdog,
                description:
                    FlowTabUITestDelayedWindowLayerEntryEvidence
                        .prewarmBeforeEntryDescription
            )

            postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                .confirm,
                traceLabel: "\(traceLabel).confirm"
            )
            XCTAssertTrue(
                waitForNonExistence(diagnosticsSummary, timeout: 5),
                "Delayed-entry pressure iteration \(iteration) must release its presentation owner."
            )
        }
    }

    private func assertSwitcherInteractionApplicationIsForegroundReady(
        _ app: XCUIApplication,
        scenario: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let becameReady = waitForFlowTabUITestApplicationToBecomeReady(
            app,
            timeout:
                FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy
                    .foregroundReadiness
        )
        XCTAssertTrue(
            becameReady,
            "\(scenario) foreground readiness watchdog expired. "
                + "unmetCondition=runningForeground "
                + "finalState=\(String(describing: app.state))",
            file: file,
            line: line
        )
    }

    private func makeDelayedWindowLayerEntryApp() -> XCUIApplication {
        makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-window-previews",
                "--flowtab-ui-mock-runtime-variant",
                "single-app-five-windows",
                "--flowtab-ui-enable-mock-hotkey-effects",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES",
                "-windowLayerAutoEnterDelay",
                "0.30",
                "-showPermissionReminder",
                "NO",
            ]
        )
    }

}
