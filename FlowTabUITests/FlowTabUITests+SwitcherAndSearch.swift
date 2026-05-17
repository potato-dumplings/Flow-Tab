import XCTest

extension FlowTabUITests {
    func testSearchPanelEntryAndResultActivation() throws {
        runRealSpaceFixtureWorkflow(
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher-search"]
        ) { identity, app in
            let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
            XCTAssertTrue(searchInput.waitForExistence(timeout: 5))

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            app.typeText(identity.switcherSearchQuery)

            let fixtureResult = app.descendants(matching: .any)
                .matching(identifier: identity.switcherSearchAppAccessibilityIdentifier)
                .firstMatch
            XCTAssertTrue(fixtureResult.waitForExistence(timeout: 5))

            app.typeText("\r")
            if !waitForNonExistence(searchInput, timeout: 1.2) {
                // XCUI keyboard input may leave the hidden NSTextView in a marked-text
                // composition state, so the first Return only commits composition.
                app.typeText("\r")
            }
            XCTAssertTrue(waitForNonExistence(searchInput, timeout: 3))
        }
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
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("测")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.test".flowTabUITestAccessibilityIdentifierComponent)")
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
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cs")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.test".flowTabUITestAccessibilityIdentifierComponent)")
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
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cs")

        let csgoResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.csgo".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(csgoResult.waitForExistence(timeout: 5))

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.test".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelCodeLikeSubsequenceShowsMockResult() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cgo")

        let csgoResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.xxx.csgo".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(csgoResult.waitForExistence(timeout: 5))
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
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("文件助手")

        let segmentedResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.\("com.flowtab.mock.file-transfer-assistant".flowTabUITestAccessibilityIdentifierComponent)")
            .firstMatch
        XCTAssertTrue(segmentedResult.waitForExistence(timeout: 5))
    }

    func testSwitcherInitialPresentationStaleOcclusionDoesNotHardRecover() throws {
        let logSnapshot = makeRuntimeLogFileSnapshot()
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-suppress-home-on-launch",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-initial-panel-occlusion-stale-ms",
                "260",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            .global,
            traceLabel: "initial-stale-occlusion"
        )
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherAppMockBrowser).waitForExistence(timeout: 5))

        waitForRuntimeLogFiles(
            containing: [
                "initial panel occlusion stale released",
                "presentationRecovery trigger=global_show action=complete"
            ],
            since: logSnapshot,
            timeout: 8
        )
        let logContents = runtimeLogContentsSinceSnapshot(logSnapshot)
        XCTAssertTrue(
            logContents.contains("presentationRecovery trigger=global_show action=softAttempt"),
            """
            Initial stale occlusion should exercise the soft recovery path.
            Runtime logs:
            \(logContents)
            """
        )
        XCTAssertFalse(
            logContents.contains("presentationRecovery trigger=global_show action=attempt"),
            """
            Initial stale occlusion should not trigger a hard recovery/orderOut path.
            Runtime logs:
            \(logContents)
            """
        )
    }

    func testSwitcherWindowLayerPaginatesLargeMockWindowSet() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-window-previews",
                "--flowtab-ui-enable-mock-hotkey-effects",
                "--flowtab-ui-mock-runtime-variant",
                "single-app-many-windows",
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-showPermissionReminder",
                "NO"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherAppMockManyWindows).waitForExistence(timeout: 5))

        postFlowTabUITestSwitcherCommandAndWaitForDelivery(.advanceDown, traceLabel: "many-window-page")

        let firstWindowID = "flowtab.switcher.window.\("mock-many-window-00".flowTabUITestAccessibilityIdentifierComponent)"
        XCTAssertTrue(element(in: app, identifier: firstWindowID).waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherNextWindowPage).waitForExistence(timeout: 2))

        let windowCards = switcherWindowCardObservations(in: app)
        XCTAssertGreaterThan(windowCards.count, 0)
        XCTAssertLessThan(windowCards.count, 20)
        XCTAssertTrue(
            windowCards.allSatisfy { $0.frame.width >= 100 },
            "Expected current visible window cards to keep preview width, found \(windowCards.map { "\($0.identifier)=\($0.frame)" })"
        )
        XCTAssertTrue(
            windowCards.allSatisfy(\.hasImage),
            "Expected current visible window cards to expose mock screenshots, found \(windowCards.map { "\($0.identifier)=\($0.value)" })"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "flowtab.switcher.window.\("mock-many-window-25".flowTabUITestAccessibilityIdentifierComponent)")
                .firstMatch
                .exists
        )
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
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))

        let firstResultIdentifier = "flowtab.switcher.search.app.\("com.flowtab.mock.wrap.01".flowTabUITestAccessibilityIdentifierComponent)"
        let lastResultIdentifier = "flowtab.switcher.search.app.\("com.flowtab.mock.wrap.10".flowTabUITestAccessibilityIdentifierComponent)"

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
            launchFlowTabUITestApplication(app)
            XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 5))
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        }
    }

}
