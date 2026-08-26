import AppKit
import Carbon
import XCTest

private enum FlowTabUITestWindowMutationPriorSession {
    case none
    case completedOptionTab

    var traceComponent: String {
        switch self {
        case .none:
            "first-session"
        case .completedOptionTab:
            "after-option-tab"
        }
    }
}

extension FlowTabUITests {
    func testFirstSwitcherSessionControlTabUsesWindowCreatedWhilePanelIsClosed()
        throws
    {
        try runWindowCreatedMutation(
            priorSession: .none
        )
    }

    func testFirstSwitcherSessionControlTabUsesWindowClosedWhilePanelIsClosed()
        throws
    {
        try runWindowClosedMutation(
            priorSession: .none
        )
    }

    func testControlTabUsesWindowCreatedAfterCompletedOptionTabSession()
        throws
    {
        try runWindowCreatedMutation(
            priorSession: .completedOptionTab
        )
    }

    func testControlTabUsesWindowClosedAfterCompletedOptionTabSession()
        throws
    {
        try runWindowClosedMutation(
            priorSession: .completedOptionTab
        )
    }

    private func runWindowCreatedMutation(
        priorSession: FlowTabUITestWindowMutationPriorSession
    ) throws {
        let identity = spaceFixtureAppIdentity
        let traceLabel =
            "window-created.\(priorSession.traceComponent)"
        let projectionRoute =
            makeSpaceFixtureCurrentAppProjectionAcceptanceRoute(
                bundleIdentifier: identity.bundleIdentifier
            )
        defer { projectionRoute.removeReadback() }
        let app = launchWindowMutationFlowTab(
            traceLabel: traceLabel,
            projectionRoute: projectionRoute
        )
        defer {
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }
        guard assertSpaceFixtureWorkflowPermissionsAvailable(in: app)
        else {
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
            windowCount: 3,
            fullscreenWindowIndex: nil,
            titlePrefix: "Created While Closed",
            enterFullscreenDelayMilliseconds: 0,
            deferredOpenWindowIndex: 3,
            fixtureAdditionalArguments:
                route.fixtureLaunchArguments
                + ["--chrome-like-window-mutation-noise"]
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
        XCTAssertEqual(readyEvidence.targetWindowPlanIndex, 3)
        XCTAssertEqual(
            readyEvidence.targetWindowTitle,
            "Created While Closed 3"
        )
        XCTAssertEqual(readyEvidence.activeWindowPlanIndices, [1, 2])
        XCTAssertEqual(
            readyEvidence.activeWindowTitlesByPlanIndex,
            [
                1: "Created While Closed 1",
                2: "Created While Closed 2"
            ]
        )
        XCTAssertEqual(
            readyEvidence.activeCGWindowIDsByPlanIndex.count,
            2
        )
        let projectionAcceptance =
            SpaceFixtureCurrentAppProjectionAcceptanceOwner(
                route: projectionRoute,
                expectedPID:
                    readyEvidence.processIdentifier,
                expectation: .createdTwoToThree
            )
        projectionAcceptance.start()
        defer { projectionAcceptance.cancel() }
        guard prepareWindowMutationFixture(
            in: app,
            fixtureApp: fixtureApp,
            identity: identity,
            initialWindowCount: 2,
            priorSession: priorSession,
            traceLabel: traceLabel,
            projectionAcceptance: projectionAcceptance,
            expectedPID:
                readyEvidence.processIdentifier
        ) else { return }
        guard projectionAcceptance.startTargetObservation() else {
            return XCTFail(
                "Could not arm created-window projection target for \(traceLabel)."
            )
        }

        let openedFixtureWindow = fixtureApp.windows[
            "flowtab.spacefixture.window.3"
        ]
        XCTAssertFalse(openedFixtureWindow.exists)
        let openedFixtureWindowObservation =
            startElementExistenceObservation(
                in: fixtureApp,
                identifier: "flowtab.spacefixture.window.3",
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
                "Deferred fixture Window 3 creation"
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
            [1, 2, 3]
        )
        XCTAssertEqual(
            appliedEvidence.activeWindowTitlesByPlanIndex,
            [
                1: "Created While Closed 1",
                2: "Created While Closed 2",
                3: "Created While Closed 3"
            ]
        )
        XCTAssertEqual(
            appliedEvidence.activeCGWindowIDsByPlanIndex.count,
            3
        )

        assertPhysicalControlTabSession(
            in: app,
            identity: identity,
            expectedTitles: [
                "Created While Closed 1",
                "Created While Closed 2",
                "Created While Closed 3"
            ],
            traceLabel: traceLabel,
            projectionAcceptance: projectionAcceptance,
            expectedPID:
                readyEvidence.processIdentifier
        )
    }

    private func runWindowClosedMutation(
        priorSession: FlowTabUITestWindowMutationPriorSession
    ) throws {
        let identity = spaceFixtureAppIdentity
        let traceLabel =
            "window-closed.\(priorSession.traceComponent)"
        let projectionRoute =
            makeSpaceFixtureCurrentAppProjectionAcceptanceRoute(
                bundleIdentifier: identity.bundleIdentifier
            )
        defer { projectionRoute.removeReadback() }
        let app = launchWindowMutationFlowTab(
            traceLabel: traceLabel,
            projectionRoute: projectionRoute
        )
        defer {
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }
        guard assertSpaceFixtureWorkflowPermissionsAvailable(in: app)
        else {
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
            windowCount: 3,
            fullscreenWindowIndex: nil,
            titlePrefix: "Closed While Hidden",
            enterFullscreenDelayMilliseconds: 0,
            closeWindowIndex: 2,
            closeWindowDelayMilliseconds: 0,
            fixtureAdditionalArguments:
                route.fixtureLaunchArguments
                + ["--chrome-like-window-mutation-noise"]
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
            [1, 2, 3]
        )
        XCTAssertEqual(
            scheduledClose.snapshot.remainingWindowTitlesByPlanIndex,
            [
                1: "Closed While Hidden 1",
                2: "Closed While Hidden 2",
                3: "Closed While Hidden 3"
            ]
        )
        XCTAssertEqual(
            scheduledClose.snapshot.remainingCGWindowIDsByPlanIndex.count,
            3
        )
        let projectionAcceptance =
            SpaceFixtureCurrentAppProjectionAcceptanceOwner(
                route: projectionRoute,
                expectedPID:
                    scheduledClose.identity.processIdentifier,
                expectation: .closedThreeToTwo
            )
        projectionAcceptance.start()
        defer { projectionAcceptance.cancel() }
        guard prepareWindowMutationFixture(
            in: app,
            fixtureApp: fixtureApp,
            identity: identity,
            initialWindowCount: 3,
            priorSession: priorSession,
            traceLabel: traceLabel,
            projectionAcceptance: projectionAcceptance,
            expectedPID:
                scheduledClose.identity.processIdentifier
        ) else { return }
        guard projectionAcceptance.startTargetObservation() else {
            return XCTFail(
                "Could not arm closed-window projection target for \(traceLabel)."
            )
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
            [1, 3]
        )
        XCTAssertFalse(appliedClose.snapshot.targetWindowIsVisible)
        XCTAssertFalse(appliedClose.snapshot.targetCGWindowIsOnScreen)
        XCTAssertEqual(
            appliedClose.snapshot.remainingWindowTitlesByPlanIndex,
            [
                1: "Closed While Hidden 1",
                3: "Closed While Hidden 3"
            ]
        )
        let retiredCGWindowID =
            scheduledClose.snapshot.targetWindowNumber
        XCTAssertFalse(
            appliedClose.snapshot.remainingCGWindowIDsByPlanIndex
                .values.contains(retiredCGWindowID)
        )
        XCTAssertNotEqual(
            scheduledClose.snapshot.remainingCGWindowIDsByPlanIndex[3],
            appliedClose.snapshot.remainingCGWindowIDsByPlanIndex[3]
        )

        assertPhysicalControlTabSession(
            in: app,
            identity: identity,
            expectedTitles: [
                "Closed While Hidden 1",
                "Closed While Hidden 3"
            ],
            traceLabel: traceLabel,
            projectionAcceptance: projectionAcceptance,
            expectedPID:
                scheduledClose.identity.processIdentifier,
            retiredTitle: "Closed While Hidden 2",
            retiredCGWindowID: retiredCGWindowID
        )
    }

    private func launchWindowMutationFlowTab(
        traceLabel: String,
        projectionRoute:
            SpaceFixtureCurrentAppProjectionAcceptanceRoute
    ) -> XCUIApplication {
        let app = makeRealRuntimeFlowTabApp(
            additionalArguments:
                runtimeTruthSwitcherLaunchArguments(
                    additionalArguments: [
                        "--flowtab-ui-enable-shortcut-event-injection"
                    ] + projectionRoute.flowTabLaunchArguments,
                    suppressesPanelActivation: false
                )
        )
        launchFlowTabUITestApplication(app)
        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: traceLabel,
            targetDescription:
                "Control-Tab-\(traceLabel)-before-fixture-launch"
        )

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertFalse(
            diagnosticsSummary.exists,
            "FlowTab must start with no Switcher session before \(traceLabel)."
        )
        return app
    }

    private func prepareWindowMutationFixture(
        in app: XCUIApplication,
        fixtureApp: XCUIApplication,
        identity: SpaceFixtureAppIdentity,
        initialWindowCount: Int,
        priorSession: FlowTabUITestWindowMutationPriorSession,
        traceLabel: String,
        projectionAcceptance:
            SpaceFixtureCurrentAppProjectionAcceptanceOwner,
        expectedPID: pid_t
    ) -> Bool {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertFalse(
            diagnosticsSummary.exists,
            "Window mutation must start from a closed panel for \(traceLabel)."
        )
        fixtureApp.activate()
        guard fixtureApp.wait(
                for: .runningForeground,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .spaceFixtureForegroundActivation
            )
        else {
            XCTFail(
                "Fixture did not become foreground before \(traceLabel) mutation."
            )
            return false
        }
        guard let baseline = projectionAcceptance.waitForBaseline() else {
            XCTFail(
                "Missing exact complete projection baseline for \(traceLabel). "
                    + projectionAcceptance.diagnosticSummary
            )
            return false
        }
        XCTAssertEqual(baseline.bundleIdentifier, identity.bundleIdentifier)
        XCTAssertEqual(baseline.appID, identity.bundleIdentifier)
        XCTAssertEqual(baseline.processIdentifier, expectedPID)
        XCTAssertTrue(baseline.isCompleteForScope)
        XCTAssertEqual(baseline.windowIDs.count, initialWindowCount)
        XCTAssertEqual(Set(baseline.windowIDs).count, initialWindowCount)

        guard priorSession == .completedOptionTab else {
            return true
        }

        guard let flowTabProcessID = runningFlowTabProcessIdentifier(
            applicationState: app.state,
            traceLabel: traceLabel
        ) else {
            return false
        }
        let projectionResolved: Bool
        do {
            defer {
                injectRuntimeKeySet(
                    targetProcessID: flowTabProcessID,
                    keyCodes: [CGKeyCode(kVK_Tab)],
                    modifierFlags: .option,
                    phase: "release"
                )
            }
            projectionResolved = performAndWaitForSwitcherAppProjection(
                diagnosticsSummary,
                expectation:
                    .exactEntry(
                        "\(identity.bundleIdentifier):\(initialWindowCount)"
                    ),
                timeout:
                    SpaceFixtureWindowOpenMutationUITestPolicy
                        .completedOptionTabSessionWatchdog,
                trigger: {
                    injectRuntimeKeySet(
                        targetProcessID: flowTabProcessID,
                        keyCodes: [CGKeyCode(kVK_Tab)],
                        modifierFlags: .option,
                        phase: "press"
                    )
                }
            )
        }
        guard projectionResolved else {
            return false
        }
        XCTAssertTrue(
            waitForNonExistence(
                diagnosticsSummary,
                timeout:
                    SpaceFixtureWindowOpenMutationUITestPolicy
                        .panelDismissalWatchdog
            ),
            "Physical Option+Tab session did not close before \(traceLabel) mutation."
        )

        fixtureApp.activate()
        guard fixtureApp.wait(
                for: .runningForeground,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .spaceFixtureForegroundActivation
            )
        else {
            XCTFail(
                "Fixture did not return to the foreground after the "
                    + "Option+Tab session for \(traceLabel)."
            )
            return false
        }
        return true
    }

    private func assertPhysicalControlTabSession(
        in app: XCUIApplication,
        identity: SpaceFixtureAppIdentity,
        expectedTitles: [String],
        traceLabel: String,
        projectionAcceptance:
            SpaceFixtureCurrentAppProjectionAcceptanceOwner,
        expectedPID: pid_t,
        retiredTitle: String? = nil,
        retiredCGWindowID: CGWindowID? = nil
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
                        keys: [
                            "apps",
                            "selected",
                            "mode",
                            "preview",
                            "previewImages"
                        ]
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
            "Physical Control+Tab projection failed for \(traceLabel). "
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
        let acceptedProjection =
            projectionAcceptance.waitForAcceptedProjection()
        XCTAssertEqual(
            acceptedProjection?.bundleIdentifier,
            identity.bundleIdentifier
        )
        XCTAssertEqual(acceptedProjection?.appID, identity.bundleIdentifier)
        XCTAssertEqual(acceptedProjection?.processIdentifier, expectedPID)
        XCTAssertEqual(
            acceptedProjection?.windowIDs.count,
            expectedTitles.count
        )
        XCTAssertTrue(acceptedProjection?.isCompleteForScope == true)
        if let retiredCGWindowID {
            XCTAssertFalse(
                acceptedProjection?.windowIDs.contains(
                    "cg:\(expectedPID):\(retiredCGWindowID)"
                ) ?? true
            )
        }
        if let retiredTitle {
            XCTAssertEqual(
                switcherWindowCardObservations(in: app)
                    .filter { $0.title == retiredTitle }
                    .count,
                0
            )
        }
        guard waitForSwitcherDiagnostics(
            diagnosticsSummary,
            key: "previewImages",
            equals: String(expectedTitles.count),
            timeout:
                SpaceFixtureWindowOpenMutationUITestPolicy
                    .switcherProjectionWatchdog
        ) else {
            return
        }
        let renderedCards = switcherWindowCardObservations(in: app)
        XCTAssertEqual(renderedCards.count, expectedTitles.count)
        XCTAssertEqual(
            renderedCards.filter(\.hasImage).count,
            expectedTitles.count
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
                    + "physical shortcut injection; applicationState="
                    + "\(String(describing: applicationState)) "
                    + "matchingProcesses=\(matchingApplications.count)."
            )
            return nil
        }
        return processID
    }
}
