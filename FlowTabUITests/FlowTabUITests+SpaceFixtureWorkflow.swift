import Foundation
import XCTest

extension FlowTabUITests {
    func testHomePageShowsPublishedDockIconFromRealSpaceFixture() throws {
        runRealSpaceFixtureWorkflow(
            fixtureAdditionalArguments: [
                "--dock-icon-resource-name",
                "PublishedDockIcon.svg"
            ]
        ) { identity, app in
            let fixtureAppRow = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity)
            assertPublishedDockIconPixelSignature(in: fixtureAppRow)
        }
    }

    func testHomePageShowsRealSpaceFixtureWorkflowWindows() throws {
        runRealSpaceFixtureWorkflow { identity, app in
            let fixtureAppRow = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity)
            assertValue(of: fixtureAppRow, equals: "3w", timeout: 20)
            assertSpaceFixtureWindowTitles(
                expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Workflow", windowCount: 3),
                in: app
            )
        }
    }

    func testHomePageSelectingRealSpaceFixtureAppShowsWorkflowWindowTitles() throws {
        runRealSpaceFixtureWorkflow { identity, app in
            _ = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity)
            assertSpaceFixtureWindowTitles(
                expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Workflow", windowCount: 3),
                in: app
            )
        }
    }

    func testSwitcherPanelShowsRealSpaceFixtureAppTileInStandardMode() throws {
        runRealSpaceFixtureWorkflow(
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { identity, app in
            let fixtureAppTile = element(in: app, identifier: identity.switcherAppAccessibilityIdentifier)
            XCTAssertTrue(
                fixtureAppTile.waitForExistence(timeout: 8),
                "FlowTab did not surface the Space Fixture app in the switcher app strip"
            )
        }
    }

    func testSwitcherPanelQuitShortcutKeepsRealFixtureAppUntilProcessTerminates() throws {
        let identity = spaceFixtureAppIdentity
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 1,
            fullscreenWindowIndex: nil,
            titlePrefix: "Quit Target",
            enterFullscreenDelayMilliseconds: 0,
            terminationDelayMilliseconds: 2_400
        )
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                fixtureApp.terminate()
                waitForSpaceFixtureApplicationToTerminate(fixtureApp)
            }
        }

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let app = makeRealRuntimeFlowTabApp(
            additionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-listen-switcher-trigger"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))

        let fixtureAppTile = element(in: app, identifier: identity.switcherAppAccessibilityIdentifier)
        XCTAssertTrue(fixtureAppTile.waitForExistence(timeout: 12))
        try postFlowTabUITestSelectSwitcherAppAndWaitForDelivery(
            bundleIdentifier: identity.bundleIdentifier,
            traceLabel: "quitFixture.selectApp"
        )
        XCTAssertTrue(waitForSwitcherSummary(in: app, containing: "selected=\(identity.bundleIdentifier)", timeout: 5))

        let logSnapshot = makeRuntimeLogFileSnapshot()
        app.activate()
        app.typeKey("q", modifierFlags: .option)

        waitForRuntimeLogFiles(
            containing: [
                "terminate request app=",
                "appID=\(identity.bundleIdentifier) sent=true"
            ],
            since: logSnapshot,
            timeout: 8
        )
        XCTAssertNotEqual(fixtureApp.state, .notRunning)
        XCTAssertTrue(
            fixtureAppTile.exists,
            "The selected fixture app should remain in the panel while its process is still terminating."
        )

        XCTAssertTrue(waitForApplicationToTerminate(fixtureApp, timeout: 8))
        waitForRuntimeLogFiles(
            containing: [
                "terminate post-refresh reason=",
                "appID=\(identity.bundleIdentifier)"
            ],
            since: logSnapshot,
            timeout: 10
        )
        let refreshedFixtureAppTile = element(
            in: app,
            identifier: identity.switcherAppAccessibilityIdentifier
        )
        XCTAssertTrue(waitForNonExistence(refreshedFixtureAppTile, timeout: 8))
        XCTAssertTrue(waitForSwitcherSummary(in: app, containing: "apps=", timeout: 5))
    }

    func testRuntimeLifecycleRefreshesRealFixtureAppLaunchAndTermination() throws {
        let identity = spaceFixtureAppIdentity

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let app = makeRealRuntimeFlowTabApp(
            additionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))

        let launchLogSnapshot = makeRuntimeLogFileSnapshot()
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 1,
            fullscreenWindowIndex: nil,
            titlePrefix: "Lifecycle",
            enterFullscreenDelayMilliseconds: 0
        )
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                fixtureApp.terminate()
                waitForSpaceFixtureApplicationToTerminate(fixtureApp)
            }
        }

        waitForRuntimeLogFiles(
            containing: [
                "runtimeLifecycle appLaunched appID=\(identity.bundleIdentifier)",
                "pid="
            ],
            since: launchLogSnapshot,
            timeout: 8
        )

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let fixtureAppRow = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity, timeout: 12)
        assertValue(of: fixtureAppRow, equals: "1w", timeout: 12)

        let terminationLogSnapshot = makeRuntimeLogFileSnapshot()
        fixtureApp.terminate()
        XCTAssertTrue(waitForApplicationToTerminate(fixtureApp, timeout: 8))
        waitForRuntimeLogFiles(
            containing: [
                "runtimeLifecycle appTerminated appID=\(identity.bundleIdentifier)",
                "pid="
            ],
            since: terminationLogSnapshot,
            timeout: 8
        )
    }

    func testRuntimeLifecycleRefreshesRealFixtureWindowSetMutation() throws {
        let identity = spaceFixtureAppIdentity

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let app = makeRealRuntimeFlowTabApp(
            additionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))

        let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 2,
            fullscreenWindowIndex: nil,
            titlePrefix: "Mutation",
            enterFullscreenDelayMilliseconds: 0,
            closeWindowIndex: 2,
            closeWindowDelayMilliseconds: 7_500
        )
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                fixtureApp.terminate()
                waitForSpaceFixtureApplicationToTerminate(fixtureApp)
            }
        }

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let fixtureAppRow = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity, timeout: 12)
        assertValue(of: fixtureAppRow, equals: "2w", timeout: 12)

        assertValue(of: fixtureAppRow, equals: "1w", timeout: 15)
        waitForRuntimeLogFiles(
            containing: [
                "homeAppDetailProjectionRead result=observed appID=\(identity.bundleIdentifier)",
                "reason=ax_window_destroyed"
            ],
            since: mutationLogSnapshot,
            timeout: 8
        )
        waitForRuntimeLogFiles(
            matching: #"homeAXDestroyed known appID=io[.]github[.]potato-dumplings[.]flowtab[.]spacefixture pid=[0-9]+ axWindowID=ax:[0-9]+:[0-9]+"#,
            since: mutationLogSnapshot,
            timeout: 8,
            description: "known destroyed AX notification resolves to a registered window element"
        )
        waitForRuntimeLogFiles(
            matching: #"runtimeAXDestroyed appID=io[.]github[.]potato-dumplings[.]flowtab[.]spacefixture pid=[0-9]+ axWindowID=ax:[0-9]+:[0-9]+ affectedCGWindowID=(none|[0-9]+)"#,
            since: mutationLogSnapshot,
            timeout: 8,
            description: "known destroyed AX notification carries an affected CG window into shared runtime reconciliation"
        )
        XCTAssertNotEqual(fixtureApp.state, .notRunning)
    }

    func testSwitcherPanelShowsRealSpaceFixtureWorkflowWindowCards() throws {
        runRealSpaceFixtureWorkflow(
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-listen-switcher-trigger"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        ) { identity, app in
            let fixtureAppTile = element(in: app, identifier: identity.switcherAppAccessibilityIdentifier)
            XCTAssertTrue(fixtureAppTile.waitForExistence(timeout: 8))
            selectSwitcherAppDirectly(
                in: app,
                appID: identity.bundleIdentifier,
                traceLabel: "workflowWindowCards.selectApp"
            )

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            app.typeKey(.downArrow, modifierFlags: [])
            XCTAssertTrue(waitForSwitcherSummary(in: app, containing: "mode=windowCycle", timeout: 5))

            assertSpaceFixtureSwitcherWindowCards(
                expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Workflow", windowCount: 3),
                in: app
            )
        }
    }

    func testSwitcherPanelRefreshesOpenWindowLayerAfterRealFixtureWindowSetMutation() throws {
        let identity = spaceFixtureAppIdentity

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 2,
            fullscreenWindowIndex: nil,
            titlePrefix: "Open Mutation",
            enterFullscreenDelayMilliseconds: 0,
            closeWindowIndex: 2,
            closeWindowDelayMilliseconds: 15_000
        )
        let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                fixtureApp.terminate()
                waitForSpaceFixtureApplicationToTerminate(fixtureApp)
            }
        }

        let app = makeRealRuntimeFlowTabApp(
            additionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-listen-switcher-trigger",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))

        let fixtureAppTile = element(in: app, identifier: identity.switcherAppAccessibilityIdentifier)
        XCTAssertTrue(fixtureAppTile.waitForExistence(timeout: 12))
        selectSwitcherAppDirectly(
            in: app,
            appID: identity.bundleIdentifier,
            traceLabel: "openWindowLayerMutation.selectApp",
            timeout: 8
        )

        let allTitles = expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Open Mutation", windowCount: 2)
        app.activate()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitForSwitcherSummary(in: app, containing: "mode=windowCycle", timeout: 5))
        _ = waitForSwitcherWindowCards(in: app, expectedTitles: allTitles, timeout: 8)

        _ = waitForSwitcherWindowCards(
            in: app,
            expectedTitles: [allTitles[0]],
            timeout: 25
        )
        waitForRuntimeLogFiles(
            matching: #"runtimeAXDestroyed appID=io[.]github[.]potato-dumplings[.]flowtab[.]spacefixture pid=[0-9]+ axWindowID=ax:[0-9]+:[0-9]+ affectedCGWindowID=(none|[0-9]+)"#,
            since: mutationLogSnapshot,
            timeout: 8,
            description: "open Switcher window-layer mutation should flow through shared runtime AX destroyed reconciliation"
        )
        XCTAssertNotEqual(fixtureApp.state, .notRunning)
    }

    func testSwitcherPanelKeepsWindowLayerWhenSelectedFixtureWindowCloses() throws {
        let identity = spaceFixtureAppIdentity

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 2,
            fullscreenWindowIndex: nil,
            titlePrefix: "Selected Mutation",
            enterFullscreenDelayMilliseconds: 0,
            closeWindowIndex: 1,
            closeWindowDelayMilliseconds: 15_000
        )
        let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                fixtureApp.terminate()
                waitForSpaceFixtureApplicationToTerminate(fixtureApp)
            }
        }

        let app = makeRealRuntimeFlowTabApp(
            additionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-listen-switcher-trigger",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))

        let fixtureAppTile = element(in: app, identifier: identity.switcherAppAccessibilityIdentifier)
        XCTAssertTrue(fixtureAppTile.waitForExistence(timeout: 12))
        selectSwitcherAppDirectly(
            in: app,
            appID: identity.bundleIdentifier,
            traceLabel: "selectedWindowMutation.selectApp",
            timeout: 8
        )

        let allTitles = expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Selected Mutation", windowCount: 2)
        app.activate()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitForSwitcherSummary(in: app, containing: "mode=windowCycle", timeout: 5))
        _ = waitForSwitcherWindowCards(in: app, expectedTitles: allTitles, timeout: 8)

        _ = waitForSwitcherWindowCards(
            in: app,
            expectedTitles: [allTitles[1]],
            timeout: 25
        )
        XCTAssertTrue(waitForSwitcherSummary(in: app, containing: "mode=windowCycle", timeout: 5))
        waitForRuntimeLogFiles(
            matching: #"runtimeAXDestroyed appID=io[.]github[.]potato-dumplings[.]flowtab[.]spacefixture pid=[0-9]+ axWindowID=ax:[0-9]+:[0-9]+ affectedCGWindowID=(none|[0-9]+)"#,
            since: mutationLogSnapshot,
            timeout: 8,
            description: "selected fixture window close should preserve open Switcher window-layer through shared runtime reconciliation"
        )
        XCTAssertNotEqual(fixtureApp.state, .notRunning)
    }

    private func selectSwitcherAppDirectly(
        in app: XCUIApplication,
        appID: String,
        traceLabel: String,
        timeout: TimeInterval = 4
    ) {
        do {
            try postFlowTabUITestSelectSwitcherAppAndWaitForDelivery(
                bundleIdentifier: appID,
                traceLabel: traceLabel,
                timeout: timeout
            )
        } catch {
            XCTFail("Failed to select switcher app \(appID): \(error)")
            return
        }

        XCTAssertTrue(waitForSwitcherSummary(in: app, containing: "selected=\(appID)", timeout: timeout))
    }

    private func waitForSwitcherSummary(
        in app: XCUIApplication,
        containing marker: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestValue = ""
        repeat {
            latestValue = switcherSummary(in: app)
            if latestValue.contains(marker) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail("Expected switcher summary to contain \(marker). Latest summary: \(latestValue)")
        return false
    }

    private func switcherSummary(in app: XCUIApplication) -> String {
        let summary = element(in: app, identifier: Identifier.switcherSummary)
        guard summary.exists else { return "" }
        return elementStringValue(summary)
    }

    private func waitForApplicationToTerminate(
        _ app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.state == .notRunning {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    func makeSpaceFixtureWorkflowFile(_ contents: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("workflow.json")
        try Data(contents.utf8).write(to: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return fileURL
    }

    func runRealSpaceFixtureWorkflow(
        flowTabAdditionalArguments: [String] = [],
        fixtureAdditionalArguments: [String] = [],
        perform assertions: (SpaceFixtureAppIdentity, XCUIApplication) -> Void
    ) {
        let identity = spaceFixtureAppIdentity
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 3,
            fullscreenWindowIndex: 3,
            titlePrefix: "Workflow",
            enterFullscreenDelayMilliseconds: 5_000,
            fixtureAdditionalArguments: fixtureAdditionalArguments
        )
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                fixtureApp.terminate()
            }
        }

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let app = makeRealRuntimeFlowTabApp(additionalArguments: flowTabAdditionalArguments)
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))
        assertions(identity, app)
    }

    private func openHomeTabAndSelectSpaceFixtureApp(
        in app: XCUIApplication,
        identity: SpaceFixtureAppIdentity,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10)
        )

        let fixtureAppRows = app.buttons.matching(identifier: identity.homeAppAccessibilityIdentifier)
        let fixtureAppRow = fixtureAppRows.firstMatch
        XCTAssertTrue(fixtureAppRow.waitForExistence(timeout: timeout))
        XCTAssertTrue(
            tapFirstHittable(in: fixtureAppRows, timeout: timeout),
            "FlowTab did not surface the real Space Fixture app on the home page"
        )
        return fixtureAppRow
    }

    private func assertSpaceFixtureWindowTitles(
        _ expectedTitles: [String],
        in app: XCUIApplication,
        timeout: TimeInterval = 12
    ) {
        for title in expectedTitles {
            assertHomeWindowTitle(title, in: app, timeout: timeout, message: "Missing window title: \(title)")
        }
    }

    private func assertSpaceFixtureSwitcherWindowCards(
        _ expectedTitles: [String],
        in app: XCUIApplication,
        timeout: TimeInterval = 12
    ) {
        _ = waitForSwitcherWindowCards(in: app, expectedTitles: expectedTitles, timeout: timeout)
    }

    private func assertPublishedDockIconPixelSignature(in appRow: XCUIElement) {
        let screenshot = appRow.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Home row with published Dock icon"
        attachment.lifetime = .deleteOnSuccess
        add(attachment)

        guard let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation) else {
            XCTFail("Could not decode the Home app row screenshot")
            return
        }

        var magentaPixelCount = 0
        var cyanPixelCount = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if color.redComponent > 0.85,
                   color.greenComponent < 0.5,
                   color.blueComponent > 0.7 {
                    magentaPixelCount += 1
                }
                if color.greenComponent > 0.85,
                   color.blueComponent > 0.9,
                   color.greenComponent - color.redComponent > 0.15,
                   color.blueComponent - color.redComponent > 0.2 {
                    cyanPixelCount += 1
                }
            }
        }

        XCTAssertGreaterThan(magentaPixelCount, 50)
        XCTAssertGreaterThan(cyanPixelCount, 50)
    }
}
