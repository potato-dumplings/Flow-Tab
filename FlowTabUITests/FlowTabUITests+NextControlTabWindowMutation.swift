import AppKit
import Carbon
import XCTest

extension FlowTabUITests {
    func testNextControlTabSessionUsesWindowCreatedWhilePanelIsClosed()
        throws
    {
        let identity = spaceFixtureAppIdentity
        guard assertSpaceFixtureWorkflowPermissionsAvailable() else {
            return
        }

        let route = makeSpaceFixtureWindowOpenMutationRoute()
        let mutation =
            SpaceFixtureWindowOpenMutationObservationOwner(
                route: route
            )
        mutation.start()
        defer { mutation.cancel() }

        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 2,
            fullscreenWindowIndex: nil,
            titlePrefix: "Created While Closed",
            enterFullscreenDelayMilliseconds: 0,
            deferredOpenWindowIndex: 2,
            fixtureAdditionalArguments:
                route.fixtureLaunchArguments
        )
        defer {
            if fixtureApp.state == .runningForeground
                || fixtureApp.state == .runningBackground
            {
                terminateSpaceFixtureApplicationAndWait(
                    fixtureApp,
                    identity: identity
                )
            }
        }

        let readyEvidence = try XCTUnwrap(
            mutation.waitForReady(
                timeout:
                    SpaceFixtureWindowOpenMutationUITestPolicy
                        .readyEvidenceWatchdog
            ),
            "Missing deferred window-open ready evidence. "
                + mutation.diagnosticSummary
        )
        XCTAssertEqual(
            readyEvidence.bundleIdentifier,
            identity.bundleIdentifier
        )
        XCTAssertEqual(readyEvidence.targetWindowPlanIndex, 2)
        XCTAssertEqual(
            readyEvidence.targetWindowTitle,
            "Created While Closed 2"
        )
        XCTAssertEqual(readyEvidence.activeWindowPlanIndices, [1])

        let app = launchWindowMutationFlowTab(
            identity: identity,
            initialWindowCount: 1,
            fixtureApp: fixtureApp,
            traceLabel: "window-created"
        )
        defer {
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }

        let openedFixtureWindow = fixtureApp.windows[
            "flowtab.spacefixture.window.2"
        ]
        XCTAssertFalse(openedFixtureWindow.exists)
        let openedFixtureWindowObservation =
            startElementExistenceObservation(
                in: fixtureApp,
                identifier: "flowtab.spacefixture.window.2",
                requiresInitialAbsence: true
            )
        defer { openedFixtureWindowObservation.cancel() }
        mutation.requestOpen(from: readyEvidence)
        assertElementExistsAfterTrigger(
            openedFixtureWindowObservation,
            timeout:
                SpaceFixtureWindowOpenMutationUITestPolicy
                    .fixtureWindowReadbackWatchdog,
            description:
                "Deferred fixture Window 2 creation"
        )
        let appliedEvidence = try XCTUnwrap(
            mutation.waitForApplied(
                requestGeneration:
                    readyEvidence.requestGeneration,
                timeout:
                    SpaceFixtureWindowOpenMutationUITestPolicy
                        .appliedEvidenceWatchdog
            ),
            "Missing deferred window-open applied evidence. "
                + mutation.diagnosticSummary
        )
        XCTAssertEqual(
            appliedEvidence.activeWindowPlanIndices,
            [1, 2]
        )

        assertNextPhysicalControlTabSession(
            in: app,
            fixtureApp: fixtureApp,
            identity: identity,
            expectedTitles: [
                "Created While Closed 1",
                "Created While Closed 2"
            ],
            traceLabel: "window-created"
        )
    }

    func testNextControlTabSessionUsesWindowClosedWhilePanelIsClosed()
        throws
    {
        let identity = spaceFixtureAppIdentity
        guard assertSpaceFixtureWorkflowPermissionsAvailable() else {
            return
        }

        let route = makeSpaceFixtureWindowCloseFaultRoute()
        let mutation = SpaceFixtureWindowCloseFaultObservationOwner(
            route: route
        )
        mutation.start()
        defer { mutation.cancel() }

        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 2,
            fullscreenWindowIndex: nil,
            titlePrefix: "Closed While Hidden",
            enterFullscreenDelayMilliseconds: 0,
            closeWindowIndex: 2,
            closeWindowDelayMilliseconds: 0,
            fixtureAdditionalArguments:
                route.fixtureLaunchArguments
        )
        defer {
            if fixtureApp.state == .runningForeground
                || fixtureApp.state == .runningBackground
            {
                terminateSpaceFixtureApplicationAndWait(
                    fixtureApp,
                    identity: identity
                )
            }
        }

        let scheduledClose = try XCTUnwrap(
            mutation.waitForScheduled(
                timeout:
                    SpaceFixtureWindowCloseFaultObservationPolicy
                        .scheduledEvidenceWatchdog
            ),
            "Missing scheduled window-close evidence. "
                + mutation.diagnosticSummary
        )
        XCTAssertEqual(
            scheduledClose.identity.bundleIdentifier,
            identity.bundleIdentifier
        )
        XCTAssertEqual(
            scheduledClose.snapshot.remainingWindowPlanIndices,
            [1, 2]
        )

        let app = launchWindowMutationFlowTab(
            identity: identity,
            initialWindowCount: 2,
            fixtureApp: fixtureApp,
            traceLabel: "window-closed"
        )
        defer {
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }

        let closedFixtureWindow = fixtureApp.windows[
            "flowtab.spacefixture.window.2"
        ]
        XCTAssertTrue(closedFixtureWindow.exists)
        assertElementDoesNotExistAfterTrigger(
            closedFixtureWindow,
            timeout:
                SpaceFixtureWindowCloseFaultObservationPolicy
                    .closedWindowDisappearanceWatchdog,
            description:
                "Exact fixture Window 2 disappearance"
        ) {
            mutation.requestClose(from: scheduledClose)
        }
        let appliedClose = try XCTUnwrap(
            mutation.waitForApplied(
                requestGeneration:
                    scheduledClose.requestGeneration,
                timeout:
                    SpaceFixtureWindowCloseFaultObservationPolicy
                        .appliedEvidenceWatchdog
            ),
            "Missing applied window-close evidence. "
                + mutation.diagnosticSummary
        )
        XCTAssertEqual(
            appliedClose.snapshot.remainingWindowPlanIndices,
            [1]
        )
        XCTAssertFalse(appliedClose.snapshot.targetWindowIsVisible)
        XCTAssertFalse(appliedClose.snapshot.targetCGWindowIsOnScreen)

        assertNextPhysicalControlTabSession(
            in: app,
            fixtureApp: fixtureApp,
            identity: identity,
            expectedTitles: ["Closed While Hidden 1"],
            traceLabel: "window-closed"
        )
    }

    private func launchWindowMutationFlowTab(
        identity: SpaceFixtureAppIdentity,
        initialWindowCount: Int,
        fixtureApp: XCUIApplication,
        traceLabel: String
    ) -> XCUIApplication {
        let app = makeRealRuntimeFlowTabApp(
            additionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-frontmost-bundle-id",
                identity.bundleIdentifier,
                "--flowtab-ui-enable-shortcut-event-injection",
                "--flowtab-ui-runtime-log-level", "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments
        )
        launchFlowTabUITestApplication(app)
        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: traceLabel,
            targetDescription:
                "next-Control-Tab-\(traceLabel)-initial-projection"
        )
        _ = assertCurrentSwitcherAppProjection(
            in: app,
            exactEntry:
                "\(identity.bundleIdentifier):\(initialWindowCount)",
            timeout:
                FlowTabUITestSwitcherAppProjectionPolicy
                    .openWindowMutationInitialProjectionWatchdog
        )

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        app.activate()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForNonExistence(
                diagnosticsSummary,
                timeout:
                    SpaceFixtureWindowOpenMutationUITestPolicy
                        .panelDismissalWatchdog
            ),
            "Initial Switcher session did not close before \(traceLabel) mutation."
        )
        fixtureApp.activate()
        XCTAssertTrue(
            fixtureApp.wait(
                for: .runningForeground,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .spaceFixtureForegroundActivation
            ),
            "Fixture did not become foreground before \(traceLabel) mutation."
        )
        return app
    }

    private func assertNextPhysicalControlTabSession(
        in app: XCUIApplication,
        fixtureApp: XCUIApplication,
        identity: SpaceFixtureAppIdentity,
        expectedTitles: [String],
        traceLabel: String
    ) {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let panelProjection =
            FlowTabUITestInAppSwitcherPanelProjectionObservationOwner(
                expectation:
                    FlowTabUITestInAppSwitcherPanelProjectionExpectation(
                        bundleIdentifier:
                            identity.bundleIdentifier,
                        windowCount: expectedTitles.count,
                        expectedTitles: expectedTitles
                    ),
                readback: {
                    let stateBefore = app.state
                    let diagnostics = self.switcherDiagnosticsSnapshot(
                        diagnosticsSummary,
                        keys: ["apps", "selected", "mode", "preview"]
                    )
                    return FlowTabUITestInAppSwitcherPanelProjectionSnapshot(
                        applicationStateBefore: stateBefore,
                        diagnostics: diagnostics,
                        applicationStateAfter: app.state
                    )
                }
            )
        guard panelProjection.start() else {
            XCTFail(
                "Control+Tab panel absence baseline failed for \(traceLabel). "
                    + panelProjection.diagnosticSummary
            )
            panelProjection.cancel()
            return
        }
        defer { panelProjection.cancel() }

        let windowCards = makeSwitcherWindowTitleObservation(
            in: app,
            expectedTitles: expectedTitles
        )
        windowCards.start()
        defer { windowCards.cancel() }

        var projectionEvidence:
            FlowTabUITestConditionEvidence<
                FlowTabUITestInAppSwitcherPanelProjectionSnapshot
            >?
        var cardEvidence:
            FlowTabUITestConditionEvidence<
                FlowTabUITestSwitcherWindowTitleSnapshot
            >?
        guard let flowTabProcessID = runningFlowTabProcessIdentifier(
            applicationState: app.state,
            traceLabel: traceLabel
        ) else {
            return
        }
        panelProjection.markTriggerCompleted()
        injectRuntimeKeySet(
            targetProcessID: flowTabProcessID,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: .control,
            phase: "press"
        )
        defer {
            injectRuntimeKeySet(
                targetProcessID: flowTabProcessID,
                keyCodes: [CGKeyCode(kVK_Tab)],
                modifierFlags: .control,
                phase: "release"
            )
        }
        projectionEvidence = panelProjection.waitForResolution(
            timeout:
                SpaceFixtureWindowOpenMutationUITestPolicy
                    .switcherProjectionWatchdog
        )
        if projectionEvidence != nil {
            cardEvidence = windowCards.waitForResolution(
                timeout:
                    SpaceFixtureWindowOpenMutationUITestPolicy
                        .switcherProjectionWatchdog
            )
        }

        XCTAssertNotNil(
            projectionEvidence,
            "Next physical Control+Tab projection failed for \(traceLabel). "
                + panelProjection.diagnosticSummary
        )
        let cards = cardEvidence?.value
        XCTAssertEqual(cards?.cardCount, expectedTitles.count)
        XCTAssertEqual(
            cards?.titleCounts,
            Dictionary(
                uniqueKeysWithValues:
                    expectedTitles.map { ($0, 1) }
            )
        )
    }

    private func runningFlowTabProcessIdentifier(
        applicationState: XCUIApplication.State,
        traceLabel: String
    ) -> pid_t? {
        let identity = FlowTabUITestAppIdentity.configured()
        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: identity.bundleIdentifier
        ).filter { !$0.isTerminated }
        let matchingApplications: [NSRunningApplication]
        if let appURL = identity.appURL?.standardizedFileURL {
            matchingApplications = runningApplications.filter {
                $0.bundleURL?.standardizedFileURL == appURL
            }
        } else {
            matchingApplications = runningApplications
        }
        guard matchingApplications.count == 1,
              let processID = matchingApplications.first?.processIdentifier
        else {
            XCTFail(
                "Expected one fixed-path FlowTab process before \(traceLabel) "
                    + "Control+Tab injection; applicationState="
                    + "\(String(describing: applicationState)) "
                    + "matchingProcesses=\(matchingApplications.count)."
            )
            return nil
        }
        return processID
    }
}
