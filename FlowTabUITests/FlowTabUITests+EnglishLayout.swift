import XCTest

extension FlowTabUITests {
    func testEnglishPrimarySurfacesExposeUsableLayoutAnchors() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level",
                "INFO",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "NO",
                "--flowtab-ui-seed-logs",
                "1"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        openSettingsTab(in: app)
        selectOption(in: app, controlIdentifier: Identifier.settingsAppearanceAppLanguage, optionIdentifier: "en")
        assertValue(of: element(in: app, identifier: Identifier.settingsAppearanceAppLanguage), equals: "en")

        let accessibilityButton = element(in: app, identifier: Identifier.settingsPermissionAccessibilityAction)
        let screenCaptureButton = element(in: app, identifier: Identifier.settingsPermissionScreenCaptureAction)
        let terminalPreviewToggle = toggleElement(
            in: app,
            identifier: Identifier.settingsPermissionTerminalContentPreviews
        )
        XCTAssertTrue(accessibilityButton.waitForExistence(timeout: 5))
        XCTAssertTrue(screenCaptureButton.waitForExistence(timeout: 5))
        XCTAssertTrue(terminalPreviewToggle.waitForExistence(timeout: 5))
        XCTAssertFalse(toggleIsOn(terminalPreviewToggle))
        XCTAssertTrue(app.staticTexts["Allow Terminal content previews"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "When enabled, FlowTab uses Apple Events to read the selected tab of the targeted Terminal window and renders the preview in memory."
            ].exists
        )
        XCTAssertTrue(accessibilityButton.isHittable)
        XCTAssertTrue(screenCaptureButton.isHittable)
        XCTAssertLessThanOrEqual(accessibilityButton.frame.height, 36)
        XCTAssertLessThanOrEqual(screenCaptureButton.frame.height, 36)

        openLogsTab(in: app)
        XCTAssertTrue(element(in: app, identifier: Identifier.logsTabContent).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start a 15-minute diagnostic session"].exists)

        openSettingsTab(in: app)
        let manageButton = element(in: app, identifier: Identifier.settingsAppVisibilityManage)
        XCTAssertTrue(manageButton.waitForExistence(timeout: 5))
        XCTAssertTrue(manageButton.isHittable)
        manageButton.click()
        XCTAssertTrue(element(in: app, identifier: Identifier.settingsAppVisibilityManager).waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["App Visibility"].waitForExistence(timeout: 5))

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
        selectOption(in: app, controlIdentifier: Identifier.settingsAppearanceAppLanguage, optionIdentifier: "en")
        assertValue(of: element(in: app, identifier: Identifier.settingsAppearanceAppLanguage), equals: "en")

        let accessibilityButton = element(in: app, identifier: Identifier.settingsPermissionAccessibilityAction)
        let screenCaptureButton = element(in: app, identifier: Identifier.settingsPermissionScreenCaptureAction)
        XCTAssertTrue(accessibilityButton.waitForExistence(timeout: 5))
        XCTAssertTrue(screenCaptureButton.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibilityButton.label, "Manage Accessibility permission")
        XCTAssertEqual(screenCaptureButton.label, "Manage Screen Recording permission")
        XCTAssertLessThanOrEqual(accessibilityButton.frame.height, 36)
        XCTAssertLessThanOrEqual(screenCaptureButton.frame.height, 36)
    }

    func testTerminalContentPreviewTogglePersistsExplicitOptInAcrossRelaunch() throws {
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

        let firstToggle = toggleElement(
            in: firstLaunchApp,
            identifier: Identifier.settingsPermissionTerminalContentPreviews
        )
        XCTAssertTrue(firstToggle.waitForExistence(timeout: 5))
        XCTAssertFalse(toggleIsOn(firstToggle))
        setToggle(firstToggle, to: true)
        XCTAssertTrue(toggleIsOn(firstToggle))

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(relaunchApp)
        openSettingsTab(in: relaunchApp)

        let relaunchToggle = toggleElement(
            in: relaunchApp,
            identifier: Identifier.settingsPermissionTerminalContentPreviews
        )
        XCTAssertTrue(relaunchToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggleIsOn(relaunchToggle))
    }
}
