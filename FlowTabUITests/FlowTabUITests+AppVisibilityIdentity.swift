import XCTest

private enum FlowTabUITestAppVisibilityIdentityVariant {
    static let closed = "app-visibility-identity-closed"
    static let accessory = "app-visibility-identity-accessory"
    static let regular = "app-visibility-identity-regular"
}

extension FlowTabUITests {
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

    func testAppVisibilitySeparatesStaticCapabilityFromDynamicRuntimeIdentity() throws {
        try configureDynamicAppAsHiddenWhileClosed()
        try assertDynamicAppPresentationWhileAccessory()
        try assertDynamicAppPreferenceAfterReturningToRegular()
    }

    private func configureDynamicAppAsHiddenWhileClosed() throws {
        let app = makeApp(
            additionalArguments: appVisibilityIdentityArguments(
                resetDefaults: true,
                variant: FlowTabUITestAppVisibilityIdentityVariant.closed
            )
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)
        guard assertHomeAndLogsOverviewChromeAfterNavigation(
            in: app,
            targetDescription: "closed dynamic-App Home projection"
        ) else {
            return
        }

        assertValue(of: element(in: app, identifier: Identifier.homeStatsTotalApps), equals: "1")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsVisibleApps), equals: "1")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsHiddenApps), equals: "0")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsTotalWindows), equals: "1")
        XCTAssertTrue(element(in: app, identifier: Identifier.homeAppIdentityEditor).exists)
        XCTAssertFalse(element(in: app, identifier: Identifier.homeAppIdentityDynamic).exists)
        XCTAssertFalse(element(in: app, identifier: Identifier.homeAppIdentityMenuBar).exists)
        XCTAssertFalse(element(in: app, identifier: Identifier.homeAppIdentityHelper).exists)

        openSettingsTab(in: app)
        let settingsHiddenCount = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityEffectiveHiddenCount
        )
        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "closed dynamic-App inventory"
        ) else {
            return
        }
        XCTAssertTrue(app.staticTexts["0 apps hidden"].exists)
        guard assertSettingsAppVisibilityQueryProjection(
            "Identity Dynamic",
            targetRowIdentifier: Identifier.settingsAppVisibilityIdentityDynamic,
            in: app,
            targetDescription: "closed dynamic-App query"
        ) else {
            return
        }
        guard let showToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityIdentityDynamic,
            in: app,
            targetDescription: "closed dynamic-App detail"
        ) else {
            return
        }

        XCTAssertTrue(showToggle.isEnabled)
        XCTAssertTrue(toggleIsOn(showToggle))
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityStandardToggleTitle
            ).exists
        )
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityEffectiveHiddenBadge
            ).waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.staticTexts["1 app hidden"].waitForExistence(timeout: 6))

        guard assertSettingsAppVisibilityRootProjectionAfterBackNavigation(
            in: app,
            targetDescription: "closed dynamic-App Settings count"
        ) else {
            return
        }
        assertValue(of: settingsHiddenCount, equals: "1 app hidden")
        assertIdentityStageTermination(app, description: "closed dynamic-App stage")
    }

    private func assertDynamicAppPresentationWhileAccessory() throws {
        let app = makeApp(
            additionalArguments: appVisibilityIdentityArguments(
                variant: FlowTabUITestAppVisibilityIdentityVariant.accessory
            )
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityEffectiveHiddenCount
            ),
            equals: "1 app hidden"
        )
        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "accessory dynamic-App inventory"
        ) else {
            return
        }
        guard assertSettingsAppVisibilityQueryProjection(
            "Identity Dynamic",
            targetRowIdentifier: Identifier.settingsAppVisibilityIdentityDynamic,
            in: app,
            targetDescription: "accessory dynamic-App query"
        ) else {
            return
        }
        guard let showToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityIdentityDynamic,
            in: app,
            targetDescription: "accessory dynamic-App detail"
        ) else {
            return
        }

        XCTAssertTrue(showToggle.isEnabled)
        XCTAssertFalse(toggleIsOn(showToggle))
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityRuntimeHiddenReason
            ).waitForExistence(timeout: 6)
        )
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityRegularModeToggleTitle
            ).exists
        )
        let effectiveHiddenBadge = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityEffectiveHiddenBadge
        )
        XCTAssertTrue(effectiveHiddenBadge.exists)

        setToggle(showToggle, to: true)
        XCTAssertTrue(toggleIsOn(showToggle))
        XCTAssertTrue(effectiveHiddenBadge.exists)
        XCTAssertTrue(app.staticTexts["1 app hidden"].exists)
        setToggle(showToggle, to: false)

        XCTAssertTrue(
            assertSettingsAppVisibilityHiddenFilterProjection(
                targetRowIdentifier: Identifier.settingsAppVisibilityIdentityDynamic,
                in: app,
                targetDescription: "accessory dynamic-App Hidden filter"
            )
        )
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: Identifier.settingsAppVisibilityIdentityDynamic)
                .count,
            1
        )

        tapElement(
            element(
                in: app,
                identifier: "flowtab.settings.app-visibility.filter.all"
            )
        )
        replaceText(
            in: element(in: app, identifier: Identifier.settingsAppVisibilitySearch),
            with: "",
            app: app
        )
        guard assertSettingsAppVisibilityQueryProjection(
            "Identity Menu Bar",
            targetRowIdentifier: Identifier.settingsAppVisibilityIdentityMenuBar,
            in: app,
            targetDescription: "static declaration query"
        ) else {
            return
        }
        tapElement(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityIdentityMenuBar
            )
        )
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityUnavailableReason
            ).waitForExistence(timeout: 6)
        )
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

        replaceText(
            in: element(in: app, identifier: Identifier.settingsAppVisibilitySearch),
            with: "",
            app: app
        )
        XCTAssertFalse(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityIdentityHelper
            ).exists
        )
        assertIdentityStageTermination(app, description: "accessory dynamic-App stage")
    }

    private func assertDynamicAppPreferenceAfterReturningToRegular() throws {
        let app = makeApp(
            additionalArguments:
                appVisibilityIdentityArguments(
                    variant: FlowTabUITestAppVisibilityIdentityVariant.regular,
                    listensForSwitcher: true
                )
                + FlowTabUITestSearchInputReadinessPolicy.applicationEvidenceLaunchArguments
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)
        guard assertHomeAndLogsOverviewChromeAfterNavigation(
            in: app,
            targetDescription: "regular dynamic-App Home projection"
        ) else {
            return
        }

        assertValue(of: element(in: app, identifier: Identifier.homeStatsTotalApps), equals: "2")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsVisibleApps), equals: "1")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsHiddenApps), equals: "1")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsTotalWindows), equals: "2")
        assertValue(
            of: element(in: app, identifier: Identifier.homeAppIdentityDynamic),
            equals: "1w hidden"
        )

        openSettingsTab(in: app)
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityEffectiveHiddenCount
            ),
            equals: "1 app hidden"
        )
        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "regular dynamic-App inventory"
        ) else {
            return
        }
        guard assertSettingsAppVisibilityQueryProjection(
            "Identity Dynamic",
            targetRowIdentifier: Identifier.settingsAppVisibilityIdentityDynamic,
            in: app,
            targetDescription: "regular dynamic-App query"
        ) else {
            return
        }
        guard let showToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityIdentityDynamic,
            in: app,
            targetDescription: "regular dynamic-App detail"
        ) else {
            return
        }
        XCTAssertTrue(showToggle.isEnabled)
        XCTAssertFalse(toggleIsOn(showToggle))
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityStandardToggleTitle
            ).exists
        )
        XCTAssertFalse(
            element(
                in: app,
                identifier: Identifier.settingsAppVisibilityRuntimeHiddenReason
            ).exists
        )

        XCTAssertTrue(
            performAndWaitForVisibleSwitcherAppProjection(
                in: app,
                requiredBundleIdentifiers: ["com.flowtab.mock.identity-editor"],
                excludedBundleIdentifiers: [
                    "com.flowtab.mock.identity-dynamic",
                    "com.flowtab.mock.identity-menu-bar",
                    "com.flowtab.mock.identity-helper"
                ],
                targetDescription: "regular dynamic-App Switcher projection",
                trigger: {
                    postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                        .global,
                        traceLabel: "regular-dynamic-app-switcher"
                    )
                }
            )
        )
        assertIdentityStageTermination(app, description: "regular dynamic-App Switcher stage")

        let searchApp = makeApp(
            additionalArguments:
                appVisibilityIdentityArguments(
                    variant: FlowTabUITestAppVisibilityIdentityVariant.regular,
                    listensForSwitcher: true
                )
                + FlowTabUITestSearchInputReadinessPolicy.applicationEvidenceLaunchArguments
        )
        let searchReadiness = prepareInitialFlowTabSearchInputReadiness()
        launchFlowTabUITestApplication(searchApp)
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            .search,
            traceLabel: "regular-dynamic-app-search"
        )
        _ = requireInitialFlowTabSearchInput(
            in: searchApp,
            observedBy: searchReadiness
        )
        let diagnosticsSummary = element(
            in: searchApp,
            identifier: Identifier.switcherSummary
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
                        expectedValue: "Identity Dynamic",
                        decodesPercentEncoding: true
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchResults",
                        expectedValue: ""
                    )
                ],
                in: diagnosticsSummary,
                timeout: 8,
                trigger: {
                    searchApp.typeText("Identity Dynamic")
                }
            )
        )
        assertIdentityStageTermination(searchApp, description: "regular dynamic-App Search stage")
    }

    private func appVisibilityIdentityArguments(
        resetDefaults: Bool = false,
        variant: String,
        listensForSwitcher: Bool = false
    ) -> [String] {
        var arguments = [
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-mock-runtime-variant",
            variant,
            "-showPermissionReminder",
            "NO",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES"
        ]
        if resetDefaults {
            arguments.insert(contentsOf: [
                "-AppleLanguages",
                "(en)",
                "--flowtab-ui-reset-defaults"
            ], at: 0)
        }
        if listensForSwitcher {
            arguments.append("--flowtab-ui-listen-switcher-trigger")
        }
        return arguments
    }

    private func assertIdentityStageTermination(
        _ app: XCUIApplication,
        description: String
    ) {
        let termination = terminateFlowTabUITestApplication(
            app,
            targetDescription: description
        )
        XCTAssertTrue(
            termination.isSatisfied,
            "Identity stage did not terminate. \(termination.diagnosticSummary)"
        )
    }
}
