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
        XCTAssertTrue(accessibilityButton.waitForExistence(timeout: 5))
        XCTAssertTrue(screenCaptureButton.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibilityButton.isHittable)
        XCTAssertTrue(screenCaptureButton.isHittable)
        XCTAssertLessThanOrEqual(accessibilityButton.frame.height, 36)
        XCTAssertLessThanOrEqual(screenCaptureButton.frame.height, 36)

        openLogsTab(in: app)
        XCTAssertTrue(element(in: app, identifier: Identifier.logsTabContent).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Enable verbose runtime logs (high-frequency, may impact performance)"].exists)

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
}
