import AppKit
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
        let terminationRoute =
            makeSpaceFixtureTerminationFaultRoute()
        let terminationObservation =
            SpaceFixtureTerminationFaultObservationOwner(
                route: terminationRoute
            )
        terminationObservation.start()
        defer {
            terminationObservation.cancel()
        }
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 1,
            fullscreenWindowIndex: nil,
            titlePrefix: "Quit Target",
            enterFullscreenDelayMilliseconds: 0,
            terminationDelayMilliseconds: 2_400,
            fixtureAdditionalArguments:
                terminationRoute.fixtureLaunchArguments
        )
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                terminateSpaceFixtureApplicationAndWait(fixtureApp, identity: identity)
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

        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: nil,
            targetDescription: "quit-shortcut-post-fixture-launch"
        )

        let fixtureAppTile = element(in: app, identifier: identity.switcherAppAccessibilityIdentifier)
        XCTAssertTrue(fixtureAppTile.waitForExistence(timeout: 12))
        selectSwitcherAppDirectly(
            in: app,
            appID: identity.bundleIdentifier,
            traceLabel: "quitFixture.selectApp"
        )

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
        let scheduledEvidence = try XCTUnwrap(
            terminationObservation.waitForScheduled(
                timeout: 8
            ),
            "Fixture did not publish scheduled termination evidence: "
                + terminationObservation.diagnosticSummary
        )
        XCTAssertEqual(
            scheduledEvidence.source,
            .terminationSignal
        )
        XCTAssertEqual(
            scheduledEvidence.delayMilliseconds,
            2_400
        )
        XCTAssertEqual(
            scheduledEvidence.identity.bundleIdentifier,
            identity.bundleIdentifier
        )
        XCTAssertTrue(
            NSRunningApplication.runningApplications(
                withBundleIdentifier:
                    identity.bundleIdentifier
            ).contains {
                !$0.isTerminated
                    && $0.processIdentifier
                        == scheduledEvidence
                            .identity
                            .processIdentifier
            },
            "Scheduled termination evidence did not identify the running fixture process."
        )
        XCTAssertNotEqual(fixtureApp.state, .notRunning)
        XCTAssertTrue(
            fixtureAppTile.exists,
            "The selected fixture app should remain in the panel while its process is still terminating."
        )

        let appliedEvidence = try XCTUnwrap(
            terminationObservation.waitForApplied(
                requestGeneration:
                    scheduledEvidence.requestGeneration,
                timeout: 8
            ),
            "Fixture did not publish applied termination evidence: "
                + terminationObservation.diagnosticSummary
        )
        XCTAssertEqual(
            appliedEvidence.identity,
            scheduledEvidence.identity
        )
        XCTAssertEqual(
            appliedEvidence.source,
            scheduledEvidence.source
        )
        let terminationWaitCompleted = fixtureApp.wait(
            for: .notRunning,
            timeout: 8
        )
        let finalFixtureState = fixtureApp.state
        XCTAssertTrue(
            terminationWaitCompleted
                && finalFixtureState == .notRunning,
            "Fixture process termination evidence was not satisfied. "
                + "waiterCompleted=\(terminationWaitCompleted) "
                + "finalState=\(String(describing: finalFixtureState))"
        )
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

        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: nil,
            targetDescription: "runtime-lifecycle-before-fixture-launch"
        )

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
                terminateSpaceFixtureApplicationAndWait(fixtureApp, identity: identity)
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
        terminateSpaceFixtureApplicationAndWait(
            fixtureApp,
            identity: identity,
            timeout: 8
        )
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

        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: nil,
            targetDescription: "window-set-mutation-before-observer"
        )

        let windowCloseRoute =
            makeSpaceFixtureWindowCloseFaultRoute()
        let windowCloseObservation =
            SpaceFixtureWindowCloseFaultObservationOwner(
                route: windowCloseRoute
            )
        windowCloseObservation.start()
        defer { windowCloseObservation.cancel() }

        let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 2,
            fullscreenWindowIndex: nil,
            titlePrefix: "Mutation",
            enterFullscreenDelayMilliseconds: 0,
            closeWindowIndex: 2,
            closeWindowDelayMilliseconds: 250,
            fixtureAdditionalArguments:
                windowCloseRoute.fixtureLaunchArguments
        )
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                terminateSpaceFixtureApplicationAndWait(fixtureApp, identity: identity)
            }
        }
        guard let scheduledClose =
                windowCloseObservation.waitForScheduled(
                    timeout: 8
                )
        else {
            XCTFail(
                "Missing scheduled fixture window-close evidence: "
                    + windowCloseObservation
                        .diagnosticSummary
            )
            return
        }
        XCTAssertEqual(
            scheduledClose.snapshot
                .targetWindowPlanIndex,
            2
        )
        XCTAssertEqual(
            scheduledClose.delayMilliseconds,
            250
        )
        XCTAssertTrue(
            scheduledClose.awaitsExplicitTrigger
        )
        XCTAssertEqual(
            scheduledClose.identity.bundleIdentifier,
            identity.bundleIdentifier
        )
        XCTAssertTrue(
            NSRunningApplication.runningApplications(
                withBundleIdentifier:
                    identity.bundleIdentifier
            ).contains {
                !$0.isTerminated
                    && $0.processIdentifier
                        == scheduledClose.identity
                            .processIdentifier
            }
        )
        XCTAssertTrue(
            scheduledClose.snapshot
                .targetWindowIsVisible
        )
        XCTAssertEqual(
            scheduledClose.snapshot
                .remainingWindowPlanIndices,
            [1, 2]
        )

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let fixtureAppRow = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity, timeout: 12)
        assertValue(of: fixtureAppRow, equals: "2w", timeout: 12)

        windowCloseObservation.requestClose(
            from: scheduledClose
        )
        guard let appliedClose =
                windowCloseObservation.waitForApplied(
                    requestGeneration:
                        scheduledClose.requestGeneration,
                    timeout: 15
                )
        else {
            XCTFail(
                "Missing applied fixture window-close evidence: "
                    + windowCloseObservation
                        .diagnosticSummary
            )
            return
        }
        XCTAssertEqual(
            appliedClose.identity,
            scheduledClose.identity
        )
        XCTAssertEqual(
            appliedClose.snapshot
                .targetWindowPlanIndex,
            2
        )
        XCTAssertEqual(
            appliedClose.snapshot
                .targetWindowNumber,
            scheduledClose.snapshot
                .targetWindowNumber
        )
        XCTAssertFalse(
            appliedClose.snapshot
                .targetWindowIsVisible
        )
        XCTAssertFalse(
            appliedClose.snapshot
                .targetCGWindowIsOnScreen
        )
        XCTAssertEqual(
            appliedClose.snapshot
                .remainingWindowPlanIndices,
            [1]
        )
        XCTAssertTrue(
            fixtureApp.windows[
                "flowtab.spacefixture.window.1"
            ].exists
        )
        XCTAssertTrue(
            waitForNonExistence(
                fixtureApp.windows[
                    "flowtab.spacefixture.window.2"
                ],
                timeout: 5
            ),
            windowCloseObservation.diagnosticSummary
        )
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

            assertSwitcherWindowCycle(in: app, timeout: 5) {
                app.typeKey(.downArrow, modifierFlags: [])
            }

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
                terminateSpaceFixtureApplicationAndWait(fixtureApp, identity: identity)
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
        assertSwitcherWindowCycle(in: app, timeout: 5) {
            app.typeKey(.downArrow, modifierFlags: [])
        }
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
                terminateSpaceFixtureApplicationAndWait(fixtureApp, identity: identity)
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
        assertSwitcherWindowCycle(in: app, timeout: 5) {
            app.typeKey(.downArrow, modifierFlags: [])
        }
        _ = waitForSwitcherWindowCards(in: app, expectedTitles: allTitles, timeout: 8)

        _ = waitForSwitcherWindowCards(
            in: app,
            expectedTitles: [allTitles[1]],
            timeout: 25
        )
        assertSwitcherWindowCycle(in: app, timeout: 5)
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
            try FlowTabUITestSwitcherCommandPayload.write(appID)
        } catch {
            XCTFail("Failed to select switcher app \(appID): \(error)")
            return
        }

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "selected",
                equals: appID,
                timeout: timeout
            ) {
                postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                    .selectApp,
                    traceLabel: traceLabel,
                    timeout: timeout
                )
            }
        )
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
                terminateSpaceFixtureApplicationAndWait(fixtureApp, identity: identity)
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

        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: nil,
            targetDescription: "standard-workflow-post-fixture-launch"
        )
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
