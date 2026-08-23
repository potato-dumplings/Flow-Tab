import XCTest

extension FlowTabUITests {
    func testFirstPanelPresentationRemovesAppWhoseFinalIdentityIsAccessory() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                "application-membership-transition",
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

        assertValue(
            of: element(in: app, identifier: Identifier.homeStatsTotalApps),
            equals: "1"
        )
        XCTAssertTrue(
            element(in: app, identifier: Identifier.homeAppMembershipStable)
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            element(in: app, identifier: Identifier.homeAppMembershipFinalAccessory)
                .exists
        )
    }
}
