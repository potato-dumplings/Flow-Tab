import AppKit
import Foundation
import XCTest

extension FlowTabUITests {
    func testSwitcherPanelKeepsWindowLayerWhenSelectedFixtureWindowCloses() throws {
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
            titlePrefix: "Selected Mutation",
            enterFullscreenDelayMilliseconds: 0,
            closeWindowIndex: 1,
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
                "Missing scheduled Selected Mutation close evidence: "
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
            1
        )
        XCTAssertGreaterThan(
            scheduledClose.snapshot.targetWindowNumber,
            0
        )
        XCTAssertTrue(scheduledClose.snapshot.targetWindowIsVisible)
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
                "selected-window-mutation-before-app-projection"
        )

        guard assertCurrentSwitcherAppProjection(
            in: app,
            exactEntry: "\(identity.bundleIdentifier):2",
            timeout:
                FlowTabUITestSwitcherAppProjectionPolicy
                    .selectedWindowMutationInitialProjectionWatchdog
        ) else { return }
        do {
            guard try performAndWaitForSwitcherAppSelection(
                in: app,
                bundleIdentifier: identity.bundleIdentifier,
                appProjectionExpectation:
                    .exactEntry(
                        "\(identity.bundleIdentifier):2"
                    ),
                timeout:
                    FlowTabUITestSwitcherAppSelectionPolicy
                        .selectedWindowMutationApplicationWatchdog,
                trigger: {
                    try FlowTabUITestSwitcherCommandPayload.write(
                        identity.bundleIdentifier
                    )
                    postFlowTabUITestSwitcherCommand(
                        .selectApp,
                        traceLabel:
                            "selectedWindowMutation.selectApp"
                    )
                }
            ) else { return }
        } catch {
            XCTFail(
                "Failed to select Selected Mutation fixture App: \(error)"
            )
            return
        }

        let allTitles = expectedSpaceFixtureWorkflowWindowTitles(
            titlePrefix: "Selected Mutation",
            windowCount: 2
        )
        var acceptsInitialWindowProjection = false
        let initialWindowCards =
            makeSwitcherWindowTitleObservation(
                in: app,
                expectedTitles: allTitles,
                acceptsResolution: {
                    acceptsInitialWindowProjection
                }
            )
        initialWindowCards.start()
        defer { initialWindowCards.cancel() }

        app.activate()
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        guard enterSwitcherPreview(
            expectedBundleIdentifier:
                identity.bundleIdentifier,
            diagnostics: diagnosticsSummary,
            previewExpectation: nil,
            timeout:
                FlowTabUITestSwitcherPreviewTransitionPolicy
                    .selectedWindowMutationModeWatchdog,
            trigger: {
                app.typeKey(.downArrow, modifierFlags: [])
            }
        ) else { return }
        acceptsInitialWindowProjection = true
        initialWindowCards.requestReadback(
            source: .triggerReadback
        )
        guard
            initialWindowCards.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherWindowTitleObservationPolicy
                        .selectedWindowMutationInitialWindowProjectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Initial Selected Mutation window projection watchdog expired. "
                    + initialWindowCards.diagnosticSummary
            )
            return
        }

        var acceptsPostCloseWindowProjection = false
        let postCloseCards =
            makeSwitcherWindowTitleObservation(
                in: app,
                expectedTitles: [allTitles[1]],
                acceptsResolution: {
                    acceptsPostCloseWindowProjection
                }
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
                "Missing applied Selected Mutation close evidence: "
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
            appliedClose.snapshot.targetWindowPlanIndex,
            1
        )
        XCTAssertEqual(
            appliedClose.snapshot.targetWindowNumber,
            scheduledClose.snapshot.targetWindowNumber
        )
        XCTAssertFalse(appliedClose.snapshot.targetWindowIsVisible)
        XCTAssertFalse(appliedClose.snapshot.targetCGWindowIsOnScreen)
        XCTAssertEqual(
            appliedClose.snapshot.remainingWindowPlanIndices,
            [2]
        )
        acceptsPostCloseWindowProjection = true
        postCloseCards.requestReadback(source: .triggerReadback)
        guard postCloseCards.waitForResolution(
            timeout:
                FlowTabUITestSwitcherWindowTitleObservationPolicy
                    .selectedWindowMutationProjectionWatchdog
        ) != nil else {
            XCTFail(
                "Selected Mutation Window-card projection watchdog expired. "
                    + postCloseCards.diagnosticSummary
            )
            return
        }
        assertSwitcherWindowCycle(in: app, timeout: 5)
        waitForRuntimeLogFiles(
            matching: #"runtimeAXDestroyed appID=io[.]github[.]potato-dumplings[.]flowtab[.]spacefixture pid=[0-9]+ axWindowID=ax:[0-9]+:[0-9]+ affectedCGWindowID=(none|[0-9]+)"#,
            since: mutationLogSnapshot,
            timeout: 8,
            description:
                "selected fixture window close should preserve open Switcher window-layer through shared runtime reconciliation"
        )
        XCTAssertNotEqual(fixtureApp.state, .notRunning)
    }
}
