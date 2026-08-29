import AppKit
import XCTest

extension FlowTabUITests {
    func testSwitcherPanelKeepsOpenWindowLayerSnapshotAfterRealFixtureWindowSetMutation() throws {
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
            bundleIdentifier: identity.bundleIdentifier,
            timeout:
                FlowTabUITestSwitcherAppProjectionPolicy
                    .openWindowMutationInitialProjectionWatchdog
        ) else { return }
        do {
            guard try performAndWaitForSwitcherAppSelection(
                in: app,
                bundleIdentifier: identity.bundleIdentifier,
                appProjectionExpectation:
                    .bundleIdentifier(identity.bundleIdentifier),
                timeout:
                    FlowTabUITestSwitcherAppSelectionPolicy
                        .openWindowMutationApplicationWatchdog,
                trigger: {
                    try FlowTabUITestSwitcherCommandPayload.write(
                        identity.bundleIdentifier
                    )
                    postFlowTabUITestSwitcherCommand(
                        .selectApp,
                        traceLabel:
                            "openWindowLayerMutation.selectApp"
                    )
                }
            ) else { return }
        } catch {
            XCTFail(
                "Failed to select Open Mutation fixture App: \(error)"
            )
            return
        }

        let allTitles = expectedSpaceFixtureWorkflowWindowTitles(
            titlePrefix: "Open Mutation",
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
                    .openWindowMutationModeWatchdog,
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
                        .openWindowMutationInitialProjectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Initial Open Mutation window projection watchdog expired. "
                    + initialWindowCards.diagnosticSummary
            )
            return
        }

        var acceptsPostCloseSnapshot = false
        let postCloseCards = makeSwitcherWindowTitleObservation(
            in: app,
            expectedTitles: allTitles,
            acceptsResolution: {
                acceptsPostCloseSnapshot
            }
        )
        postCloseCards.start()
        defer { postCloseCards.cancel() }

        let reconciliationLogBaseline =
            makeRuntimeLogFileSnapshot()
        defer { reconciliationLogBaseline.cancel() }
        var acceptsRuntimeReconciliation = false
        let runtimeReconciliation =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation:
                    try .exactReadyCurrentAppRepair(
                        bundleIdentifier:
                            identity.bundleIdentifier,
                        processIdentifier: fixturePID,
                        windowCount: 1
                    ),
                observationRegistration:
                    reconciliationLogBaseline
                        .observationRegistration(),
                acceptsResolution: {
                    acceptsRuntimeReconciliation
                },
                readback:
                    reconciliationLogBaseline.makeReadback
            )
        runtimeReconciliation.start()
        defer { runtimeReconciliation.cancel() }

        windowCloseObservation.requestClose(from: scheduledClose)
        acceptsRuntimeReconciliation = true
        runtimeReconciliation.requestReadback(
            source: .triggerReadback
        )
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
        acceptsPostCloseSnapshot = true
        postCloseCards.requestReadback(source: .triggerReadback)
        guard let projectionEvidence = postCloseCards.waitForResolution(
            timeout:
                FlowTabUITestSwitcherWindowTitleObservationPolicy
                    .openWindowMutationProjectionWatchdog
        ) else {
            XCTFail(
                "Open Mutation Window-card projection watchdog expired. "
                    + postCloseCards.diagnosticSummary
            )
            return
        }
        XCTAssertEqual(projectionEvidence.value.cardCount, allTitles.count)
        XCTAssertEqual(
            projectionEvidence.value.titleCounts,
            Dictionary(uniqueKeysWithValues: allTitles.map { ($0, 1) })
        )

        guard
            runtimeReconciliation.waitForResolution(
                timeout:
                    FlowTabUITestRuntimeLogObservationPolicy
                        .openWindowMutationReconciliationWatchdog
            ) != nil
        else {
            XCTFail(
                "Open Mutation runtime reconciliation watchdog expired. "
                    + runtimeReconciliation.diagnosticSummary
            )
            return
        }
        XCTAssertNotEqual(fixtureApp.state, .notRunning)
    }

    func testSwitcherPanelKeepsOpenWorkflowAppWindowLayerSnapshotAfterMultiAppWindowSetMutation() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.appID == "chrome" },
            "Switcher workflow must include the Chrome-style fixture app for multi-app mutation proof"
        )
        let snapshotTitles = targetApp.expectedWindowTitles
        XCTAssertEqual(snapshotTitles.count, 2)

        let windowCloseRoute =
            makeSpaceFixtureWindowCloseFaultRoute()
        let windowCloseObservation =
            SpaceFixtureWindowCloseFaultObservationOwner(
                route: windowCloseRoute
            )
        windowCloseObservation.start()
        defer { windowCloseObservation.cancel() }

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-listen-switcher-trigger",
                "-windowLayerAutoEnterDelay", "30.0"
            ] + FlowTabUITestSwitcherCommandPayload.launchArguments,
            workflowAppLaunchArguments: { workflowApp in
                guard workflowApp.appID == targetApp.appID else {
                    return []
                }
                return [
                    "--close-window-index", "2",
                    "--close-window-delay-ms", "0"
                ] + windowCloseRoute.fixtureLaunchArguments
            }
        ) { workflow, app in
            let diagnosticsSummary = element(
                in: app,
                identifier: Identifier.switcherSummary
            )
            guard waitForSpaceFixtureSwitcherAppStripProjection(
                workflow,
                in: app
            ) != nil else { return }
            guard let scheduledClose =
                    windowCloseObservation.waitForScheduled(
                        timeout:
                            SpaceFixtureWindowCloseFaultObservationPolicy
                                .scheduledEvidenceWatchdog
                    )
            else {
                XCTFail(
                    "Missing scheduled multi-App Open Mutation close evidence: "
                        + windowCloseObservation.diagnosticSummary
                )
                return
            }

            let targetProcessIdentifier =
                try runningWorkflowApplicationProcessIdentifier(
                    targetApp
                )
            XCTAssertEqual(scheduledClose.delayMilliseconds, 0)
            XCTAssertTrue(scheduledClose.awaitsExplicitTrigger)
            XCTAssertEqual(
                scheduledClose.identity.bundleIdentifier,
                targetApp.identity.bundleIdentifier
            )
            XCTAssertEqual(
                scheduledClose.identity.processIdentifier,
                targetProcessIdentifier
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

            selectSwitcherWorkflowApp(
                targetApp,
                in: app,
                diagnosticsSummary: diagnosticsSummary
            )
            app.activate()
            guard enterSwitcherPreview(
                targetApp,
                in: app,
                diagnostics: diagnosticsSummary,
                allowsNoisyCGSiblings: false
            ) else { return }

            var acceptsPostCloseProjection = false
            let postCloseCards =
                makeSwitcherWindowTitleObservation(
                    in: app,
                    expectedTitles: snapshotTitles,
                    acceptsResolution: {
                        acceptsPostCloseProjection
                    }
                )
            postCloseCards.start()
            defer { postCloseCards.cancel() }
            XCTAssertNil(postCloseCards.resolvedEvidence)

            let reconciliationLogBaseline =
                makeRuntimeLogFileSnapshot()
            defer { reconciliationLogBaseline.cancel() }
            var acceptsRuntimeReconciliation = false
            let runtimeReconciliation =
                FlowTabUITestRuntimeLogObservationOwner(
                    expectation:
                        try .exactReadyCurrentAppRepair(
                            bundleIdentifier:
                                targetApp.identity.bundleIdentifier,
                            processIdentifier:
                                targetProcessIdentifier,
                            windowCount: 1
                        ),
                    observationRegistration:
                        reconciliationLogBaseline
                            .observationRegistration(),
                    acceptsResolution: {
                        acceptsRuntimeReconciliation
                    },
                    readback:
                        reconciliationLogBaseline.makeReadback
                )
            runtimeReconciliation.start()
            defer { runtimeReconciliation.cancel() }
            XCTAssertNil(runtimeReconciliation.resolvedEvidence)

            windowCloseObservation.requestClose(
                from: scheduledClose
            )
            acceptsRuntimeReconciliation = true
            runtimeReconciliation.requestReadback(
                source: .triggerReadback
            )
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
                    "Missing applied multi-App Open Mutation close evidence: "
                        + windowCloseObservation.diagnosticSummary
                )
                return
            }
            XCTAssertEqual(
                appliedClose.identity,
                scheduledClose.identity
            )
            XCTAssertEqual(
                appliedClose.requestGeneration,
                scheduledClose.requestGeneration
            )
            XCTAssertEqual(
                appliedClose.snapshot.targetWindowPlanIndex,
                2
            )
            XCTAssertEqual(
                appliedClose.snapshot.targetWindowNumber,
                scheduledClose.snapshot.targetWindowNumber
            )
            XCTAssertFalse(
                appliedClose.snapshot.targetWindowIsVisible
            )
            XCTAssertFalse(
                appliedClose.snapshot.targetCGWindowIsOnScreen
            )
            XCTAssertEqual(
                appliedClose.snapshot.remainingWindowPlanIndices,
                [1]
            )

            acceptsPostCloseProjection = true
            postCloseCards.requestReadback(
                source: .triggerReadback
            )
            guard let projectionEvidence =
                    postCloseCards.waitForResolution(
                        timeout:
                            FlowTabUITestSwitcherWindowTitleObservationPolicy
                                .multiAppOpenWindowMutationProjectionWatchdog
                    )
            else {
                XCTFail(
                    "Multi-App Open Mutation Window-card projection watchdog expired. "
                        + postCloseCards.diagnosticSummary
                )
                return
            }
            XCTAssertEqual(
                projectionEvidence.value.cardCount,
                snapshotTitles.count
            )
            XCTAssertEqual(
                projectionEvidence.value.titleCounts,
                Dictionary(
                    uniqueKeysWithValues:
                        snapshotTitles.map { ($0, 1) }
                )
            )
            guard requireActiveSwitcherPreview(
                targetApp,
                diagnostics: diagnosticsSummary
            ) else { return }
            guard
                runtimeReconciliation.waitForResolution(
                    timeout:
                        FlowTabUITestRuntimeLogObservationPolicy
                            .multiAppOpenWindowMutationReconciliationWatchdog
                ) != nil
            else {
                XCTFail(
                    "Multi-App Open Mutation runtime reconciliation "
                        + "watchdog expired. "
                        + runtimeReconciliation.diagnosticSummary
                )
                return
            }
            assertWorkflowApplicationProcessRemainsRunning(
                targetApp,
                processIdentifier: targetProcessIdentifier
            )
        }
    }
}
