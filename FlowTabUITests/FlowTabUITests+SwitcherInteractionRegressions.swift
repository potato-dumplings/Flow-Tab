import XCTest

private enum FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy {
    static let foregroundReadiness: TimeInterval = 10
    static let controlTabDiagnostics: TimeInterval = 5
    static let controlTabSelectedPreview: TimeInterval = 5
    static let controlTabWindowCards: TimeInterval = 5
    static let delayedPresentationDismissal: TimeInterval = 5
    static let compatibleBounds = [foregroundReadiness, controlTabDiagnostics, controlTabSelectedPreview, controlTabWindowCards, delayedPresentationDismissal]
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
        let policies = FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy.compatibleBounds
        XCTAssertEqual(policies, [10, 5, 5, 5, 5])
        XCTAssertTrue(policies.allSatisfy { $0.isFinite && $0 > 0 })
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
        let appIDs = [
            "com.flowtab.mock.mail",
            "com.flowtab.mock.browser",
            "com.flowtab.mock.flow-search",
            "com.xxx.test",
            "com.xxx.csgo",
            "com.flowtab.mock.file-transfer-assistant",
        ]
        let expectedHomeRows = appIDs.map {
            FlowTabUITestHomeAppRowProjectionExpectation.Row(
                identifier: "flowtab.home.app."
                    + $0.flowTabUITestAccessibilityIdentifierComponent,
                value: nil
            )
        }
        var acceptsHomeRowEvidence = false
        let homeRowObservation = makeHomeAppRowProjectionObservation(
            in: app,
            rows: expectedHomeRows,
            frameOrder: .unconstrained,
            acceptsEvidence: { acceptsHomeRowEvidence }
        )
        homeRowObservation.start()
        defer { homeRowObservation.cancel() }

        let homeTabButtons = app.buttons.matching(identifier: Identifier.homeTabButton)
        let homeContent = element(in: app, identifier: Identifier.homeTabContent)
        let navigationSatisfied =
            tapFirstHittableAndWaitForExistence(
                in: homeTabButtons,
                content: homeContent,
                contentDescription: Identifier.homeTabContent,
                timeout: FlowTabUITestSupportWatchdogPolicy.tabNavigation
            )
        XCTAssertTrue(
            navigationSatisfied,
            "Home runtime-order navigation watchdog expired. "
                + "candidateCount=\(homeTabButtons.count) "
                + "contentExists=\(homeContent.exists)"
        )

        guard navigationSatisfied else { return }
        acceptsHomeRowEvidence = true
        homeRowObservation.requestReadback(source: .triggerReadback)
        guard
            let homeRowProjection =
                homeRowObservation.waitForResolution(
                    timeout:
                        FlowTabUITestHomeRuntimeOrderProjectionPolicy
                            .watchdog
                )?.value,
            let homeOrder = homeRowProjection.identifiersByAscendingFrame?
                .compactMap({ identifier in
                    expectedHomeRows.firstIndex { $0.identifier == identifier }
                    .map { appIDs[$0] }
                }),
            homeOrder.count == appIDs.count
        else {
            XCTFail(
                "Home runtime-order projection watchdog expired. "
                    + homeRowObservation.diagnosticSummary
            )
            return
        }

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        app.activate()
        XCUIElement.perform(withKeyModifiers: .option) {
            XCTAssertTrue(
                performAndWaitForSwitcherAppProjection(
                    diagnosticsSummary,
                    expectation: .orderedBundleIdentifiers(homeOrder),
                    timeout:
                        FlowTabUITestSwitcherAppProjectionPolicy
                            .runtimeOrderWatchdog,
                    trigger: {
                        app.typeKey(.tab, modifierFlags: .option)
                    }
                ),
                "Fresh Option+Tab must publish the Home runtime App order."
            )
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
        let secondaryWindowID = "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        let secondaryPreviewID = previewImageIdentifier(for: secondaryWindowID)
        let secondaryPreviewObservation = startElementExistenceObservation(in: app, identifier: secondaryPreviewID, requiresInitialAbsence: true)
        defer { secondaryPreviewObservation.cancel() }
        let logSnapshot = makeRuntimeLogFileSnapshot()
        defer { logSnapshot.cancel() }

        app.activate()
        XCUIElement.perform(withKeyModifiers: .control) {
            let cards = performAndWaitForSwitcherWindowCards(
                in: app,
                expectedTitles: ["Current Primary", "Current Secondary"],
                requiresEmptyInitialSnapshot: true,
                timeout: FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy.controlTabWindowCards,
                trigger: {
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
                            timeout:
                                FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy
                                    .controlTabDiagnostics,
                            trigger: {
                                app.typeKey(.tab, modifierFlags: .control)
                            }
                        ),
                        "The first physical Control+Tab gesture should select the next current-app window with both previews."
                    )
                    assertElementExistsAfterTrigger(
                        secondaryPreviewObservation,
                        timeout: FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy.controlTabSelectedPreview,
                        description: "Selected Control+Tab window preview"
                    )
                }
            )
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
            since: logSnapshot
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

            assertElementDoesNotExistAfterTrigger(
                diagnosticsSummary,
                timeout: FlowTabUITestSwitcherInteractionRegressionWatchdogPolicy.delayedPresentationDismissal,
                description: "Delayed-entry pressure iteration \(iteration) presentation dismissal",
                trigger: {
                    postFlowTabUITestSwitcherCommandAndWaitForDelivery(.confirm, traceLabel: "\(traceLabel).confirm")
                }
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
