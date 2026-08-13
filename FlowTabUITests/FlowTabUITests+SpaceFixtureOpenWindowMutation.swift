import AppKit
import XCTest

extension FlowTabUITests {
    func testSwitcherPanelRefreshesOpenWindowLayerAfterRealFixtureWindowSetMutation() throws {
        let identity = spaceFixtureAppIdentity

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

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
            titlePrefix: "Open Mutation",
            enterFullscreenDelayMilliseconds: 0,
            closeWindowIndex: 2,
            closeWindowDelayMilliseconds: 0,
            fixtureAdditionalArguments:
                windowCloseRoute.fixtureLaunchArguments
        )
        let mutationLogSnapshot = makeRuntimeLogFileSnapshot()
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
        guard let scheduledClose =
                windowCloseObservation.waitForScheduled(
                    timeout:
                        SpaceFixtureWindowCloseFaultObservationPolicy
                            .scheduledEvidenceWatchdog
                )
        else {
            XCTFail(
                "Missing scheduled Open Mutation close evidence: "
                    + windowCloseObservation.diagnosticSummary
            )
            return
        }
        XCTAssertEqual(scheduledClose.delayMilliseconds, 0)
        XCTAssertTrue(scheduledClose.awaitsExplicitTrigger)
        XCTAssertEqual(
            scheduledClose.identity.bundleIdentifier,
            identity.bundleIdentifier
        )
        let fixturePID = scheduledClose.identity.processIdentifier
        XCTAssertTrue(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: identity.bundleIdentifier
            ).contains {
                !$0.isTerminated
                    && $0.processIdentifier == fixturePID
            }
        )
        XCTAssertEqual(
            scheduledClose.snapshot.targetWindowPlanIndex,
            2
        )
        XCTAssertGreaterThan(
            scheduledClose.snapshot.targetWindowNumber,
            0
        )
        XCTAssertTrue(
            scheduledClose.snapshot.targetWindowIsVisible
        )
        XCTAssertEqual(
            scheduledClose.snapshot.remainingWindowPlanIndices,
            [1, 2]
        )

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
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }

        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: nil,
            targetDescription:
                "open-window-mutation-before-app-projection"
        )

        guard assertCurrentSwitcherAppProjection(
            in: app,
            exactEntry: "\(identity.bundleIdentifier):2",
            timeout:
                FlowTabUITestSwitcherAppProjectionPolicy
                    .openWindowMutationInitialProjectionWatchdog
        ) else { return }
        selectSwitcherAppDirectly(
            in: app,
            appID: identity.bundleIdentifier,
            traceLabel: "openWindowLayerMutation.selectApp",
            timeout: 8
        )

        let allTitles = expectedSpaceFixtureWorkflowWindowTitles(
            titlePrefix: "Open Mutation",
            windowCount: 2
        )
        app.activate()
        assertSwitcherWindowCycle(in: app, timeout: 5) {
            app.typeKey(.downArrow, modifierFlags: [])
        }
        guard waitForSwitcherWindowCards(
            in: app,
            expectedTitles: allTitles,
            timeout: 8
        ) else { return }

        let postCloseCards = makeSwitcherWindowTitleObservation(
            in: app,
            expectedTitles: [allTitles[0]]
        )
        postCloseCards.start()
        defer { postCloseCards.cancel() }

        windowCloseObservation.requestClose(from: scheduledClose)
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
                "Missing applied Open Mutation close evidence: "
                    + windowCloseObservation.diagnosticSummary
            )
            return
        }
        XCTAssertEqual(appliedClose.identity, scheduledClose.identity)
        XCTAssertEqual(
            appliedClose.requestGeneration,
            scheduledClose.requestGeneration
        )
        XCTAssertEqual(
            appliedClose.snapshot.targetWindowNumber,
            scheduledClose.snapshot.targetWindowNumber
        )
        XCTAssertFalse(appliedClose.snapshot.targetWindowIsVisible)
        XCTAssertFalse(
            appliedClose.snapshot.targetCGWindowIsOnScreen
        )
        XCTAssertEqual(
            appliedClose.snapshot.remainingWindowPlanIndices,
            [1]
        )
        guard postCloseCards.waitForResolution(
            timeout:
                FlowTabUITestSwitcherWindowTitleObservationPolicy
                    .openWindowMutationProjectionWatchdog
        ) != nil else {
            XCTFail(
                "Open Mutation Window-card projection watchdog expired. "
                    + postCloseCards.diagnosticSummary
            )
            return
        }

        waitForRuntimeLogFiles(
            matching: #"runtimeAXDestroyed appID=io[.]github[.]potato-dumplings[.]flowtab[.]spacefixture pid=[0-9]+ axWindowID=ax:[0-9]+:[0-9]+ affectedCGWindowID=(none|[0-9]+)"#,
            since: mutationLogSnapshot,
            timeout: 8,
            description: "open Switcher window-layer mutation should flow through shared runtime AX destroyed reconciliation"
        )
        XCTAssertNotEqual(fixtureApp.state, .notRunning)
    }
}
