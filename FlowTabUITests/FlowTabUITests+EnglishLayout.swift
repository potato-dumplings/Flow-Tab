import XCTest

enum FlowTabUITestEnglishSearchProjectionPolicy {
    static let projectionWatchdog: TimeInterval = 10
}

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
        assertEnglishFlowTabForegroundReadiness(
            in: app,
            targetDescription: "English primary surfaces"
        )

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
        XCTAssertTrue(app.staticTexts["Log level"].exists)

        openSettingsTab(in: app)
        guard assertSettingsAppVisibilityManagerProjectionAfterNavigation(
            in: app,
            expectedManagerTitle: "App Visibility",
            targetDescription: "English primary App Visibility manager"
        ) else {
            return
        }

        guard
            waitForExactElementCollection(
                in: app,
                identifiers: [
                    Identifier.switcherSearchInput,
                    Identifier.switcherSearchAppMockMail
                ],
                watchdog:
                    FlowTabUITestEnglishSearchProjectionPolicy
                        .projectionWatchdog,
                targetDescription: "English primary Search",
                trigger: {
                    postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
                        .search,
                        traceLabel: "english-layout.search"
                    )
                }
            ) != nil
        else {
            return
        }
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
        assertEnglishFlowTabForegroundReadiness(
            in: app,
            targetDescription: "English granted-permission actions"
        )

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

    private func assertEnglishFlowTabForegroundReadiness(
        in app: XCUIApplication,
        targetDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let readinessSatisfied =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .foregroundActivation
            )
        XCTAssertTrue(
            readinessSatisfied,
            "\(targetDescription) foreground readiness watchdog expired. "
                + "finalState=\(String(describing: app.state))",
            file: file,
            line: line
        )
    }
}
