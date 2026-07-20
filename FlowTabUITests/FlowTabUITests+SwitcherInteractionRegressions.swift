import XCTest

extension FlowTabUITests {
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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))
        XCTAssertTrue(
            tapFirstHittable(
                in: app.buttons.matching(identifier: Identifier.homeTabButton),
                timeout: 5
            )
        )
        XCTAssertTrue(element(in: app, identifier: Identifier.homeTabContent).waitForExistence(timeout: 5))

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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let secondaryWindowID =
            "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        let secondaryPreviewID = previewImageIdentifier(for: secondaryWindowID)
        let logSnapshot = makeRuntimeLogFileSnapshot()

        app.activate()
        XCUIElement.perform(withKeyModifiers: .control) {
            app.typeKey(.tab, modifierFlags: .control)

            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
            XCTAssertTrue(
                waitForControlTabSelectedWindow(
                    diagnosticsSummary,
                    windowID: "mock-current-secondary",
                    timeout: 5
                ),
                "The first physical Control+Tab gesture should select the next current-app window."
            )
            XCTAssertTrue(
                element(in: app, identifier: secondaryPreviewID).waitForExistence(timeout: 5),
                "The selected window should expose a real preview marker while Control remains held."
            )
            XCTAssertTrue(
                waitForSwitcherDiagnosticsValue(
                    diagnosticsSummary,
                    key: "previewImages",
                    expectedValue: "2",
                    timeout: 5
                ),
                "Control+Tab should reveal with both preview images ready."
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
                "inAppHotkeyPressed dir=forward panelVisible=0 action=show",
                "show kind=inApp action=initialAdvance key=tabForward",
                "initial window-only panel revealed reason=preview_batch_completed previewsReady=1",
            ],
            since: logSnapshot,
            timeout: 8
        )
    }

    func testOptionTabDelayedWindowLayerEntryShowsPrewarmedPreviewAtTransition() throws {
        let app = makeApp(
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
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let firstWindowID =
            "flowtab.switcher.window.\("mock-browser-normal-1".flowTabUITestAccessibilityIdentifierComponent)"
        let firstPreview = element(
            in: app,
            identifier: previewImageIdentifier(for: firstWindowID)
        )
        let logSnapshot = makeRuntimeLogFileSnapshot()

        app.activate()
        XCUIElement.perform(withKeyModifiers: .option) {
            app.typeKey(.tab, modifierFlags: .option)

            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
            XCTAssertTrue(
                waitForWindowLayerPreviewAtTransition(
                    diagnosticsSummary: diagnosticsSummary,
                    previewElement: firstPreview,
                    timeout: 5,
                    previewGrace: 0.10
                ),
                "The delayed Option+Tab window layer should expose its prewarmed preview with the mode transition."
            )

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Option Tab prewarmed delayed window layer"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        waitForRuntimeLogFiles(
            containing: [
                "prewarmed=5",
                "entered reason=timer",
            ],
            since: logSnapshot,
            timeout: 8
        )
    }

    private func waitForControlTabSelectedWindow(
        _ diagnosticsSummary: XCUIElement,
        windowID: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selectedWindow") == windowID {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func waitForSwitcherDiagnosticsValue(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        expectedValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if switcherPanelDiagnosticsValue(diagnosticsSummary, key: key) == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < deadline
        return false
    }

    private func waitForWindowLayerPreviewAtTransition(
        diagnosticsSummary: XCUIElement,
        previewElement: XCUIElement,
        timeout: TimeInterval,
        previewGrace: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var windowLayerObservedAt: Date?
        repeat {
            let now = Date()
            let mode = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "mode")
            if mode.hasPrefix("windowCycle") {
                if previewElement.exists {
                    return true
                }
                if windowLayerObservedAt == nil {
                    windowLayerObservedAt = now
                }
                if let windowLayerObservedAt,
                   now.timeIntervalSince(windowLayerObservedAt) > previewGrace {
                    return false
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < deadline
        return false
    }
}
