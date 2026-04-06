import XCTest

extension FlowTabUITests {
    func testSwitcherPanelShowsMockAppTilesInStandardMode() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherPanel).waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(element(in: app, identifier: Identifier.switcherSearchInput).exists)
    }

    func testSearchPanelEntryAndResultActivation() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("browser")

        let browserResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-flowtab-mock-browser")
            .firstMatch
        XCTAssertTrue(browserResult.waitForExistence(timeout: 5))

        app.typeText("\r")
        if !waitForNonExistence(switcherPanel, timeout: 1.2) {
            // XCUI keyboard input may leave the hidden NSTextView in a marked-text
            // composition state, so the first Return only commits composition.
            app.typeText("\r")
        }
        XCTAssertTrue(waitForNonExistence(switcherPanel, timeout: 3))
    }

    func testSearchPanelChineseQueryShowsChineseMockResult() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("测")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-xxx-test")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelPinyinInitialsShowChineseMockResult() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cs")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-xxx-test")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelSharedCsQueryShowsCSGOAndChineseMockResults() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cs")

        let csgoResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-xxx-csgo")
            .firstMatch
        XCTAssertTrue(csgoResult.waitForExistence(timeout: 5))

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-xxx-test")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelSegmentedChineseQueryShowsCompoundMockResult() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("文件助手")

        let segmentedResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-flowtab-mock-file-transfer-assistant")
            .firstMatch
        XCTAssertTrue(segmentedResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelWrapFromLastResultScrollsBackToFirstResult() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                "search-wrap",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        let firstResultIdentifier = "flowtab.switcher.search.app.com-flowtab-mock-wrap-01"
        let lastResultIdentifier = "flowtab.switcher.search.app.com-flowtab-mock-wrap-10"

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeKey(.downArrow, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        for _ in 0..<9 {
            app.typeKey(.downArrow, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        }

        XCTAssertTrue(
            hasHittableElement(
                in: app.descendants(matching: .any).matching(identifier: lastResultIdentifier),
                timeout: 2
            )
        )

        app.typeKey(.downArrow, modifierFlags: [])

        XCTAssertTrue(
            hasHittableElement(
                in: app.descendants(matching: .any).matching(identifier: firstResultIdentifier),
                timeout: 5
            )
        )
    }

    func testSwitcherPanelMoveAppThenAutoEnterWindowLayerShowsMockWindows() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 8))

        app.typeKey(.escape, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let mailInboxWindow = switcherPanel.descendants(matching: .any)
            .matching(identifier: Identifier.switcherWindowMockMailInbox)
            .firstMatch
        let mailDraftWindow = switcherPanel.descendants(matching: .any)
            .matching(identifier: Identifier.switcherWindowMockMailDraft)
            .firstMatch
        XCTAssertFalse(mailInboxWindow.exists)
        XCTAssertFalse(mailDraftWindow.exists)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.typeKey(.leftArrow, modifierFlags: [])

        XCTAssertTrue(mailInboxWindow.waitForExistence(timeout: 3))
        XCTAssertTrue(mailDraftWindow.waitForExistence(timeout: 3))
    }

    func testTabSwitchStressCPUAndMemory() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let app = makeApp(
                additionalArguments: [
                    "--flowtab-ui-reset-defaults",
                    "--flowtab-ui-mock-runtime",
                    "--flowtab-tab-stress",
                    "--flowtab-tab-stress-duration",
                    "2",
                    "--flowtab-tab-stress-interval-ms",
                    "16",
                    "-showPermissionReminder",
                    "NO"
                ]
            )
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        }
    }

}
