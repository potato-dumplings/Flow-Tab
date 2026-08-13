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
            _ = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity, expectedValue: "3w")
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
            XCTAssertTrue(assertCurrentSwitcherAppProjection(
                in: app,
                exactEntry: "\(identity.bundleIdentifier):3",
                timeout: FlowTabUITestSwitcherAppProjectionPolicy.standardFixtureProjectionWatchdog
            ))
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

        guard assertCurrentSwitcherAppProjection(
            in: app,
            exactEntry: "\(identity.bundleIdentifier):1",
            timeout:
                FlowTabUITestSwitcherAppProjectionPolicy
                    .quitShortcutInitialProjectionWatchdog
        ) else { return }
        let fixtureAppTile = element(
            in: app,
            identifier: identity.switcherAppAccessibilityIdentifier
        )
        selectSwitcherAppDirectly(
            in: app,
            appID: identity.bundleIdentifier,
            traceLabel: "quitFixture.selectApp"
        )
        guard let removalObservation =
                startSwitcherAppRemovalObservation(
                    in: app,
                    bundleIdentifier: identity.bundleIdentifier,
                    expectedInitialWindowCount: 1
                )
        else { return }
        defer { removalObservation.cancel() }

        let logSnapshot = makeRuntimeLogFileSnapshot()
        defer { logSnapshot.cancel() }
        let postTerminationRefreshObservation =
            SpaceFixturePostTerminationRefreshObservationOwner(
                bundleIdentifier: identity.bundleIdentifier,
                baseline: logSnapshot
            )
        postTerminationRefreshObservation.start()
        defer { postTerminationRefreshObservation.cancel() }
        let terminationRequestPattern =
            FlowTabUITestRuntimeLogRecordPattern
                .exactTerminationRequest(
                    bundleIdentifier:
                        identity.bundleIdentifier
                )
        let terminationRequestExpression =
            try NSRegularExpression(
                pattern: terminationRequestPattern
            )
        var acceptsTerminationRequest = false
        let terminationRequestObservation =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation:
                    .regularExpression(
                        terminationRequestExpression,
                        pattern: terminationRequestPattern,
                        description:
                            "exact quit-shortcut termination request"
                    ),
                observationRegistration:
                    logSnapshot.observationRegistration(),
                acceptsResolution: {
                    acceptsTerminationRequest
                },
                readback: logSnapshot.makeReadback
            )
        terminationRequestObservation.start()
        defer { terminationRequestObservation.cancel() }
        app.activate()
        app.typeKey("q", modifierFlags: .option)
        acceptsTerminationRequest = true
        terminationRequestObservation.requestReadback(
            source: .triggerReadback
        )
        removalObservation.markTriggerCompleted()

        guard
            terminationRequestObservation.waitForResolution(
                timeout:
                    FlowTabUITestRuntimeLogObservationPolicy
                        .quitShortcutTerminationRequestWatchdog
            ) != nil
        else {
            XCTFail(
                "Quit-shortcut termination-request watchdog "
                    + "expired. "
                    + terminationRequestObservation
                        .diagnosticSummary
            )
            return
        }
        let scheduledEvidence = try XCTUnwrap(
            terminationObservation.waitForScheduled(
                timeout:
                    SpaceFixtureTerminationFaultObservationPolicy
                        .scheduledEvidenceWatchdog
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
        postTerminationRefreshObservation.bindTarget(
            processIdentifier:
                scheduledEvidence.identity.processIdentifier,
            requestGeneration: scheduledEvidence.requestGeneration
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
                timeout:
                    SpaceFixtureTerminationFaultObservationPolicy
                        .appliedEvidenceWatchdog
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
            timeout:
                FlowTabUITestApplicationTerminationPolicy
                    .quitShortcutFixtureWatchdog
        )
        let finalFixtureState = fixtureApp.state
        XCTAssertEqual(
            finalFixtureState,
            .notRunning,
            "Fixture process termination evidence was not satisfied. "
                + "waiterCompleted=\(terminationWaitCompleted) "
                + "finalState=\(String(describing: finalFixtureState))"
        )
        let refreshEvidence = try XCTUnwrap(
            postTerminationRefreshObservation.waitForResolution(
                timeout:
                    SpaceFixturePostTerminationRefreshObservationPolicy
                        .evidenceWatchdog
            ),
            "Post-termination projection refresh watchdog expired. "
                + postTerminationRefreshObservation.diagnosticSummary
        )
        XCTAssertEqual(
            refreshEvidence.value.reason,
            "workspace_notification"
        )
        XCTAssertEqual(
            refreshEvidence.value.bundleIdentifier,
            identity.bundleIdentifier
        )
        XCTAssertEqual(
            refreshEvidence.value.processIdentifier,
            scheduledEvidence.identity.processIdentifier
        )
        XCTAssertEqual(
            refreshEvidence.value.pendingGeneration,
            scheduledEvidence.requestGeneration
        )
        XCTAssertTrue(refreshEvidence.value.matchedPending)
        XCTAssertTrue(refreshEvidence.value.refreshed)
        assertSwitcherAppRemoved(
            removalObservation,
            timeout:
                FlowTabUITestSwitcherAppProjectionPolicy
                    .quitShortcutRemovalWatchdog,
            description: "Quit-shortcut fixture App projection removal"
        )
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
        let escapedLifecycleAppID =
            NSRegularExpression.escapedPattern(
                for: identity.bundleIdentifier
            )
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
            matching:
                #"runtimeLifecycle appLaunched appID=\#(escapedLifecycleAppID) "#
                + #"pid=[1-9][0-9]* maintenanceGeneration=[1-9][0-9]*"#,
            since: launchLogSnapshot,
            description: "exact workspace lifecycle launch evidence"
        )

        app.activate()
        assertRealSpaceFixtureFlowTabIsForegroundReadyAfterFixtureLaunch(
            app,
            targetDescription: "runtime-lifecycle-after-fixture-launch"
        )
        _ = openHomeTabAndSelectSpaceFixtureApp(
            in: app,
            identity: identity,
            expectedValue: "1w",
            timeout:
                FlowTabUITestSpaceFixtureHomeProjectionPolicy
                    .runtimeLifecycleAppSummaryWatchdog
        )

        let runningFixtureProcesses =
            NSRunningApplication.runningApplications(
                withBundleIdentifier: identity.bundleIdentifier
            ).filter { !$0.isTerminated }
        let fixturePID = try XCTUnwrap(
            runningFixtureProcesses.count == 1
                ? runningFixtureProcesses.first?.processIdentifier
                : nil,
            "Expected one active lifecycle fixture process before termination. "
                + "observedPIDs=\(runningFixtureProcesses.map(\.processIdentifier))"
        )
        let terminationLogSnapshot = makeRuntimeLogFileSnapshot()
        terminateSpaceFixtureApplicationAndWait(
            fixtureApp,
            identity: identity,
            timeout:
                FlowTabUITestApplicationTerminationPolicy
                    .runtimeLifecycleFixtureWatchdog
        )
        waitForRuntimeLogFiles(
            matching:
                #"runtimeLifecycle appTerminated appID=\#(escapedLifecycleAppID) "#
                + #"pid=\#(fixturePID) maintenanceGeneration=[1-9][0-9]*"#,
            since: terminationLogSnapshot,
            description: "exact workspace lifecycle termination evidence"
        )
    }

    func testRuntimeLifecycleRefreshesRealFixtureWindowSetMutation() throws {
        let identity = spaceFixtureAppIdentity

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let currentAppProjectionAcceptanceRoute =
            makeSpaceFixtureCurrentAppProjectionAcceptanceRoute(bundleIdentifier: identity.bundleIdentifier)
        currentAppProjectionAcceptanceRoute.removeReadback()
        defer { currentAppProjectionAcceptanceRoute.removeReadback() }
        let app = makeRealRuntimeFlowTabApp(
            additionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs"
            ] + currentAppProjectionAcceptanceRoute.flowTabLaunchArguments
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
                    timeout:
                        SpaceFixtureWindowCloseFaultObservationPolicy
                            .scheduledEvidenceWatchdog
                )
        else {
            XCTFail(
                "Missing scheduled fixture window-close evidence: "
                    + windowCloseObservation
                        .diagnosticSummary
            )
            return
        }
        let fixturePID = scheduledClose.identity.processIdentifier
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
                    && $0.processIdentifier == fixturePID
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
        assertRealSpaceFixtureFlowTabIsForegroundReadyAfterFixtureLaunch(
            app, targetDescription: "window-set-mutation-after-fixture-launch"
        )
        let fixtureAppRow = openHomeTabAndSelectSpaceFixtureApp(
            in: app,
            identity: identity,
            expectedValue: "2w",
            timeout:
                FlowTabUITestSpaceFixtureHomeProjectionPolicy
                    .runtimeWindowMutationInitialSummaryWatchdog
        )

        let currentAppProjectionAcceptance =
            SpaceFixtureCurrentAppProjectionAcceptanceOwner(
                route: currentAppProjectionAcceptanceRoute,
                expectedPID: fixturePID
            )
        currentAppProjectionAcceptance.start()
        defer { currentAppProjectionAcceptance.cancel() }
        guard assertSpaceFixtureCurrentAppProjectionBaseline(
            from: currentAppProjectionAcceptance,
            identity: identity,
            expectedPID: fixturePID
        ) else { return }
        guard currentAppProjectionAcceptance.startTargetObservation()
        else {
            XCTFail(
                "Failed to establish post-close projection observer: "
                    + currentAppProjectionAcceptance
                        .diagnosticSummary
            )
            return
        }

        let postCloseHomeProjection =
            makeSpaceFixtureHomeTransitionObservation(
                in: app,
                rowIdentifier: fixtureAppRow.identifier,
                expectedValue: "1w"
            )
        postCloseHomeProjection.start()
        defer { postCloseHomeProjection.cancel() }

        let closedFixtureWindow = fixtureApp.windows[
            "flowtab.spacefixture.window.2"
        ]
        assertElementDoesNotExistAfterTrigger(
            closedFixtureWindow,
            timeout:
                SpaceFixtureWindowCloseFaultObservationPolicy
                    .closedWindowDisappearanceWatchdog,
            description:
                "Exact Space fixture Window 2 disappearance"
        ) {
            windowCloseObservation.requestClose(
                from: scheduledClose
            )
            postCloseHomeProjection.markTriggerCompleted()
        }
        guard let appliedClose =
                windowCloseObservation.waitForApplied(
                    requestGeneration:
                        scheduledClose.requestGeneration,
                    timeout:
                        SpaceFixtureWindowCloseFaultObservationPolicy
                            .appliedEvidenceWatchdog
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
        guard postCloseHomeProjection.waitForResolution(
            timeout:
                FlowTabUITestSpaceFixtureHomeProjectionPolicy
                    .runtimeWindowMutationFinalSummaryWatchdog
        ) != nil else {
            XCTFail(
                "Space Fixture post-close Home projection watchdog expired. "
                    + postCloseHomeProjection.diagnosticSummary
            )
            return
        }
        guard assertSpaceFixtureCurrentAppProjectionAccepted(
            by: currentAppProjectionAcceptance,
            identity: identity,
            expectedPID: fixturePID
        ) else { return }
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
            guard assertCurrentSwitcherAppProjection(
                in: app,
                exactEntry: "\(identity.bundleIdentifier):3",
                timeout: FlowTabUITestSwitcherAppProjectionPolicy.standardFixtureProjectionWatchdog
            ) else { return }
            selectSwitcherAppDirectly(
                in: app,
                appID: identity.bundleIdentifier,
                traceLabel: "workflowWindowCards.selectApp"
            )

            XCTAssertTrue(
                enterSwitcherWindowCycle(
                    expectedBundleIdentifier: identity.bundleIdentifier,
                    in: app,
                    timeout: FlowTabUITestSwitcherPreviewTransitionPolicy.standardFixtureEntryWatchdog
                )
            )

            assertSpaceFixtureSwitcherWindowCards(
                expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Workflow", windowCount: 3),
                in: app
            )
        }
    }

    func selectSwitcherAppDirectly(
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
