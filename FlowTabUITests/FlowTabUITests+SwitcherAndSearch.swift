import XCTest

private enum FlowTabUITestSwitcherAndSearchWatchdogPolicy {
    static let optionTabAppClickDismissal: TimeInterval = 2
    static let controlTabWindowClickDismissal: TimeInterval = 2
    static let searchResultClickDismissal: TimeInterval = 2
    static let searchMockForegroundReadiness: TimeInterval = 10
    static let spaceFixtureSearchResultPublication: TimeInterval = 5
    static let searchHeaderProjection: TimeInterval = 10
    static let compatibleBounds = [
        optionTabAppClickDismissal,
        controlTabWindowClickDismissal,
        searchResultClickDismissal,
        searchMockForegroundReadiness,
        spaceFixtureSearchResultPublication,
        searchHeaderProjection
    ]
}

extension FlowTabUITests {
    func testSwitcherAndSearchWatchdogPolicyPreservesCompatibleBounds() {
        let policies = FlowTabUITestSwitcherAndSearchWatchdogPolicy.compatibleBounds
        XCTAssertEqual(policies, [2, 2, 2, 10, 5, 10])
        XCTAssertTrue(policies.allSatisfy { $0.isFinite && $0 > 0 })
    }

    private var searchPointerHoverArguments: [String] {
        searchMockRuntimeArguments()
    }

    var searchPointerHoverTriggerArguments: [String] {
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

    func launchSearchMockApplication(
        mockRuntimeVariant: String? = nil
    ) -> (
        app: XCUIApplication,
        readiness:
            FlowTabUITestSearchInputReadinessObservationOwner
    ) {
        let app = makeApp(
            additionalArguments:
                searchMockRuntimeArguments(
                    mockRuntimeVariant:
                        mockRuntimeVariant
                )
        )
        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        launchFlowTabUITestApplication(app)
        assertSearchMockApplicationIsForegroundReady(app)
        return (app, readiness)
    }

    private func assertSearchMockApplicationIsForegroundReady(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let becameReady = waitForFlowTabUITestApplicationToBecomeReady(
            app,
            timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy
                .searchMockForegroundReadiness
        )
        XCTAssertTrue(
            becameReady,
            "Search mock application foreground-readiness watchdog expired. "
                + "unmetCondition=runningForeground "
                + "finalState=\(String(describing: app.state))",
            file: file,
            line: line
        )
    }

    func testSearchPanelEntryAndResultActivation() throws {
        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
        runRealSpaceFixtureWorkflow(
            flowTabAdditionalArguments:
                ["--flowtab-ui-open-switcher-search"]
                + FlowTabUITestSwitcherSearchConfirmationPolicy
                    .applicationEvidenceLaunchArguments
        ) { identity, app in
            let searchInput =
                requireInitialFlowTabSearchInput(
                    in: app,
                    observedBy: readiness
                )
            XCTAssertTrue(
                performAndWaitForCommittedSearchResultRow(
                    in: app,
                    scope: "app",
                    query: identity.switcherSearchQuery,
                    resultID: "app:\(identity.bundleIdentifier)",
                    rowIdentifier:
                        identity
                            .switcherSearchAppAccessibilityIdentifier,
                    timeout:
                        FlowTabUITestSwitcherAndSearchWatchdogPolicy
                            .spaceFixtureSearchResultPublication,
                    trigger: {
                        app.typeText(
                            identity.switcherSearchQuery
                        )
                    }
                ),
                "Search did not publish the exact committed "
                    + "Space fixture App result row."
            )

            confirmSwitcherSearchSelection(
                in: app,
                searchInput: searchInput,
                expectedQuery: identity.switcherSearchQuery
            )
        }
    }

    func testSearchHeaderHighlightedAppChipStaysContentSizedForShortTitle() throws {
        let app = makeApp(additionalArguments: searchPointerHoverArguments)
        guard
            let searchElements = waitForExactElementCollection(
                in: app,
                identifiers: [
                    Identifier.switcherSearchHeader,
                    Identifier.switcherSearchHighlight
                ],
                watchdog:
                    FlowTabUITestSwitcherAndSearchWatchdogPolicy
                        .searchHeaderProjection,
                targetDescription:
                    "Search header and highlighted App chip",
                trigger: {
                    launchFlowTabUITestApplication(app)
                    assertSearchMockApplicationIsForegroundReady(app)
                }
            )
        else {
            return
        }
        let highlightedChip = searchElements[1]
        XCTAssertGreaterThan(highlightedChip.frame.width, 40)
        XCTAssertLessThan(
            highlightedChip.frame.width,
            150,
            "Short highlighted app names should stay content-sized instead of expanding to the long-title width cap."
        )
    }

    func testSearchPanelChineseQueryShowsChineseMockResult() throws {
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
        app.typeText("测")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.test".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelPinyinInitialsShowChineseMockResult() throws {
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
        app.typeText("cs")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.test".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelSharedCsQueryShowsCSGOAndChineseMockResults() throws {
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
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
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
        app.typeText("cgo")

        let csgoResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.csgo".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(csgoResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelSegmentedChineseQueryShowsCompoundMockResult() throws {
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
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
        XCTAssertTrue(
            openGlobalSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel: "pointer.app.hover"
            )
        )
        XCTAssertTrue(browserTile.waitForExistence(timeout: 5))
        XCTAssertTrue(mailTile.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "selected",
                equals: "com.flowtab.mock.browser",
                timeout: 3
            )
        )

        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "selected",
                equals: "com.flowtab.mock.mail",
                timeout: 3,
                trigger: {
                    browserTile.coordinate(
                        withNormalizedOffset:
                            CGVector(dx: 0.5, dy: 0.5)
                    ).hover()
                    mailTile.coordinate(
                        withNormalizedOffset:
                            CGVector(dx: 0.5, dy: 0.5)
                    ).hover()
                }
            ),
            "Hovering a switcher app tile after pointer movement should update the selected app. browserFrame=\(browserTile.frame) mailFrame=\(mailTile.frame) summary=\(diagnosticsSummary.value ?? "")"
        )
    }

    func testOptionTabSwitcherClickCommitsAppAndClosesPanel() throws {
        let app = makeApp(additionalArguments: optionTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let mailTile = element(in: app, identifier: Identifier.switcherAppMockMail)
        XCTAssertTrue(
            openGlobalSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel: "pointer.app.click"
            )
        )
        XCTAssertTrue(mailTile.waitForExistence(timeout: 5))

        assertElementDoesNotExistAfterTrigger(
            diagnosticsSummary,
            timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy.optionTabAppClickDismissal,
            description: "Option+Tab App-card click presentation dismissal",
            trigger: { mailTile.tap() }
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
        XCTAssertTrue(
            openInAppSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel: "pointer.window.hover"
            )
        )
        XCTAssertTrue(primaryWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(secondaryWindow.waitForExistence(timeout: 5))

        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "selectedWindow",
                equals: "mock-current-secondary",
                timeout: 3,
                trigger: {
                    primaryWindow.coordinate(
                        withNormalizedOffset:
                            CGVector(dx: 0.5, dy: 0.5)
                    ).hover()
                    secondaryWindow.coordinate(
                        withNormalizedOffset:
                            CGVector(dx: 0.5, dy: 0.5)
                    ).hover()
                }
            ),
            "Hovering a Control+Tab window card after pointer movement should update the selected window."
        )
    }

    func testControlTabSwitcherClickCommitsWindowAndClosesPanel() throws {
        let app = makeApp(additionalArguments: controlTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let secondaryWindowID = "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        let secondaryWindow = element(in: app, identifier: secondaryWindowID)
        XCTAssertTrue(
            openInAppSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel: "pointer.window.click"
            )
        )
        XCTAssertTrue(secondaryWindow.waitForExistence(timeout: 5))

        assertElementDoesNotExistAfterTrigger(
            diagnosticsSummary,
            timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy.controlTabWindowClickDismissal,
            description: "Control+Tab window-card click presentation dismissal",
            trigger: { secondaryWindow.tap() }
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

        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "searchSelectedResult",
                equals: "app:com.flowtab.mock.browser",
                decodesPercentEncoding: true,
                timeout: 3,
                trigger: {
                    mailResult.coordinate(
                        withNormalizedOffset:
                            CGVector(dx: 0.5, dy: 0.5)
                    ).hover()
                    browserResult.coordinate(
                        withNormalizedOffset:
                            CGVector(dx: 0.5, dy: 0.5)
                    ).hover()
                }
            ),
            "Hovering a search result after pointer movement should update the selected search result."
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

        assertElementDoesNotExistAfterTrigger(
            diagnosticsSummary,
            timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy.searchResultClickDismissal,
            description: "Search result-row click presentation dismissal",
            trigger: { browserResult.tap() }
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

    func assertSearchResultUsesRowSizedFrame(
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

}
