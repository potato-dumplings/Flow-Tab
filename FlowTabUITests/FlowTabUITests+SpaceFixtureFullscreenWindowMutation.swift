import Foundation
import XCTest

extension FlowTabUITests {
    func testSwitcherPanelRefreshesOpenFullscreenWorkflowAppWindowLayerAfterTargetWindowCloses()
        throws
    {
        let workflow =
            try configuredSwitcherSpaceFixtureWorkflow()
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.appID == "notes" },
            "Switcher workflow must include the Notes-style fixture app for fullscreen target-window mutation proof"
        )
        let fullscreenWindowIndex = try XCTUnwrap(
            targetApp.fullscreenWindowIndex
        )
        let fullscreenTitles = Set(
            targetApp.fullscreenWindowTitles
        )
        let remainingTitles =
            targetApp.expectedWindowTitles.filter {
                !fullscreenTitles.contains($0)
            }
        let initialWindowPlanIndices =
            Array(1...targetApp.windowCount)
        let remainingWindowPlanIndices =
            initialWindowPlanIndices.filter {
                $0 != fullscreenWindowIndex
            }
        XCTAssertEqual(targetApp.expectedWindowTitles.count, 2)
        XCTAssertEqual(fullscreenTitles.count, 1)
        XCTAssertEqual(remainingTitles.count, 1)

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
            ] + FlowTabUITestSwitcherCommandPayload
                .launchArguments,
            workflowAppLaunchArguments: { workflowApp in
                guard workflowApp.appID == targetApp.appID
                else {
                    return []
                }
                return [
                    "--close-window-index",
                    "\(fullscreenWindowIndex)",
                    "--close-window-delay-ms",
                    "0"
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
                    "Missing scheduled fullscreen multi-App close evidence: "
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
                fullscreenWindowIndex
            )
            XCTAssertGreaterThan(
                scheduledClose.snapshot.targetWindowNumber,
                0
            )
            XCTAssertTrue(
                scheduledClose.snapshot.targetWindowIsVisible
            )
            XCTAssertEqual(
                scheduledClose.snapshot
                    .remainingWindowPlanIndices,
                initialWindowPlanIndices
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
                allowsNoisyCGSiblings: true
            ) else { return }
            let closedFullscreenTitle = try XCTUnwrap(
                visibleFullscreenWindowTitle(
                    in: diagnosticsSummary,
                    for: targetApp
                )
            )

            var acceptsPostCloseProjection = false
            let postCloseCards =
                makeSwitcherWindowTitleObservation(
                    in: app,
                    expectedTitles: remainingTitles,
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
                        try .exactRuntimeAXDestroyed(
                            bundleIdentifier:
                                targetApp.identity.bundleIdentifier,
                            processIdentifier:
                                targetProcessIdentifier,
                            affectedCGWindowID:
                                scheduledClose.snapshot
                                    .targetWindowNumber
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
                    "Missing applied fullscreen multi-App close evidence: "
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
                fullscreenWindowIndex
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
                appliedClose.snapshot
                    .remainingWindowPlanIndices,
                remainingWindowPlanIndices
            )

            acceptsPostCloseProjection = true
            postCloseCards.requestReadback(
                source: .triggerReadback
            )
            guard let projectionEvidence =
                    postCloseCards.waitForResolution(
                        timeout:
                            FlowTabUITestSwitcherWindowTitleObservationPolicy
                                .fullscreenMultiAppWindowMutationProjectionWatchdog
                    )
            else {
                XCTFail(
                    "Fullscreen multi-App Window-card projection watchdog expired. "
                        + postCloseCards.diagnosticSummary
                )
                return
            }
            XCTAssertEqual(projectionEvidence.value.cardCount, 1)
            XCTAssertEqual(
                projectionEvidence.value.titleCounts,
                [remainingTitles[0]: 1]
            )
            guard requireActiveSwitcherPreview(
                targetApp,
                diagnostics: diagnosticsSummary
            ) else { return }
            guard
                runtimeReconciliation.waitForResolution(
                    timeout:
                        FlowTabUITestRuntimeLogObservationPolicy
                            .fullscreenMultiAppWindowMutationReconciliationWatchdog
                ) != nil
            else {
                XCTFail(
                    "Fullscreen multi-App runtime reconciliation "
                        + "watchdog expired. "
                        + runtimeReconciliation.diagnosticSummary
                )
                return
            }
            assertWorkflowApplicationProcessRemainsRunning(
                targetApp,
                processIdentifier: targetProcessIdentifier
            )
            XCTAssertFalse(
                switcherPreviewTitles(
                    from: diagnosticsSummary
                ).contains(closedFullscreenTitle),
                """
                Open Switcher window layer still exposed the closed fullscreen target window.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
            XCTAssertTrue(
                Set(
                    switcherPreviewTitles(
                        from: diagnosticsSummary
                    )
                ).isDisjoint(
                    with: Set(
                        workflow.otherExpectedWindowTitles(
                            excluding: targetApp.appID
                        )
                    )
                ),
                """
                Fullscreen target-window mutation exposed another app's window card.

                \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
                """
            )
        }
    }
}
