import AppKit
import XCTest

private enum FlowTabUITestSettingsSearchWatchdogPolicy {
    static let committedResultProjection: TimeInterval = 8
    static let userTriggeredAppProjection: TimeInterval = 8
    static let applicationForeground: TimeInterval = 10
}

extension FlowTabUITests {
    func testSettingsSearchWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .committedResultProjection,
            8
        )
        XCTAssertTrue(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .committedResultProjection.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .committedResultProjection,
            0
        )
        XCTAssertEqual(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .userTriggeredAppProjection,
            8
        )
        XCTAssertTrue(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .userTriggeredAppProjection.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .userTriggeredAppProjection,
            0
        )
        XCTAssertEqual(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .applicationForeground,
            10
        )
        XCTAssertTrue(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .applicationForeground.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .applicationForeground,
            0
        )
    }

    func testSettingsSearchDisabledPreventsAutoSearchLaunchEntry() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-record-hotkey-reload-diagnostics",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        let searchEnabledToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsSearchEnabled)
        XCTAssertTrue(searchEnabledToggle.waitForExistence(timeout: 5))
        setToggle(searchEnabledToggle, to: false)
        XCTAssertFalse(toggleIsOn(searchEnabledToggle))
        let firstTermination = terminateFlowTabUITestApplication(
            firstLaunchApp,
            targetDescription: "disabled-Search settings process"
        )
        XCTAssertTrue(
            firstTermination.isSatisfied,
            "Disabled-Search settings process did not terminate. "
                + firstTermination.diagnosticSummary
        )

        let resolutionRoute =
            FlowTabUITestInitialPresentationResolutionRoute()
        try resolutionRoute.prepareReadback()
        let resolutionOwner =
            FlowTabUITestInitialPresentationResolutionObservationOwner(
                route: resolutionRoute,
                expectation:
                    FlowTabUITestInitialPresentationResolutionExpectation(
                        requiredItemIDs: [
                            "com.flowtab.mock.mail"
                        ],
                        searchFeatureEnabled: false,
                        searchIsActive: false,
                        searchActivationIsPending: false
                    )
            )
        resolutionOwner.start()
        defer {
            resolutionOwner.cancel()
            resolutionRoute.removeReadback()
        }

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ] + resolutionRoute.launchArguments
        )
        launchFlowTabUITestApplication(relaunchApp)
        guard let resolution =
                resolutionOwner.waitForResolution(
                    timeout:
                        FlowTabUITestInitialPresentationResolutionPolicy
                            .watchdog
                )
        else {
            XCTFail(
                "Disabled-Search initial presentation watchdog "
                    + "expired. "
                    + resolutionOwner.diagnosticSummary
            )
            return
        }
        XCTAssertEqual(resolution.sessionMode, "appCycle")
        XCTAssertFalse(resolution.searchFeatureEnabled)
        XCTAssertFalse(resolution.searchIsActive)
        XCTAssertFalse(resolution.searchActivationIsPending)
        XCTAssertEqual(
            resolution.postPresentationItemIDs,
            resolution.candidateItemIDs
        )
        let relaunchTermination = terminateFlowTabUITestApplication(
            relaunchApp,
            targetDescription: "disabled-Search command process"
        )
        XCTAssertTrue(
            relaunchTermination.isSatisfied,
            "Disabled-Search command process did not terminate. "
                + relaunchTermination.diagnosticSummary
        )
    }

    func testSettingsSearchDefaultScopePersistsAndShowsWindowThenAppResults() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        let searchEnabledToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsSearchEnabled)
        XCTAssertTrue(searchEnabledToggle.waitForExistence(timeout: 5))
        setToggle(searchEnabledToggle, to: true)

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "window")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")
        firstLaunchApp.terminate()

        let windowSearchApp = launchMockSwitcherSearchFromUserPath()
        XCTAssertTrue(
            performAndWaitForCommittedSearchResultRow(
                in: windowSearchApp,
                scope: "window",
                query: "Inbox",
                resultID:
                    "window:com.flowtab.mock.mail#mock-mail-inbox",
                rowIdentifier:
                    Identifier.switcherSearchWindowMockMailInbox,
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .committedResultProjection,
                trigger: {
                    windowSearchApp.typeText("Inbox")
                }
            ),
            "Window-scope Search did not publish the exact "
                + "committed Inbox result row."
        )
        windowSearchApp.terminate()

        let settingsRelaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(settingsRelaunchApp)
        openSettingsTab(in: settingsRelaunchApp)
        assertValue(of: element(in: settingsRelaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")

        selectOption(in: settingsRelaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "app")
        assertValue(of: element(in: settingsRelaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "app")
        settingsRelaunchApp.terminate()

        let appSearchApp = launchMockSwitcherSearchFromUserPath()
        XCTAssertTrue(
            performAndWaitForCommittedSearchResultRow(
                in: appSearchApp,
                scope: "app",
                query: "Mail",
                resultID: "app:com.flowtab.mock.mail",
                rowIdentifier:
                    Identifier.switcherSearchAppMockMail,
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .committedResultProjection,
                trigger: {
                    appSearchApp.typeText("Mail")
                }
            ),
            "App-scope Search did not publish the exact "
                + "committed Mail result row."
        )
    }

    func testSettingsSearchDefaultScopeCanSwitchBetweenAppAndWindow() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        let searchEnabledToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsSearchEnabled)
        XCTAssertTrue(searchEnabledToggle.waitForExistence(timeout: 5))
        setToggle(searchEnabledToggle, to: true)

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "app")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "app")

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "window")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")
    }

    func testSettingsSearchWindowScopeUnavailableWithoutAccessibilityPermission() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        let becameForeground =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .applicationForeground,
                traceLabel:
                    "settings-search-permission-scope-readiness"
            )
        XCTAssertTrue(
            becameForeground,
            "Settings Search permission-scope application readiness "
                + "watchdog expired. expectedState=runningForeground "
                + "finalState=\(String(describing: app.state))"
        )
        assertSettingsSearchWindowScopeUnavailable(in: app) {
            openSettingsTab(in: app)
        }
    }

    func testSettingsAppVisibilityNavigationConvergesFromVisibleState() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(
                resetDefaults: true
            )
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let manager = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityManager
        )
        let manageButton = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityManage
        )
        guard assertSettingsAppVisibilityManagerProjectionAfterNavigation(
            in: app,
            targetDescription: "visible-state App Visibility manager"
        ) else {
            return
        }

        let backButton = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityBack
        )
        XCTAssertTrue(backButton.waitForExistence(timeout: 6))
        tapElement(backButton)

        XCTAssertTrue(waitForNonExistence(manager, timeout: 6))
        XCTAssertTrue(manageButton.waitForExistence(timeout: 6))
    }

    func testSettingsAppVisibilityHidesMockAppFromSwitcherAndSearch() throws {
        let settingsApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(settingsApp)
        openSettingsTab(in: settingsApp)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: settingsApp,
            targetDescription: "hidden-App configuration inventory"
        ) else {
            return
        }

        guard assertSettingsAppVisibilityQueryProjection(
            "Mail",
            targetRowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: settingsApp,
            targetDescription: "hidden-App configuration Search projection"
        ) else {
            return
        }

        guard let showToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: settingsApp,
            targetDescription: "hidden-App configuration detail"
        ) else {
            return
        }
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))
        let settingsTermination = terminateFlowTabUITestApplication(
            settingsApp,
            targetDescription: "settings app visibility configuration"
        )
        XCTAssertTrue(
            settingsTermination.isSatisfied,
            "Settings app termination failed. "
                + settingsTermination.diagnosticSummary
        )

        let switcherApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(opensSwitcher: true)
        )
        guard assertInitialSwitcherAppProjectionAfterLaunch(
            in: switcherApp,
            requiredBundleIdentifiers: ["com.flowtab.mock.browser"],
            excludedBundleIdentifiers: ["com.flowtab.mock.mail"],
            targetDescription: "hidden-App Switcher relaunch projection",
            trigger: {
                launchFlowTabUITestApplication(switcherApp)
            }
        ) else {
            return
        }
        let switcherTermination = terminateFlowTabUITestApplication(
            switcherApp,
            targetDescription: "app visibility switcher verification"
        )
        XCTAssertTrue(
            switcherTermination.isSatisfied,
            "Switcher app termination failed. "
                + switcherTermination.diagnosticSummary
        )

        let searchApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(opensSearch: true)
        )
        let searchReadiness =
            prepareInitialFlowTabSearchInputReadiness()
        launchFlowTabUITestApplication(searchApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(searchApp, timeout: 10))
        _ = requireInitialFlowTabSearchInput(
            in: searchApp,
            observedBy: searchReadiness
        )
        let diagnosticsSummary = element(
            in: searchApp,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(
            diagnosticsSummary.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                [
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchResultsScope",
                        expectedValue: "app"
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchResultsQuery",
                        expectedValue: "Mail",
                        decodesPercentEncoding: true
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchResults",
                        expectedValue: ""
                    )
                ],
                in: diagnosticsSummary,
                timeout: 5,
                trigger: {
                    searchApp.typeText("Mail")
                }
            ),
            "Search did not commit the exact empty app-result projection for Mail."
        )
        XCTAssertFalse(
            element(
                in: searchApp,
                identifier: Identifier.switcherSearchAppMockMail
            ).exists
        )
    }

    func testSettingsAppVisibilitySelectionPublishesExactDetailToggle() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "selected-detail regression inventory"
        ) else {
            return
        }
        guard assertSettingsAppVisibilityQueryProjection(
            "Mail",
            targetRowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: app,
            targetDescription: "selected-detail regression Search projection"
        ) else {
            return
        }
        guard let showToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: app,
            targetDescription: "selected-detail regression target"
        ) else {
            return
        }

        XCTAssertTrue(toggleIsOn(showToggle))
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))
    }

    func testSettingsAppVisibilitySearchUsesSharedPinyinMatching() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "pinyin Search inventory"
        ) else {
            return
        }

        XCTAssertTrue(
            assertSettingsAppVisibilityQueryProjection(
                "ceshi",
                targetRowIdentifier:
                    Identifier.settingsAppVisibilityChineseTest,
                in: app,
                targetDescription: "pinyin Search projection"
            )
        )
    }

    func testSettingsCurrentAppActivationPolicyAppearsAsHiddenApp() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let showInCommandTabToggle = toggleElement(
            in: app,
            identifier: Identifier.settingsAppearanceShowInCommandTab
        )
        XCTAssertTrue(showInCommandTabToggle.waitForExistence(timeout: 6))
        XCTAssertFalse(toggleIsOn(showInCommandTabToggle))
        XCTAssertTrue(app.staticTexts["已隐藏 1 个应用"].waitForExistence(timeout: 6))

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "current-App inventory"
        ) else {
            return
        }

        guard assertSettingsAppVisibilityHiddenFilterProjection(
            targetRowIdentifier: Identifier.settingsAppVisibilityCurrentApp,
            in: app,
            targetDescription: "current-App Hidden filter projection"
        ) else {
            return
        }

        guard let showToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityCurrentApp,
            in: app,
            targetDescription: "current-App Hidden detail"
        ) else {
            return
        }
        XCTAssertFalse(toggleIsOn(showToggle))
    }

    func testSettingsAppVisibilityHiddenFilterShowsStoredHiddenAppMissingFromInventory() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: firstLaunchApp,
            targetDescription: "stored hidden-App source inventory"
        ) else {
            return
        }

        guard assertSettingsAppVisibilityQueryProjection(
            "Mail",
            targetRowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: firstLaunchApp,
            targetDescription: "stored hidden-App source Search projection"
        ) else {
            return
        }

        guard let showToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: firstLaunchApp,
            targetDescription: "stored hidden-App source detail"
        ) else {
            return
        }
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))
        firstLaunchApp.terminate()

        let staleInventoryApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(
                mockRuntimeVariant: "single-app-five-windows"
            )
        )
        launchFlowTabUITestApplication(staleInventoryApp)
        openSettingsTab(in: staleInventoryApp)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: staleInventoryApp,
            targetDescription: "stale hidden-App inventory"
        ) else {
            return
        }

        guard assertSettingsAppVisibilityHiddenFilterProjection(
            targetRowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: staleInventoryApp,
            targetDescription: "stale hidden-App filter projection"
        ) else {
            return
        }

        guard let staleShowToggle =
            settingsAppVisibilityShowToggleAfterSelecting(
                rowIdentifier: Identifier.settingsAppVisibilityMockMail,
                in: staleInventoryApp,
                targetDescription: "stale hidden-App detail"
            )
        else {
            return
        }
        XCTAssertFalse(toggleIsOn(staleShowToggle))
    }

    private func launchMockSwitcherSearchFromUserPath() -> XCUIApplication {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
                + FlowTabUITestSearchInputReadinessPolicy
                    .applicationEvidenceLaunchArguments
        )
        launchFlowTabUITestApplication(app)
        let becameForeground =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .applicationForeground,
                traceLabel:
                    "settings-search-user-path-readiness"
            )
        XCTAssertTrue(
            becameForeground,
            "Settings Search user-path application readiness "
                + "watchdog expired. expectedState=runningForeground "
                + "finalState=\(String(describing: app.state))"
        )
        XCTAssertTrue(
            assertInitialSwitcherAppProjectionAfterLaunch(
                in: app,
                requiredBundleIdentifiers: [
                    "com.flowtab.mock.mail"
                ],
                excludedBundleIdentifiers: [],
                targetDescription:
                    "Settings Search user-path Switcher",
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .userTriggeredAppProjection,
                trigger: {
                    postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                        .global,
                        traceLabel: "settings-search-user-path"
                    )
                }
            ),
            "Settings Search user path did not present the exact "
                + "Mail App projection."
        )

        let searchReadiness =
            prepareInitialFlowTabSearchInputReadiness()
        app.typeText("\r")

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: searchReadiness
        )
        return app
    }

    private func appVisibilityRuntimeArguments(
        resetDefaults: Bool = false,
        opensSwitcher: Bool = false,
        opensSearch: Bool = false,
        mockRuntimeVariant: String? = nil
    ) -> [String] {
        var arguments: [String] = []
        if resetDefaults {
            arguments.append("--flowtab-ui-reset-defaults")
        }
        arguments += [
            "--flowtab-ui-mock-runtime",
            "-showPermissionReminder",
            "NO",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES"
        ]
        if opensSearch {
            arguments.append("--flowtab-ui-open-switcher-search")
            arguments +=
                FlowTabUITestSearchInputReadinessPolicy
                    .applicationEvidenceLaunchArguments
        } else if opensSwitcher {
            arguments.append("--flowtab-ui-open-switcher")
        }
        if let mockRuntimeVariant {
            arguments += [
                "--flowtab-ui-mock-runtime-variant",
                mockRuntimeVariant
            ]
        }
        return arguments
    }

}
