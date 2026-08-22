import AppKit
import XCTest

private enum FlowTabUITestSettingsSearchWatchdogPolicy {
    static let committedResultProjection: TimeInterval = 8
    static let userTriggeredAppProjection: TimeInterval = 8
    static let applicationForeground: TimeInterval = 10
    static let searchEnabledToggleProjection: TimeInterval = 5
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
        XCTAssertEqual(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .searchEnabledToggleProjection,
            5
        )
        XCTAssertTrue(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .searchEnabledToggleProjection.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsSearchWatchdogPolicy
                .searchEnabledToggleProjection,
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

        let searchEnabledToggle = requireSettingsSearchEnabledToggle(
            in: firstLaunchApp,
            scenario: "disabled initial launch"
        )
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
                        excludedItemIDs: [],
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
                "--flowtab-ui-mock-window-previews",
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

        let searchEnabledToggle = requireSettingsSearchEnabledToggle(
            in: firstLaunchApp,
            scenario: "persisted default scope initial launch"
        )
        setToggle(searchEnabledToggle, to: true)

        selectOption(
            in: firstLaunchApp,
            controlIdentifier: Identifier.settingsSearchDefaultScope,
            optionIdentifier: "window"
        )
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

        let searchEnabledToggle = requireSettingsSearchEnabledToggle(
            in: firstLaunchApp,
            scenario: "scope switching initial launch"
        )
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

        guard assertSettingsAppVisibilityManagerProjectionAfterNavigation(
            in: app,
            targetDescription: "visible-state App Visibility manager"
        ) else {
            return
        }

        guard assertSettingsAppVisibilityRootProjectionAfterBackNavigation(
            in: app,
            targetDescription: "visible-state Settings root"
        ) else {
            return
        }
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
            additionalArguments:
                appVisibilityRuntimeArguments()
                + ["--flowtab-ui-listen-switcher-trigger"]
                + FlowTabUITestSearchInputReadinessPolicy.applicationEvidenceLaunchArguments
        )
        launchFlowTabUITestApplication(switcherApp)
        let switcherBecameForeground =
            waitForFlowTabUITestApplicationToBecomeReady(
                switcherApp,
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .applicationForeground,
                traceLabel:
                    "settings-app-visibility-hidden-switcher-readiness"
            )
        guard switcherBecameForeground else {
            XCTFail(
                "Hidden-App Switcher application readiness watchdog "
                    + "expired. expectedState=runningForeground "
                    + "finalState=\(String(describing: switcherApp.state))"
            )
            return
        }
        guard performAndWaitForVisibleSwitcherAppProjection(
            in: switcherApp,
            requiredBundleIdentifiers: ["com.flowtab.mock.browser"],
            excludedBundleIdentifiers: ["com.flowtab.mock.mail"],
            targetDescription: "hidden-App Switcher relaunch projection",
            trigger: {
                postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                    .global,
                    traceLabel:
                        "settings-app-visibility-hidden-switcher"
                )
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
            additionalArguments:
                appVisibilityRuntimeArguments()
                + ["--flowtab-ui-listen-switcher-trigger"]
                + FlowTabUITestSearchInputReadinessPolicy.applicationEvidenceLaunchArguments
        )
        let searchReadiness =
            prepareInitialFlowTabSearchInputReadiness()
        launchFlowTabUITestApplication(searchApp)
        let becameForeground =
            waitForFlowTabUITestApplicationToBecomeReady(
                searchApp,
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .applicationForeground,
                traceLabel:
                    "settings-app-visibility-hidden-search-readiness"
            )
        guard becameForeground else {
            XCTFail(
                "Hidden-App Search application readiness watchdog "
                    + "expired. expectedState=runningForeground "
                    + "finalState=\(String(describing: searchApp.state))"
            )
            return
        }
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            .search,
            traceLabel:
                "settings-app-visibility-hidden-search"
        )
        _ = requireInitialFlowTabSearchInput(
            in: searchApp,
            observedBy: searchReadiness
        )
        let diagnosticsSummary = element(
            in: searchApp,
            identifier: Identifier.switcherSummary
        )
        guard
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
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .committedResultProjection,
                trigger: {
                    searchApp.typeText("Mail")
                }
            )
        else {
            return
        }
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

    func testAppVisibilityIdentityCatalogExcludesAuxiliaryAndDisablesSystemManagedVisibility() throws {
        let app = makeApp(
            additionalArguments:
                appVisibilityRuntimeArguments(
                    resetDefaults: true,
                    mockRuntimeVariant: "app-visibility-identity"
                )
                + ["--flowtab-ui-listen-switcher-trigger"]
                + FlowTabUITestSearchInputReadinessPolicy.applicationEvidenceLaunchArguments
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)
        guard assertHomeAndLogsOverviewChromeAfterNavigation(
            in: app,
            targetDescription: "application identity Home projection"
        ) else {
            return
        }

        assertValue(of: element(in: app, identifier: Identifier.homeStatsTotalApps), equals: "1")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsVisibleApps), equals: "1")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsHiddenApps), equals: "0")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsTotalWindows), equals: "1")
        XCTAssertTrue(element(in: app, identifier: Identifier.homeAppIdentityEditor).exists)
        XCTAssertFalse(element(in: app, identifier: Identifier.homeAppIdentityMenuBar).exists)
        XCTAssertFalse(element(in: app, identifier: Identifier.homeAppIdentityHelper).exists)

        openSettingsTab(in: app)
        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "application identity inventory"
        ) else {
            return
        }
        guard assertSettingsAppVisibilityQueryProjection(
            "Identity Menu Bar",
            targetRowIdentifier: Identifier.settingsAppVisibilityIdentityMenuBar,
            in: app,
            targetDescription: "system-managed application query"
        ) else {
            return
        }

        let systemManagedRow = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityIdentityMenuBar
        )
        tapElement(systemManagedRow)
        let reason = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityUnavailableReason
        )
        XCTAssertTrue(reason.waitForExistence(timeout: 6))
        let systemManagedToggle = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityShowToggle
        )
        XCTAssertTrue(systemManagedToggle.exists)
        XCTAssertFalse(systemManagedToggle.isEnabled)
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilitySystemManagedBadge
            ).exists
        )
        XCTAssertFalse(
            element(in: app, identifier: Identifier.settingsAppVisibilityIdentityHelper).exists
        )

        replaceText(
            in: element(in: app, identifier: Identifier.settingsAppVisibilitySearch),
            with: "",
            app: app
        )
        guard assertSettingsAppVisibilityQueryProjection(
            "Identity Editor",
            targetRowIdentifier: Identifier.settingsAppVisibilityIdentityEditor,
            in: app,
            targetDescription: "configurable application query"
        ) else {
            return
        }
        guard let configurableToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityIdentityEditor,
            in: app,
            targetDescription: "configurable application detail"
        ) else {
            return
        }
        XCTAssertTrue(configurableToggle.isEnabled)
        XCTAssertTrue(toggleIsOn(configurableToggle))

        XCTAssertTrue(
            performAndWaitForVisibleSwitcherAppProjection(
                in: app,
                requiredBundleIdentifiers: ["com.flowtab.mock.identity-editor"],
                excludedBundleIdentifiers: [
                    "com.flowtab.mock.identity-menu-bar",
                    "com.flowtab.mock.identity-helper"
                ],
                targetDescription: "application identity Switcher projection",
                trigger: {
                    postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                        .global,
                        traceLabel: "application-identity-switcher"
                    )
                }
            )
        )
    }

    func testSettingsCurrentAppActivationPolicyAppearsAsHiddenApp() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        guard assertSettingsCurrentAppActivationProjectionAfterNavigation(
            in: app,
            targetDescription: "current-App activation-policy Settings",
            trigger: {
                openSettingsTab(in: app)
            }
        ) else {
            return
        }

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

    func testSettingsAppVisibilityHiddenFilterRemovesStoredHiddenAppMissingFromInventory() throws {
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

        let hiddenFilter = element(
            in: staleInventoryApp,
            identifier: Identifier.settingsAppVisibilityFilterHidden
        )
        let hiddenProjection = staleInventoryApp.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    Identifier.settingsAppVisibilityHiddenFilterProjectionPrefix
                )
            )
            .firstMatch
        tapElement(hiddenFilter)
        XCTAssertTrue(hiddenProjection.waitForExistence(timeout: 6))
        XCTAssertFalse(
            element(
                in: staleInventoryApp,
                identifier: Identifier.settingsAppVisibilityMockMail
            ).exists
        )
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
            performAndWaitForVisibleSwitcherAppProjection(
                in: app,
                requiredBundleIdentifiers: [
                    "com.flowtab.mock.mail"
                ],
                excludedBundleIdentifiers: [],
                targetDescription:
                    "Settings Search user-path Switcher",
                watchdog:
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

    private func requireSettingsSearchEnabledToggle(
        in app: XCUIApplication,
        scenario: String
    ) -> XCUIElement {
        let toggle = element(
            in: app,
            identifier: Identifier.settingsSearchEnabled
        )
        let wasInitiallyPresent = toggle.exists
        let waiterSatisfied = wasInitiallyPresent
            || toggle.waitForExistence(
                timeout:
                    FlowTabUITestSettingsSearchWatchdogPolicy
                        .searchEnabledToggleProjection
            )
        let finalExists = toggle.exists
        let finalElementType = finalExists
            ? String(describing: toggle.elementType)
            : "unavailable"
        let finalHittable = finalExists
            ? String(toggle.isHittable)
            : "unavailable"
        let finalValue = finalExists
            ? String(describing: toggle.value)
            : "unavailable"
        XCTAssertTrue(
            waiterSatisfied && finalExists,
            "Settings Search enabled-toggle projection watchdog expired. "
                + "scenario=\(scenario) "
                + "expectedIdentifier=\(Identifier.settingsSearchEnabled) "
                + "appState=\(String(describing: app.state)) "
                + "initialExists=\(wasInitiallyPresent) "
                + "waiterSatisfied=\(waiterSatisfied) "
                + "finalExists=\(finalExists) "
                + "finalElementType=\(finalElementType) "
                + "finalHittable=\(finalHittable) "
                + "finalValue=\(finalValue)"
        )
        return toggle
    }

    private func appVisibilityRuntimeArguments(
        resetDefaults: Bool = false,
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
        if let mockRuntimeVariant {
            arguments += [
                "--flowtab-ui-mock-runtime-variant",
                mockRuntimeVariant
            ]
        }
        return arguments
    }

}
