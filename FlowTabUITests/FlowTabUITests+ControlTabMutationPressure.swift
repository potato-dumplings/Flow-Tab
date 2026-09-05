import Foundation
import XCTest

extension FlowTabUITests {
    func testControlTabClosedPanelMutationPressureGate() throws {
        continueAfterFailure = true
        let environment = ProcessInfo.processInfo.environment
        let duration = ControlTabPressureUITestPolicy.duration(
            environment: environment
        )
        let cooldown = ControlTabPressureUITestPolicy.cooldown(
            environment: environment
        )
        let metricsURL = controlTabPressureMetricsURL(environment)
        var metrics = ControlTabPressureMetricsRecorder(
            lane: "mutation",
            scenario: "closed-panel"
        )
        defer { try? metrics.write(to: metricsURL) }

        let controlObserver = ControlTabPressureUITestObserver()
        controlObserver.start()
        defer { controlObserver.cancel() }
        let mutationObserver = ControlTabMutationFixtureObserver()
        mutationObserver.start()
        defer { mutationObserver.cancel() }

        let projectionRoute = makeSpaceFixtureCurrentAppProjectionAcceptanceRoute(
            bundleIdentifier: spaceFixtureAppIdentity.bundleIdentifier)
        defer { projectionRoute.removeReadback() }
        let app = makeRealRuntimeFlowTabApp(
            additionalArguments: runtimeTruthSwitcherLaunchArguments(
                additionalArguments: [
                    "--flowtab-ui-enable-shortcut-event-injection"
                ] + projectionRoute.flowTabLaunchArguments,
                suppressesPanelActivation: false
            )
        )
        for item in controlObserver.launchEnvironment {
            app.launchEnvironment[item.key] = item.value
        }
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
            traceLabel: "control-tab.mutation",
            targetDescription: "before-repeatable-fixture"
        )
        guard assertSpaceFixtureWorkflowPermissionsAvailable(in: app)
        else {
            metrics.appendProof(
                ControlTabPressureProof(
                    kind: "permission",
                    generation: 0,
                    processIdentifier: 0,
                    windowID: "none",
                    cgWindowID: 0,
                    satisfied: false,
                    detail: "accessibility-or-screen-capture"
                )
            )
            throw XCTSkip(
                "Control+Tab mutation pressure requires Accessibility and Screen Recording permissions."
            )
        }

        let identity = spaceFixtureAppIdentity
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 3,
            fullscreenWindowIndex: nil,
            titlePrefix: "Control Tab Mutation",
            enterFullscreenDelayMilliseconds: 0,
            fixtureAdditionalArguments:
                mutationObserver.route.launchArguments
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
        XCTAssertTrue(
            fixtureApp.wait(for: .runningForeground, timeout: 8)
        )
        XCTAssertFalse(
            element(in: app, identifier: Identifier.switcherSummary)
                .exists
        )

        var targetIsOpen = true

        let firstMutation = try applyControlTabFixtureMutation(
            .close,
            observer: mutationObserver,
            expectedWindowCount: 2,
            app: app,
            metrics: &metrics
        )
        targetIsOpen = false
        let firstCycle = try runControlTabRealRuntimeCycle(
            observer: controlObserver,
            expectedAppID: identity.bundleIdentifier,
            expectedWindowCount: 2,
            expectedTitles: [
                "Control Tab Mutation 1",
                "Control Tab Mutation 2"
            ],
            cycle: 0,
            commits: false,
            app: app,
            screenshotName:
                "flowtab-control-tab-mutation-closed-panel-windowContentDraw",
            metrics: &metrics
        )
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "first_session",
                generation: firstMutation.generation,
                processIdentifier:
                    firstMutation.identity.processIdentifier,
                windowID: "window-plan-3",
                cgWindowID: firstMutation.retiredCGWindowID,
                satisfied:
                    firstCycle.first?.satisfied == true,
                detail: "closed-panel-3-to-2"
            )
        )

        fixtureApp.activate()
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            .global,
            traceLabel: "control-tab.mutation.option-history"
        )
        let globalDiagnostics = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(globalDiagnostics.waitForExistence(timeout: 8))
        app.activate()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForControlTabPanelToBecomeUserHidden(
                globalDiagnostics,
                timeout: 5
            )
        )
        fixtureApp.activate()
        let optionHistoryCleanupSequence = try XCTUnwrap(
            controlObserver.post("cancel")
        )
        let optionHistoryCleanup = try XCTUnwrap(
            controlObserver.wait(
                sequence: optionHistoryCleanupSequence,
                phase: "cancel"
            ),
            "Option+Tab history modifier cleanup did not complete."
        )
        metrics.append(optionHistoryCleanup, cycle: 0)
        assertControlTabStructuredSpanEvidence(
            optionHistoryCleanup
        )
        XCTAssertTrue(optionHistoryCleanup.satisfied)
        let reopened = try applyControlTabFixtureMutation(
            .open,
            observer: mutationObserver,
            expectedWindowCount: 3,
            app: app,
            metrics: &metrics
        )
        targetIsOpen = true
        let optionHistoryReentry = try runControlTabRealRuntimeCycle(
            observer: controlObserver,
            expectedAppID: identity.bundleIdentifier,
            expectedWindowCount: 3,
            expectedTitles: [
                "Control Tab Mutation 1",
                "Control Tab Mutation 2",
                "Control Tab Mutation 3"
            ],
            cycle: 0,
            commits: true,
            app: app,
            metrics: &metrics
        )
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "option_tab_history",
                generation: reopened.generation,
                processIdentifier:
                    reopened.identity.processIdentifier,
                windowID:
                    optionHistoryReentry.first?
                        .selectedWindowIDAfter ?? "none",
                cgWindowID: 0,
                satisfied:
                    optionHistoryReentry.first?.satisfied == true,
                detail:
                    "completed-global-session;cleanup="
                    + (
                        optionHistoryCleanup.satisfied
                            ? "released" : "invalid"
                    )
                    + ";focused-reentry="
                    + (
                        optionHistoryReentry.first?.satisfied
                            == true ? "ready" : "invalid"
                    )
            )
        )

        let projectionOwner = SpaceFixtureCurrentAppProjectionAcceptanceOwner(
            route: projectionRoute,
            expectedPID: reopened.identity.processIdentifier,
            expectation: SpaceFixtureCurrentAppProjectionAcceptanceExpectation(
                baselineWindowCount: 3,
                targetWindowCount: 2,
                mutation: .closed))
        projectionOwner.start()
        defer { projectionOwner.cancel() }
        let projectionBaseline = try XCTUnwrap(projectionOwner.waitForBaseline(), projectionOwner.diagnosticSummary)
        XCTAssertTrue(projectionOwner.startTargetObservation())
        let dirtyProjection = try XCTUnwrap(mutationObserver.mutate(.close))
        let completeProjection = try XCTUnwrap(projectionOwner.waitForAcceptedProjection(), projectionOwner.diagnosticSummary)
        XCTAssertTrue(completeProjection.isCompleteForScope)
        XCTAssertEqual(completeProjection.processIdentifier, dirtyProjection.identity.processIdentifier)
        XCTAssertTrue(completeProjection.sourceGeneration.isStrictlyLater(than: projectionBaseline.sourceGeneration))
        XCTAssertEqual(completeProjection.windowIDs.count, 2)
        let freshOpenSequence = try XCTUnwrap(controlObserver.post("physicalOpen"))
        pressAndHoldPhysicalControlTab(in: app)
        let freshOpen = try XCTUnwrap(controlObserver.wait(sequence: freshOpenSequence, phase: "open"))
        metrics.append(freshOpen, cycle: 0)
        assertControlTabStructuredSpanEvidence(freshOpen)
        XCTAssertTrue(freshOpen.satisfied)
        XCTAssertFalse(freshOpen.watchdogExpired)
        XCTAssertEqual(freshOpen.selectedWindowCount, 2)
        XCTAssertTrue(dirtyProjection.readbackSatisfied)
        XCTAssertFalse(dirtyProjection.watchdogExpired)
        XCTAssertEqual(
            dirtyProjection.snapshot.activeWindowPlanIndices.count,
            2
        )
        let strictDiagnostics = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(strictDiagnostics.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForSwitcherPreviewTitles(
                strictDiagnostics,
                toExactlyMatch: [
                    "Control Tab Mutation 1",
                    "Control Tab Mutation 2"
                ],
                timeout: 8
            )
        )
        let freshCommitSequence = try XCTUnwrap(controlObserver.post("physicalCommit"))
        releasePhysicalControlTab(in: app)
        XCTAssertTrue(
            waitForControlTabPanelToBecomeUserHidden(
                strictDiagnostics,
                timeout: 5
            )
        )
        let freshCommit = try XCTUnwrap(controlObserver.wait(sequence: freshCommitSequence, phase: "commit"))
        metrics.append(freshCommit, cycle: 0)
        assertControlTabStructuredSpanEvidence(freshCommit)
        XCTAssertTrue(freshCommit.satisfied)
        XCTAssertTrue(freshCommit.activationVerified)
        targetIsOpen = false
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "mutation_generation",
                generation: dirtyProjection.generation,
                processIdentifier:
                    dirtyProjection.identity.processIdentifier,
                windowID: "window-plan-3",
                cgWindowID: dirtyProjection.retiredCGWindowID,
                satisfied: dirtyProjection.readbackSatisfied
                    && !dirtyProjection.watchdogExpired
                    && dirtyProjection.snapshot
                        .activeWindowPlanIndices.count == 2,
                detail: "action=close;windows=2"
            )
        )
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "dirty_projection_gate",
                generation: dirtyProjection.generation,
                processIdentifier:
                    dirtyProjection.identity.processIdentifier,
                windowID: "window-plan-3",
                cgWindowID: dirtyProjection.retiredCGWindowID,
                satisfied: completeProjection.isCompleteForScope
                    && completeProjection.sourceGeneration.isStrictlyLater(than: projectionBaseline.sourceGeneration)
                    && completeProjection.windowIDs.count == 2
                    && freshOpen.satisfied && freshCommit.activationVerified,
                detail: "strict-complete-projection-before-first-frame;source="
                    + completeProjection.sourceGeneration.diagnosticSummary
            )
        )

        _ = try applyControlTabFixtureMutation(
            .open,
            observer: mutationObserver,
            expectedWindowCount: 3,
            app: app,
            metrics: &metrics
        )
        targetIsOpen = true
        var cancellationSequence: UInt64?
        let earlyRelease = try XCTUnwrap(
            mutationObserver.mutate(
                .close,
                afterAcknowledgement: {
                    cancellationSequence =
                        controlObserver.post("physicalCancel")
                    self.pressAndReleasePhysicalControlTab(in: app)
                }
            )
        )
        assertControlTabFixtureMutationEvidence(
            earlyRelease,
            expectedWindowCount: 2,
            app: app,
            expectsClosedPanel: false
        )
        targetIsOpen = false
        let cancellationEvidence = try XCTUnwrap(
            controlObserver.wait(
                sequence: try XCTUnwrap(cancellationSequence),
                phase: "cancel"
            ),
            "Early Control release cancellation readback expired."
        )
        metrics.append(cancellationEvidence, cycle: 0)
        assertControlTabStructuredSpanEvidence(
            cancellationEvidence
        )
        XCTAssertTrue(
            waitForControlTabPanelToBecomeUserHidden(
                element(
                    in: app,
                    identifier: Identifier.switcherSummary
                ),
                timeout: 5
            ),
            "Early Control release allowed a delayed panel presentation."
        )
        XCTAssertTrue(cancellationEvidence.satisfied)
        XCTAssertTrue(cancellationEvidence.timingValid)
        XCTAssertFalse(cancellationEvidence.watchdogExpired)
        XCTAssertFalse(cancellationEvidence.latePresentationObserved)
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "early_control_release",
                generation: earlyRelease.generation,
                processIdentifier:
                    earlyRelease.identity.processIdentifier,
                windowID: "window-plan-3",
                cgWindowID: earlyRelease.retiredCGWindowID,
                satisfied: cancellationEvidence.satisfied
                    && cancellationEvidence.timingValid
                    && !cancellationEvidence.watchdogExpired
                    && !cancellationEvidence
                        .latePresentationObserved,
                detail: "cancelled-before-freshness-resolve"
            )
        )

        fixtureApp.activate()
        let physicalEvidence = try assertPhysicalControlTabPressureGate(
            in: app,
            observer: controlObserver,
            scenario: ControlTabPressureUITestScenario(
                name: "closed-panel",
                variant: "real-runtime",
                expectedAppCount: 0,
                expectedWindowCount: 2,
                focusedAppID: identity.bundleIdentifier
            )
        )
        physicalEvidence.forEach {
            metrics.append($0, cycle: 0)
        }
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "physical_shortcut",
                generation: earlyRelease.generation,
                processIdentifier:
                    earlyRelease.identity.processIdentifier,
                windowID: "none",
                cgWindowID: 0,
                satisfied:
                    controlTabPhysicalShortcutEvidenceSatisfied(
                        physicalEvidence
                    ),
                detail: "control-tab,control-shift-tab,hold-release"
            )
        )
        metrics.appendProof(
            try waitForControlTabSamplerReadiness(
                environment: environment
            )
        )

        metrics.mark("measurement_start")
        let measurementStart = Date()
        var cycle = 0

        repeat {
            let action: SpaceFixtureWindowMutationPressureAction =
                targetIsOpen ? .close : .open
            let expectedCount = targetIsOpen ? 2 : 3
            _ = try applyControlTabFixtureMutation(
                action,
                observer: mutationObserver,
                expectedWindowCount: expectedCount,
                app: app,
                metrics: &metrics
            )
            targetIsOpen.toggle()
            cycle += 1
            let titles = (1...expectedCount).map {
                "Control Tab Mutation \($0)"
            }
            _ = try runControlTabRealRuntimeCycle(
                observer: controlObserver,
                expectedAppID: identity.bundleIdentifier,
                expectedWindowCount: expectedCount,
                expectedTitles: titles,
                cycle: cycle,
                commits: cycle.isMultiple(of: 2),
                app: app,
                metrics: &metrics
            )
        } while Date().timeIntervalSince(measurementStart) < duration

        try finishControlTabPressureCooldown(
            observer: controlObserver,
            seconds: cooldown,
            metrics: &metrics
        )
        try metrics.write(to: metricsURL)
        XCTAssertGreaterThan(reopened.generation, firstMutation.generation)
    }
}
