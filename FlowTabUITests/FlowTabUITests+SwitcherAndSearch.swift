import XCTest

extension FlowTabUITests {
    private var optionTabPointerHoverArguments: [String] {
        [
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-open-switcher",
            "-showPermissionReminder",
            "NO"
        ]
    }

    private var controlTabPointerHoverArguments: [String] {
        [
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-mock-window-previews",
            "--flowtab-ui-mock-runtime-variant",
            "focused-current-app",
            "--flowtab-ui-frontmost-bundle-id",
            FlowTabUITestAppIdentity.configured().bundleIdentifier,
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-runtime-log-level",
            "DEBUG",
            "--flowtab-ui-enable-verbose-logs",
            "-showPermissionReminder",
            "NO"
        ]
    }

    private var searchPointerHoverArguments: [String] {
        searchMockRuntimeArguments()
    }

    private var searchPointerHoverTriggerArguments: [String] {
        searchMockRuntimeArguments(opensSearchOnLaunch: false, listensForTrigger: true)
    }

    private func searchMockRuntimeArguments(
        mockRuntimeVariant: String? = nil,
        opensSearchOnLaunch: Bool = true,
        listensForTrigger: Bool = false
    ) -> [String] {
        var arguments = [
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-mock-runtime",
            "-showPermissionReminder",
            "NO",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES",
            "--flowtab-ui-runtime-log-level",
            "DEBUG",
            "--flowtab-ui-enable-verbose-logs"
        ]
        if let mockRuntimeVariant {
            arguments += [
                "--flowtab-ui-mock-runtime-variant",
                mockRuntimeVariant
            ]
        }
        if opensSearchOnLaunch {
            arguments.append("--flowtab-ui-open-switcher-search")
        }
        if listensForTrigger {
            arguments.append("--flowtab-ui-listen-switcher-trigger")
        }
        return arguments
    }

    func testSearchPanelEntryAndResultActivation() throws {
        runRealSpaceFixtureWorkflow(
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher-search"]
        ) { identity, app in
            let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
            XCTAssertTrue(searchInput.waitForExistence(timeout: 5))

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            app.typeText(identity.switcherSearchQuery)

            let fixtureResult = app.descendants(matching: .any)
                .matching(identifier: identity.switcherSearchAppAccessibilityIdentifier)
                .firstMatch
            XCTAssertTrue(fixtureResult.waitForExistence(timeout: 5))

            app.typeText("\r")
            if !waitForNonExistence(searchInput, timeout: 1.2) {
                // XCUI keyboard input may leave the hidden NSTextView in a marked-text
                // composition state, so the first Return only commits composition.
                app.typeText("\r")
            }
            XCTAssertTrue(waitForNonExistence(searchInput, timeout: 3))
        }
    }

    func testSearchHeaderHighlightedAppChipStaysContentSizedForShortTitle() throws {
        let app = makeApp(additionalArguments: searchPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let searchHeader = element(in: app, identifier: Identifier.switcherSearchHeader)
        let highlightedChip = element(in: app, identifier: Identifier.switcherSearchHighlight)
        XCTAssertTrue(searchHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(highlightedChip.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(highlightedChip.frame.width, 40)
        XCTAssertLessThan(
            highlightedChip.frame.width,
            150,
            "Short highlighted app names should stay content-sized instead of expanding to the long-title width cap."
        )
    }

    func testSearchPanelChineseQueryShowsChineseMockResult() throws {
        let app = makeApp(
            additionalArguments: searchMockRuntimeArguments()
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("测")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.test".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelPinyinInitialsShowChineseMockResult() throws {
        let app = makeApp(
            additionalArguments: searchMockRuntimeArguments()
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cs")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.test".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelSharedCsQueryShowsCSGOAndChineseMockResults() throws {
        let app = makeApp(
            additionalArguments: searchMockRuntimeArguments()
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cs")

        let csgoResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.csgo".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(csgoResult.waitForExistence(timeout: 5))

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.test".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelCodeLikeSubsequenceShowsMockResult() throws {
        let app = makeApp(
            additionalArguments: searchMockRuntimeArguments()
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cgo")

        let csgoResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.csgo".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(csgoResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelSegmentedChineseQueryShowsCompoundMockResult() throws {
        let app = makeApp(
            additionalArguments: searchMockRuntimeArguments()
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("文件助手")

        let segmentedResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.flowtab.mock.file-transfer-assistant".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(segmentedResult.waitForExistence(timeout: 5))
    }

    func testOptionTabSwitcherPointerHoverSelectsMockAppAfterMovement() throws {
        let app = makeApp(additionalArguments: optionTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let browserTile = element(in: app, identifier: Identifier.switcherAppMockBrowser)
        let mailTile = element(in: app, identifier: Identifier.switcherAppMockMail)
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(browserTile.waitForExistence(timeout: 5))
        XCTAssertTrue(mailTile.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForSwitcherDiagnosticsValue(
                diagnosticsSummary,
                key: "selected",
                equals: "com.flowtab.mock.browser",
                timeout: 3
            )
        )

        browserTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        mailTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()

        XCTAssertTrue(
            waitForSwitcherDiagnosticsValue(
                diagnosticsSummary,
                key: "selected",
                equals: "com.flowtab.mock.mail",
                timeout: 3
            ),
            "Hovering a switcher app tile after pointer movement should update the selected app. browserFrame=\(browserTile.frame) mailFrame=\(mailTile.frame) summary=\(diagnosticsSummary.value ?? "")"
        )
    }

    func testOptionTabSwitcherStationaryPointerOverAppTileDoesNotSelectOnPresentation() throws {
        let placementApp = makeApp(additionalArguments: optionTabPointerHoverArguments)
        launchFlowTabUITestApplication(placementApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(placementApp, timeout: 10))

        let placementMailTile = element(in: placementApp, identifier: Identifier.switcherAppMockMail)
        XCTAssertTrue(placementMailTile.waitForExistence(timeout: 5))
        let stationaryPoint = CGPoint(x: placementMailTile.frame.midX, y: placementMailTile.frame.midY)
        placementMailTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        terminateAndWaitForNotRunning(placementApp)

        let app = makeApp(additionalArguments: optionTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let mailTile = element(in: app, identifier: Identifier.switcherAppMockMail)
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(mailTile.waitForExistence(timeout: 5))
        assertFrame(mailTile.frame, contains: stationaryPoint)
        assertSwitcherDiagnosticsValueRemains(
            diagnosticsSummary,
            key: "selected",
            equals: "com.flowtab.mock.browser",
            duration: 1,
            message: "A stationary pointer already over the mail app tile must not select it on presentation."
        )
    }

    func testOptionTabSwitcherClickCommitsAppAndClosesPanel() throws {
        let app = makeApp(additionalArguments: optionTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let mailTile = element(in: app, identifier: Identifier.switcherAppMockMail)
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(mailTile.waitForExistence(timeout: 5))

        mailTile.tap()

        XCTAssertTrue(
            waitForNonExistence(diagnosticsSummary, timeout: 2),
            "Clicking an Option+Tab app tile should commit the app and close the panel immediately."
        )
    }

    func testControlTabSwitcherPointerHoverSelectsWindowAfterMovement() throws {
        let app = makeApp(additionalArguments: controlTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let primaryWindowID = "flowtab.switcher.window.\("mock-current-primary".flowTabUITestAccessibilityIdentifierComponent)"
        let secondaryWindowID = "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        let primaryWindow = element(in: app, identifier: primaryWindowID)
        let secondaryWindow = element(in: app, identifier: secondaryWindowID)
        XCTAssertTrue(openInAppSwitcherForPointerHover(diagnosticsSummary))
        XCTAssertTrue(primaryWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(secondaryWindow.waitForExistence(timeout: 5))

        primaryWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        secondaryWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()

        XCTAssertTrue(
            waitForSwitcherDiagnosticsValue(
                diagnosticsSummary,
                key: "selectedWindow",
                equals: "mock-current-secondary",
                timeout: 3
            ),
            "Hovering a Control+Tab window card after pointer movement should update the selected window."
        )
    }

    func testControlTabSwitcherStationaryPointerOverWindowCardDoesNotSelectOnPresentation() throws {
        let placementApp = makeApp(additionalArguments: controlTabPointerHoverArguments)
        launchFlowTabUITestApplication(placementApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(placementApp, timeout: 10))

        let placementSummary = element(in: placementApp, identifier: Identifier.switcherSummary)
        XCTAssertTrue(openInAppSwitcherForPointerHover(placementSummary))
        let secondaryWindowID = "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        let placementSecondaryWindow = element(in: placementApp, identifier: secondaryWindowID)
        XCTAssertTrue(placementSecondaryWindow.waitForExistence(timeout: 5))
        let stationaryPoint = CGPoint(
            x: placementSecondaryWindow.frame.midX,
            y: placementSecondaryWindow.frame.midY
        )
        placementSecondaryWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        terminateAndWaitForNotRunning(placementApp)

        let app = makeApp(additionalArguments: controlTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(openInAppSwitcherForPointerHover(diagnosticsSummary))
        let secondaryWindow = element(in: app, identifier: secondaryWindowID)
        XCTAssertTrue(secondaryWindow.waitForExistence(timeout: 5))
        assertFrame(secondaryWindow.frame, contains: stationaryPoint)
        assertSwitcherDiagnosticsValueRemains(
            diagnosticsSummary,
            key: "selectedWindow",
            equals: "mock-current-primary",
            duration: 1,
            message: "A stationary pointer already over the secondary window card must not select it on presentation."
        )
    }

    func testControlTabSwitcherClickCommitsWindowAndClosesPanel() throws {
        let app = makeApp(additionalArguments: controlTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let secondaryWindowID = "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        let secondaryWindow = element(in: app, identifier: secondaryWindowID)
        XCTAssertTrue(openInAppSwitcherForPointerHover(diagnosticsSummary))
        XCTAssertTrue(secondaryWindow.waitForExistence(timeout: 5))

        secondaryWindow.tap()

        XCTAssertTrue(
            waitForNonExistence(diagnosticsSummary, timeout: 2),
            "Clicking a Control+Tab window card should commit the window and close the panel immediately."
        )
    }

    func testSearchPanelPointerHoverSelectsResultAfterMovement() throws {
        let app = makeApp(additionalArguments: searchPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let mailResultID = "flowtab.switcher.search.app.\("com.flowtab.mock.mail".flowTabUITestAccessibilityIdentifierComponent)"
        let browserResultID = "flowtab.switcher.search.app.\("com.flowtab.mock.browser".flowTabUITestAccessibilityIdentifierComponent)"
        let mailResult = app.descendants(matching: .any)
            .matching(identifier: mailResultID)
            .firstMatch
        let browserResult = app.descendants(matching: .any)
            .matching(identifier: browserResultID)
            .firstMatch
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(mailResult.waitForExistence(timeout: 5))
        XCTAssertTrue(browserResult.waitForExistence(timeout: 5))
        assertSearchResultUsesRowSizedFrame(mailResult)
        assertSearchResultUsesRowSizedFrame(browserResult)

        mailResult.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        browserResult.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()

        XCTAssertTrue(
            waitForSwitcherDiagnosticsValue(
                diagnosticsSummary,
                key: "searchSelectedResult",
                equals: "app:com.flowtab.mock.browser",
                decodesPercentEncoding: true,
                timeout: 3
            ),
            "Hovering a search result after pointer movement should update the selected search result."
        )
    }

    func testSearchPanelStationaryPointerOverResultDoesNotSelectOnPresentation() throws {
        let browserResultID = "flowtab.switcher.search.app.\("com.flowtab.mock.browser".flowTabUITestAccessibilityIdentifierComponent)"
        let app = makeApp(additionalArguments: searchPointerHoverTriggerArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        XCTAssertTrue(openSearchSwitcherForPointerHover(diagnosticsSummary))

        let primingBrowserResult = app.descendants(matching: .any)
            .matching(identifier: browserResultID)
            .firstMatch
        XCTAssertTrue(primingBrowserResult.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 3))
        XCTAssertTrue(openSearchSwitcherForPointerHover(diagnosticsSummary))

        let placementBrowserResult = app.descendants(matching: .any)
            .matching(identifier: browserResultID)
            .firstMatch
        XCTAssertTrue(placementBrowserResult.waitForExistence(timeout: 5))
        assertSearchResultUsesRowSizedFrame(placementBrowserResult)
        let stationaryPoint = CGPoint(
            x: placementBrowserResult.frame.midX,
            y: placementBrowserResult.frame.midY
        )
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(diagnosticsSummary, timeout: 3))
        let homeContent = element(in: app, identifier: Identifier.homeTabContent)
        XCTAssertTrue(homeContent.waitForExistence(timeout: 3))
        hoverScreenPoint(stationaryPoint, relativeTo: homeContent)
        XCTAssertTrue(openSearchSwitcherForPointerHover(diagnosticsSummary))

        let browserResult = app.descendants(matching: .any)
            .matching(identifier: browserResultID)
            .firstMatch
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(browserResult.waitForExistence(timeout: 5))
        assertSearchResultUsesRowSizedFrame(browserResult)
        assertFrame(browserResult.frame, contains: stationaryPoint)
        assertSwitcherDiagnosticsValueRemains(
            diagnosticsSummary,
            key: "searchSelectedResult",
            equals: "app%3Acom.flowtab.mock.mail",
            duration: 1,
            message: "A stationary pointer already over the browser search result must not select it on presentation."
        )
    }

    func testSearchPanelClickCommitsResultAndClosesPanel() throws {
        let app = makeApp(additionalArguments: searchPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let browserResultID = "flowtab.switcher.search.app.\("com.flowtab.mock.browser".flowTabUITestAccessibilityIdentifierComponent)"
        let browserResult = app.descendants(matching: .any)
            .matching(identifier: browserResultID)
            .firstMatch
        XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(browserResult.waitForExistence(timeout: 5))
        assertSearchResultUsesRowSizedFrame(browserResult)

        browserResult.tap()

        XCTAssertTrue(
            waitForNonExistence(diagnosticsSummary, timeout: 2),
            "Clicking a search result row should commit the result and close the panel immediately."
        )
    }

    func testSwitcherInitialPresentationStaleOcclusionDoesNotHardRecover() throws {
        let logSnapshot = makeRuntimeLogFileSnapshot()
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-suppress-home-on-launch",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-initial-panel-occlusion-stale-ms",
                "260",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            .global,
            traceLabel: "initial-stale-occlusion"
        )
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherAppMockBrowser).waitForExistence(timeout: 5))

        waitForRuntimeLogFiles(
            containing: [
                "phase=installed staleMs=260",
                "phase=released staleMs=260",
                "initial panel occlusion stale released",
                "presentationRecovery trigger=global_show action=complete"
            ],
            since: logSnapshot,
            timeout: 8
        )
        let logContents = runtimeLogContentsSinceSnapshot(logSnapshot)
        XCTAssertTrue(
            logContents.contains("presentationRecovery trigger=global_show action=softAttempt"),
            """
            Initial stale occlusion should exercise the soft recovery path.
            Runtime logs:
            \(logContents)
            """
        )
        XCTAssertFalse(
            logContents.contains("presentationRecovery trigger=global_show action=attempt"),
            """
            Initial stale occlusion should not trigger a hard recovery/orderOut path.
            Runtime logs:
            \(logContents)
            """
        )
    }

    func testOptionTabSwitcherHidesZeroWindowNestedAppsFromMockWeChatTopology() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                "nested-zero-window-apps",
                "--flowtab-ui-enable-mock-hotkey-effects",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let hostWeChatRow = element(in: app, identifier: Identifier.switcherAppWeChat)
        let topLevelZeroWindowRow = element(in: app, identifier: Identifier.switcherAppTopLevelZeroWindow)
        let logSnapshot = makeRuntimeLogFileSnapshot()
        try FlowTabUITestSwitcherCommandPayload.write("com.tencent.xinWeChat")

        app.activate()
        XCUIElement.perform(withKeyModifiers: .option) {
            app.typeKey(.tab, modifierFlags: .option)

            XCTAssertTrue(
                hostWeChatRow.waitForExistence(timeout: 8),
                "Option+Tab should open the switcher with the outer WeChat app row."
            )
            XCTAssertTrue(
                topLevelZeroWindowRow.waitForExistence(timeout: 8),
                "The nested-app filter must not hide ordinary top-level 0w apps."
            )
            let switcherAppIdentifiers = Set(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@", "flowtab.switcher.app."))
                    .allElementsBoundByIndex
                    .map(\.identifier)
            )
            XCTAssertFalse(
                switcherAppIdentifiers.contains(Identifier.switcherAppNestedWeChatAppEx),
                """
                The switcher app layer should hide zero-window helper apps nested in a visible host app bundle.
                Switcher app identifiers: \(switcherAppIdentifiers.sorted())
                """
            )
            XCTAssertFalse(
                switcherAppIdentifiers.contains(Identifier.switcherAppNestedMiniProgram),
                """
                The switcher app layer should hide deeper zero-window helper apps nested in a visible host app bundle.
                Switcher app identifiers: \(switcherAppIdentifiers.sorted())
                """
            )

            postFlowTabUITestSwitcherCommandAndWaitForDelivery(.selectApp, traceLabel: "nestedTopology.selectWeChat")
            app.typeKey(.downArrow, modifierFlags: [])
            _ = waitForSwitcherWindowCards(
                in: app,
                expectedTitles: [
                    "微信",
                    "微信（窗口）",
                    "Mock Mini Program Window"
                ],
                timeout: 6
            )

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Option Tab switcher nested zero-window topology"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        waitForRuntimeLogFiles(
            containing: [
                "hotkeyPressed dir=forward panelVisible=0 action=show",
                "HotKey Forward"
            ],
            since: logSnapshot,
            timeout: 10
        )
    }

    func testSwitcherWindowLayerPaginatesLargeMockWindowSet() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-window-previews",
                "--flowtab-ui-enable-mock-hotkey-effects",
                "--flowtab-ui-mock-runtime-variant",
                "single-app-many-windows",
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-showPermissionReminder",
                "NO"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherAppMockManyWindows).waitForExistence(timeout: 5))

        postFlowTabUITestSwitcherCommandAndWaitForDelivery(.advanceDown, traceLabel: "many-window-page")

        let firstWindowID = "flowtab.switcher.window.\("mock-many-window-00".flowTabUITestAccessibilityIdentifierComponent)"
        XCTAssertTrue(element(in: app, identifier: firstWindowID).waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherNextWindowPage).waitForExistence(timeout: 2))

        let windowCards = switcherWindowCardObservations(in: app)
        XCTAssertGreaterThan(windowCards.count, 0)
        XCTAssertLessThan(windowCards.count, 20)
        XCTAssertTrue(
            windowCards.allSatisfy { $0.frame.width >= 100 },
            "Expected current visible window cards to keep preview width, found \(windowCards.map { "\($0.identifier)=\($0.frame)" })"
        )
        XCTAssertTrue(
            windowCards.allSatisfy(\.hasImage),
            "Expected current visible window cards to expose mock screenshots, found \(windowCards.map { "\($0.identifier)=\($0.value)" })"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "flowtab.switcher.window.\("mock-many-window-25".flowTabUITestAccessibilityIdentifierComponent)")
                .firstMatch
                .exists
        )
    }

    func testSearchPanelWrapFromLastResultScrollsBackToFirstResult() throws {
        let app = makeApp(
            additionalArguments: searchMockRuntimeArguments(mockRuntimeVariant: "search-wrap")
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        let firstResultIdentifier = "flowtab.switcher.search.app.\("com.flowtab.mock.wrap.01".flowTabUITestAccessibilityIdentifierComponent)"
        let lastResultIdentifier = "flowtab.switcher.search.app.\("com.flowtab.mock.wrap.10".flowTabUITestAccessibilityIdentifierComponent)"

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeKey(.downArrow, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        for _ in 0..<9 {
            app.typeKey(.downArrow, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        }

        XCTAssertTrue(
            hasHittableElement(
                in: app.descendants(matching: .any).matching(identifier: lastResultIdentifier),
                timeout: 2
            )
        )

        app.typeKey(.downArrow, modifierFlags: [])

        XCTAssertTrue(
            hasHittableElement(
                in: app.descendants(matching: .any).matching(identifier: firstResultIdentifier),
                timeout: 5
            )
        )
    }

    private func waitForSwitcherDiagnosticsValue(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        equals expectedValue: String,
        decodesPercentEncoding: Bool = false,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            var value = switcherPanelDiagnosticsValue(diagnosticsSummary, key: key)
            if decodesPercentEncoding {
                value = value.removingPercentEncoding ?? value
            }
            if value == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func assertSwitcherDiagnosticsValueRemains(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        equals expectedValue: String,
        duration: TimeInterval,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(duration)
        repeat {
            let value = switcherPanelDiagnosticsValue(diagnosticsSummary, key: key)
            if value != expectedValue {
                XCTFail(
                    "\(message) Expected \(key)=\(expectedValue), found \(value). summary=\(diagnosticsSummary.value ?? "")",
                    file: file,
                    line: line
                )
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
    }

    private func openInAppSwitcherForPointerHover(_ diagnosticsSummary: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(8)
        var attempt = 1
        repeat {
            postFlowTabUITestSwitcherTrigger(
                .inApp,
                traceLabel: "pointer.window.open.\(attempt)"
            )
            if diagnosticsSummary.waitForExistence(timeout: 1.2) {
                return true
            }
            attempt += 1
        } while Date() < deadline

        return diagnosticsSummary.exists
    }

    private func openSearchSwitcherForPointerHover(_ diagnosticsSummary: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(8)
        var attempt = 1
        repeat {
            postFlowTabUITestSwitcherTrigger(
                .search,
                traceLabel: "pointer.search.open.\(attempt)"
            )
            if diagnosticsSummary.waitForExistence(timeout: 1.2) {
                return true
            }
            attempt += 1
        } while Date() < deadline

        return diagnosticsSummary.exists
    }

    private func assertFrame(
        _ frame: CGRect,
        contains point: CGPoint,
        tolerance: CGFloat = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expandedFrame = frame.insetBy(dx: -tolerance, dy: -tolerance)
        XCTAssertTrue(
            expandedFrame.contains(point),
            "Expected stationary pointer point \(point) to remain inside target frame \(frame).",
            file: file,
            line: line
        )
    }

    private func assertSearchResultUsesRowSizedFrame(
        _ result: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(
            result.frame.width,
            200,
            "Search result hover tests must target the full result row, not only its label. frame=\(result.frame)",
            file: file,
            line: line
        )
    }

    private func hoverScreenPoint(_ point: CGPoint, relativeTo element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(
                CGVector(
                    dx: point.x - element.frame.minX,
                    dy: point.y - element.frame.minY
                )
            )
            .hover()
    }

    private func terminateAndWaitForNotRunning(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5), file: file, line: line)
    }

}
