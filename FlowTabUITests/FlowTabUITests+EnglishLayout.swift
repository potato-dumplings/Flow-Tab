import XCTest

extension FlowTabUITests {
    func testEnglishPrimarySurfacesExposeUsableLayoutAnchors() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "NO",
                "--flowtab-ui-seed-logs",
                "1"
            ]
                + FlowTabUITestSearchInputReadinessPolicy
                    .applicationEvidenceLaunchArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        openSettingsTab(in: app)
        assertSettingsPermissionActionProjection(
            in: app,
            targetDescription: "English primary permission actions"
        ) {
            selectOption(
                in: app,
                controlIdentifier:
                    Identifier.settingsAppearanceAppLanguage,
                optionIdentifier: "en"
            )
            assertValue(
                of: element(
                    in: app,
                    identifier:
                        Identifier.settingsAppearanceAppLanguage
                ),
                equals: "en"
            )
        }

        openLogsTab(in: app)
        XCTAssertTrue(app.staticTexts["Start a 15-minute diagnostic session"].exists)

        openSettingsTab(in: app)
        guard assertSettingsAppVisibilityManagerProjectionAfterNavigation(
            in: app,
            expectedManagerTitle: "App Visibility",
            targetDescription: "English primary App Visibility manager"
        ) else {
            return
        }

        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(.search, traceLabel: "english-layout.search")
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchAppMockMail).waitForExistence(timeout: 5))
    }

    func testEnglishGrantedPermissionActionsUseManageLabels() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        openSettingsTab(in: app)
        assertSettingsPermissionActionProjection(
            in: app,
            expectedAccessibilityLabel:
                "Manage Accessibility permission",
            expectedScreenCaptureLabel:
                "Manage Screen Recording permission",
            targetDescription: "English granted permission actions"
        ) {
            selectOption(
                in: app,
                controlIdentifier:
                    Identifier.settingsAppearanceAppLanguage,
                optionIdentifier: "en"
            )
            assertValue(
                of: element(
                    in: app,
                    identifier:
                        Identifier.settingsAppearanceAppLanguage
                ),
                equals: "en"
            )
        }
    }

    func testTerminalContentPreviewPermissionControlIsAbsent() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let terminalPreviewToggle = toggleElement(
            in: app,
            identifier: Identifier.settingsPermissionTerminalContentPreviews
        )
        XCTAssertFalse(terminalPreviewToggle.exists)
        XCTAssertFalse(app.staticTexts["Allow Terminal content previews"].exists)
    }
}
