import XCTest

extension FlowTabUITests {
    func testRunningHiddenApplicationsStayVisibleOnHomeAfterMembershipRefresh() throws {
        let app = makeApp(
            additionalArguments: [
                "-AppleLanguages",
                "(zh-Hans)",
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                "application-membership-transition",
                "--flowtab-ui-include-current-app-in-inventory",
                "--flowtab-ui-enable-mock-hotkey-effects",
                "--flowtab-ui-listen-switcher-trigger",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        assertSwitcherAndSearchApplicationIsForegroundReady(app)

        XCUIElement.perform(withKeyModifiers: .option) {
            XCTAssertTrue(
                performAndWaitForVisibleSwitcherAppProjection(
                    in: app,
                    requiredBundleIdentifiers: [
                        "com.flowtab.mock.membership-stable"
                    ],
                    excludedBundleIdentifiers: [
                        "com.flowtab.mock.membership-final-accessory"
                    ],
                    targetDescription: "final accessory membership projection",
                    trigger: {
                        app.typeKey(.tab, modifierFlags: .option)
                    }
                )
            )
        }

        assertValue(of: element(in: app, identifier: Identifier.homeStatsTotalApps), equals: "3")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsVisibleApps), equals: "1")
        assertValue(of: element(in: app, identifier: Identifier.homeStatsHiddenApps), equals: "2")
        XCTAssertTrue(
            element(in: app, identifier: Identifier.homeAppMembershipStable)
                .waitForExistence(timeout: 5)
        )
        let accessoryRow = element(
            in: app,
            identifier: Identifier.homeAppMembershipFinalAccessory
        )
        XCTAssertTrue(accessoryRow.waitForExistence(timeout: 5))
        XCTAssertTrue(accessoryRow.staticTexts["0w"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[Identifier.homeAppMembershipFinalAccessory].exists)

        let currentAppID = FlowTabUITestAppIdentity.configured().bundleIdentifier
        let currentAppIDComponent =
            currentAppID.flowTabUITestAccessibilityIdentifierComponent
        let currentAppRowIdentifier = "flowtab.home.app.\(currentAppIDComponent)"
        let currentAppRow = element(in: app, identifier: currentAppRowIdentifier)
        XCTAssertTrue(currentAppRow.waitForExistence(timeout: 5))
        XCTAssertTrue(currentAppRow.staticTexts["0w"].waitForExistence(timeout: 5))

        let hiddenBadgePrefix = "flowtab.home.app.hidden-badge."
        let currentAppBadge = element(
            in: app,
            identifier: "\(hiddenBadgePrefix)\(currentAppIDComponent)"
        )
        let accessoryBadge = element(
            in: app,
            identifier:
                "\(hiddenBadgePrefix)"
                + "com.flowtab.mock.membership-final-accessory"
                    .flowTabUITestAccessibilityIdentifierComponent
        )
        XCTAssertTrue(currentAppBadge.waitForExistence(timeout: 5))
        XCTAssertTrue(accessoryBadge.waitForExistence(timeout: 5))
        XCTAssertTrue(
            currentAppRow.staticTexts["已隐藏"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            accessoryRow.staticTexts["已隐藏"].waitForExistence(timeout: 5)
        )

        openSettingsTab(in: app)
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityEffectiveHiddenCount
            ),
            equals: "已隐藏 2 个应用"
        )
        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "共享隐藏应用清单"
        ) else {
            return
        }
        XCTAssertTrue(app.staticTexts["已隐藏 2 个应用"].waitForExistence(timeout: 5))
    }
}
