import XCTest

extension FlowTabUITests {
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

    private func assertCommittedMockSearchResults(
        in app: XCUIApplication,
        query: String,
        bundleIdentifiers: [String],
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rows = bundleIdentifiers.map { bundleIdentifier in
            FlowTabUITestSwitcherSearchExpectedResultRow(
                resultID: "app:\(bundleIdentifier)",
                rowIdentifier:
                    "flowtab.switcher.search.app."
                    + bundleIdentifier
                        .flowTabUITestAccessibilityIdentifierComponent
            )
        }
        XCTAssertTrue(
            performAndWaitForCommittedSearchResultRows(
                in: app,
                scope: "app",
                query: query,
                rows: rows,
                timeout: timeout,
                trigger: {
                    app.typeText(query)
                }
            ),
            "Search did not publish the exact committed mock "
                + "App result rows for query \(String(reflecting: query)).",
            file: file,
            line: line
        )
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

    func assertSwitcherAndSearchApplicationIsForegroundReady(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let becameReady = waitForFlowTabUITestApplicationToBecomeReady(
            app,
            timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy
                .switcherAndSearchForegroundReadiness
        )
        XCTAssertTrue(
            becameReady,
            "Switcher/Search application foreground-readiness "
                + "watchdog expired. unmetCondition=runningForeground "
                + "finalState=\(String(describing: app.state))",
            file: file,
            line: line
        )
    }

    private func waitForOptionTabPointerAppRows(
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        identifiers: [String],
        watchdog: TimeInterval,
        traceLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [XCUIElement]? {
        waitForExactElementCollection(
            in: app,
            identifiers: identifiers,
            watchdog: watchdog,
            targetDescription:
                "Option+Tab pointer App-row presentation",
            file: file,
            line: line,
            trigger: {
                XCTAssertTrue(
                    openGlobalSwitcherForPointerHover(
                        diagnosticsSummary,
                        traceLabel: traceLabel
                    ),
                    "Option+Tab pointer presentation did not "
                        + "publish its exact diagnostics summary.",
                    file: file,
                    line: line
                )
            }
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
        assertCommittedMockSearchResults(
            in: app,
            query: "测",
            bundleIdentifiers: ["com.xxx.test"],
            timeout:
                FlowTabUITestSwitcherAndSearchWatchdogPolicy
                    .searchMockSingleResultProjection
        )
    }

    func testSearchPanelPinyinInitialsShowChineseMockResult() throws {
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
        assertCommittedMockSearchResults(
            in: app,
            query: "cs",
            bundleIdentifiers: ["com.xxx.test"],
            timeout:
                FlowTabUITestSwitcherAndSearchWatchdogPolicy
                    .searchMockSingleResultProjection
        )
    }

    func testSearchPanelSharedCsQueryShowsCSGOAndChineseMockResults() throws {
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
        assertCommittedMockSearchResults(
            in: app,
            query: "cs",
            bundleIdentifiers: [
                "com.xxx.csgo",
                "com.xxx.test"
            ],
            timeout:
                FlowTabUITestSwitcherAndSearchWatchdogPolicy
                    .searchMockMultipleResultProjection
        )
    }

    func testSearchPanelCodeLikeSubsequenceShowsMockResult() throws {
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
        assertCommittedMockSearchResults(
            in: app,
            query: "cgo",
            bundleIdentifiers: ["com.xxx.csgo"],
            timeout:
                FlowTabUITestSwitcherAndSearchWatchdogPolicy
                    .searchMockSingleResultProjection
        )
    }

    func testSearchPanelSegmentedChineseQueryShowsCompoundMockResult() throws {
        let launch = launchSearchMockApplication()
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )
        assertCommittedMockSearchResults(
            in: app,
            query: "文件助手",
            bundleIdentifiers: [
                "com.flowtab.mock.file-transfer-assistant"
            ],
            timeout:
                FlowTabUITestSwitcherAndSearchWatchdogPolicy
                    .searchMockSingleResultProjection
        )
    }

    func testOptionTabSwitcherPointerHoverSelectsMockAppAfterMovement() throws {
        let app = makeApp(additionalArguments: optionTabPointerHoverArguments)
        launchFlowTabUITestApplication(app)
        assertSwitcherAndSearchApplicationIsForegroundReady(app)

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        guard
            let appTiles = waitForOptionTabPointerAppRows(
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                identifiers: [
                    Identifier.switcherAppMockBrowser,
                    Identifier.switcherAppMockMail
                ],
                watchdog:
                    FlowTabUITestSwitcherAndSearchWatchdogPolicy
                        .optionTabAppRowCollectionProjection,
                traceLabel: "pointer.app.hover"
            )
        else {
            return
        }
        let browserTile = appTiles[0]
        let mailTile = appTiles[1]
        XCTAssertTrue(
            waitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "selected",
                equals: "com.flowtab.mock.browser",
                timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy.optionTabSelectedAppProjection
            )
        )

        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "selected",
                equals: "com.flowtab.mock.mail",
                timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy.optionTabSelectedAppProjection,
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
        assertSwitcherAndSearchApplicationIsForegroundReady(app)

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        guard
            let mailTile = waitForOptionTabPointerAppRows(
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                identifiers: [
                    Identifier.switcherAppMockMail
                ],
                watchdog:
                    FlowTabUITestSwitcherAndSearchWatchdogPolicy
                        .optionTabSingleAppRowProjection,
                traceLabel: "pointer.app.click"
            )?.first
        else {
            return
        }

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
        assertSwitcherAndSearchApplicationIsForegroundReady(app)

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let primaryWindowID = "flowtab.switcher.window.\("mock-current-primary".flowTabUITestAccessibilityIdentifierComponent)"
        let secondaryWindowID = "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        guard
            let windows = waitForExactElementCollection(
                in: app,
                identifiers: [
                    primaryWindowID,
                    secondaryWindowID
                ],
                watchdog:
                    FlowTabUITestSwitcherAndSearchWatchdogPolicy
                        .controlTabWindowCollectionProjection,
                targetDescription:
                    "Control+Tab pointer Window-card presentation",
                trigger: {
                    XCTAssertTrue(
                        openInAppSwitcherForPointerHover(
                            diagnosticsSummary,
                            traceLabel: "pointer.window.hover"
                        ),
                        "Control+Tab pointer presentation did not "
                            + "publish its exact diagnostics summary."
                    )
                }
            )
        else {
            return
        }
        let primaryWindow = windows[0]
        let secondaryWindow = windows[1]

        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "selectedWindow",
                equals: "mock-current-secondary",
                timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy.controlTabSelectedWindowProjection,
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
        assertSwitcherAndSearchApplicationIsForegroundReady(app)

        let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
        let secondaryWindowID = "flowtab.switcher.window.\("mock-current-secondary".flowTabUITestAccessibilityIdentifierComponent)"
        guard
            let secondaryWindow = waitForExactElementCollection(
                in: app,
                identifiers: [secondaryWindowID],
                watchdog:
                    FlowTabUITestSwitcherAndSearchWatchdogPolicy
                        .controlTabSingleWindowProjection,
                targetDescription:
                    "Control+Tab pointer Window-card presentation",
                trigger: {
                    XCTAssertTrue(
                        openInAppSwitcherForPointerHover(
                            diagnosticsSummary,
                            traceLabel: "pointer.window.click"
                        ),
                        "Control+Tab pointer presentation did not "
                            + "publish its exact diagnostics summary."
                    )
                }
            )?.first
        else {
            return
        }

        assertElementDoesNotExistAfterTrigger(
            diagnosticsSummary,
            timeout: FlowTabUITestSwitcherAndSearchWatchdogPolicy.controlTabWindowClickDismissal,
            description: "Control+Tab window-card click presentation dismissal",
            trigger: { secondaryWindow.tap() }
        )
    }

    func testSearchPanelPointerHoverSelectsResultAfterMovement() throws {
        let app = makeApp(additionalArguments: searchPointerHoverArguments)
        guard
            let resultRows = launchAndWaitForPointerSearchResultRows(
                in: app,
                bundleIdentifiers: [
                    "com.flowtab.mock.mail",
                    "com.flowtab.mock.browser"
                ],
                timeout:
                    FlowTabUITestSwitcherAndSearchWatchdogPolicy
                        .searchPointerResultCollectionProjection
            )
        else {
            return
        }
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let mailResult = resultRows[0]
        let browserResult = resultRows[1]
        assertSearchResultUsesRowSizedFrame(mailResult)
        assertSearchResultUsesRowSizedFrame(browserResult)

        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "searchSelectedResult",
                equals: "app:com.flowtab.mock.browser",
                decodesPercentEncoding: true,
                timeout:
                    FlowTabUITestSwitcherAndSearchWatchdogPolicy
                        .searchSelectedResultProjection,
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
        guard
            let browserResult =
                launchAndWaitForPointerSearchResultRows(
                    in: app,
                    bundleIdentifiers: [
                        "com.flowtab.mock.browser"
                    ],
                    timeout:
                        FlowTabUITestSwitcherAndSearchWatchdogPolicy
                            .searchPointerSingleResultProjection
                )?.first
        else {
            return
        }
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
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
        assertSwitcherAndSearchApplicationIsForegroundReady(app)

        _ = waitForExactElementCollection(
            in: app,
            identifiers: [Identifier.switcherAppMockBrowser],
            watchdog: FlowTabUITestSwitcherAndSearchWatchdogPolicy.initialStaleOcclusionBrowserRowProjection,
            targetDescription: "Initial stale-occlusion Browser-row presentation"
        ) {
            postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                .global, traceLabel: "initial-stale-occlusion"
            )
        }

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
        assertSwitcherAndSearchApplicationIsForegroundReady(app)

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
        assertSwitcherAndSearchApplicationIsForegroundReady(app)
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

}
