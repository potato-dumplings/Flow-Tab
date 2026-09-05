import Darwin
import Foundation
import XCTest

extension FlowTabUITests {
    func testControlTabNoisyTopologyPressureGate() throws {
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
            lane: "topology",
            scenario: "noisy"
        )
        defer { try? metrics.write(to: metricsURL) }

        let observer = ControlTabPressureUITestObserver()
        observer.start()
        defer { observer.cancel() }
        let workflow = try configuredSwitcherRuntimeTruthWorkflow(
            sourceWorkflowURL:
                SpaceFixtureMultiAppWorkflowDefaults
                .optionTabWindowStateNoisyRuntimeTruthWorkflowSourceURL
        )
        let targetApp = try XCTUnwrap(
            workflow.apps.first { !$0.fullscreenWindowTitles.isEmpty }
        )
        XCTAssertEqual(targetApp.expectedWindowTitles.count, 4)
        let initialFullscreenTitle = try XCTUnwrap(
            targetApp.fullscreenWindowTitles.first
        )
        let topologyBaseline = makeRuntimeLogFileSnapshot()
        defer { topologyBaseline.cancel() }
        var executed = false

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments:
                runtimeTruthSwitcherLaunchArguments(
                    additionalArguments: [
                        "--flowtab-ui-enable-shortcut-event-injection"
                    ],
                    suppressesPanelActivation: false
                ),
            flowTabLaunchEnvironment: observer.launchEnvironment,
            waitsForFullscreenMarkers: false,
            suppressesAppAccessibilityChildren: true,
            validatesPermissionsBeforeFixtureLaunch: true,
            preservesDesktopAfterFullscreen: false,
            prelaunchesFlowTabBeforeFixture: true,
            beforeFlowTabLaunch: { _ in
                XCTAssertTrue(
                    self.waitForWorkflowSpaceContainingCGWindow(
                        title: initialFullscreenTitle,
                        app: targetApp,
                        timeout: 12
                    )
                )
            },
            flowTabLaunchTraceLabel: "control-tab.topology"
        ) { _, app in
            executed = true
            let targetApplication =
                makeSpaceFixtureWorkflowApplication(
                    for: targetApp.identity
                )
            targetApplication.activate()
            let targetPID = try runningWorkflowApplicationProcessIdentifier(
                targetApp
            )

            let physicalEvidence = try assertPhysicalControlTabPressureGate(
                in: app,
                observer: observer,
                scenario: ControlTabPressureUITestScenario(
                    name: "noisy",
                    variant: "real-runtime",
                    expectedAppCount: 0,
                    expectedWindowCount: 4,
                    focusedAppID: targetApp.identity.bundleIdentifier
                )
            )
            physicalEvidence.forEach {
                metrics.append($0, cycle: 0)
            }
            metrics.appendProof(
                ControlTabPressureProof(
                    kind: "physical_shortcut",
                    generation: 0,
                    processIdentifier: targetPID,
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
            var exactlyActivatedTitles = Set<String>()
            let minimumCycleCount =
                ControlTabTopologyPressureCyclePlan
                .minimumCycleCount(
                    windowCount: targetApp.expectedWindowTitles.count
                )
            repeat {
                cycle += 1
                let plan = ControlTabTopologyPressureCyclePlan(
                    cycle: cycle,
                    windowCount: targetApp.expectedWindowTitles.count
                )
                targetApplication.activate()
                if let activatedTitle = try runControlTabTopologyPressureCycle(
                    observer: observer,
                    targetApp: targetApp,
                    targetPID: targetPID,
                    desiredTitle: targetApp.expectedWindowTitles[
                        plan.windowIndex
                    ],
                    cycle: cycle,
                    commits: plan.commits,
                    app: app,
                    capturesScreenshot: cycle == 1,
                    topologyBaseline: topologyBaseline,
                    metrics: &metrics
                ) {
                    exactlyActivatedTitles.insert(activatedTitle)
                }
            } while Date().timeIntervalSince(measurementStart) < duration
                || cycle < minimumCycleCount

            XCTAssertEqual(
                exactlyActivatedTitles,
                Set(targetApp.expectedWindowTitles),
                "Every noisy-topology window must complete exact activation."
            )

            try finishControlTabPressureCooldown(
                observer: observer,
                seconds: cooldown,
                metrics: &metrics
            )
            try metrics.write(to: metricsURL)
        }

        guard executed else {
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
            try metrics.write(to: metricsURL)
            throw XCTSkip(
                "Control+Tab topology pressure requires Accessibility and Screen Recording permissions."
            )
        }
    }

    private func runControlTabTopologyPressureCycle(
        observer: ControlTabPressureUITestObserver,
        targetApp: SpaceFixtureResolvedWorkflow.App,
        targetPID: pid_t,
        desiredTitle: String,
        cycle: Int,
        commits: Bool,
        app: XCUIApplication,
        capturesScreenshot: Bool,
        topologyBaseline: FlowTabUITestRuntimeLogObservationBaseline,
        metrics: inout ControlTabPressureMetricsRecorder
    ) throws -> String? {
        let opened = try postControlTabPressureAction(
            "open",
            observer: observer,
            phase: "open"
        )
        XCTAssertTrue(opened.satisfied)
        XCTAssertTrue(opened.panelPresented)
        XCTAssertEqual(
            opened.selectedAppID,
            targetApp.identity.bundleIdentifier
        )
        XCTAssertEqual(opened.selectedWindowCount, 4)
        XCTAssertTrue(opened.partitionsReconciled)
        XCTAssertTrue(opened.timingValid)
        XCTAssertFalse(opened.latePresentationObserved)
        XCTAssertFalse(opened.watchdogExpired)
        var evidence = [opened]

        let diagnostics = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForSwitcherPreviewTitles(
                diagnostics,
                toExactlyMatch: targetApp.expectedWindowTitles,
                timeout: 8
            ),
            "Control+Tab included a window outside the focused app."
        )
        if capturesScreenshot {
            let attachment = XCTAttachment(
                screenshot: XCUIScreen.main.screenshot()
            )
            attachment.name =
                "flowtab-control-tab-topology-noisy-windowContentDraw"
            attachment.lifetime = .keepAlways
            add(attachment)
            assertNoisyControlTabTopologyEvidence(
                since: topologyBaseline,
                targetPID: targetPID,
                metrics: &metrics
            )
        }

        evidence.append(
            try postControlTabPressureAction(
                "forward",
                observer: observer,
                phase: "forward"
            )
        )
        evidence.append(
            try postControlTabPressureAction(
                "reverse",
                observer: observer,
                phase: "reverse"
            )
        )

        var selectedTitle = switcherPanelDiagnosticsValue(
            diagnostics,
            key: "selectedWindowTitle"
        )
        for _ in 0..<(targetApp.expectedWindowTitles.count + 1)
            where selectedTitle != desiredTitle
        {
            let advanced = try postControlTabPressureAction(
                "forward",
                observer: observer,
                phase: "forward"
            )
            evidence.append(advanced)
            XCTAssertTrue(
                waitForSwitcherDiagnostics(
                    diagnostics,
                    key: "selectedWindow",
                    equals: advanced.selectedWindowIDAfter,
                    timeout: 5
                )
            )
            selectedTitle = switcherPanelDiagnosticsValue(
                diagnostics,
                key: "selectedWindowTitle"
            )
        }
        XCTAssertEqual(selectedTitle, desiredTitle)
        let selectedWindowID = switcherPanelDiagnosticsValue(
            diagnostics,
            key: "selectedWindow"
        )
        let selection = try runtimeTruthWindowSelection(
            title: selectedTitle,
            windowID: selectedWindowID
        )

        let terminalPhase = commits ? "commit" : "cancel"
        let activationBaseline = makeRuntimeLogFileSnapshot()
        let terminal = try postControlTabPressureAction(
            terminalPhase,
            observer: observer,
            phase: terminalPhase
        )
        evidence.append(terminal)
        XCTAssertTrue(
            waitForControlTabPanelToBecomeUserHidden(
                diagnostics,
                timeout: 5
            )
        )
        var exactlyActivatedTitle: String?

        if commits {
            let exactFrontmost = waitForExactFrontmostWorkflowCGWindow(
                windowNumber: selection.windowNumber,
                title: selection.title,
                app: targetApp,
                timeout: 8
            )
            let verifiedFocus =
                waitForControlTabVerifiedFocusReadback(
                    selection: selection,
                    processIdentifier: targetPID,
                    since: activationBaseline
                )
            XCTAssertTrue(exactFrontmost)
            XCTAssertTrue(verifiedFocus)
            let activationSatisfied = exactFrontmost && verifiedFocus
            metrics.appendProof(
                ControlTabPressureProof(
                    kind: "exact_activation",
                    generation: Int(terminal.projectionGeneration),
                    processIdentifier: targetPID,
                    windowID: selectedWindowID,
                    cgWindowID: selection.windowNumber,
                    satisfied: activationSatisfied,
                    detail:
                        "title=\(selection.title);"
                        + "target-pid,window-id,cg-window-id,verified-focus-readback"
                )
            )
            if activationSatisfied {
                exactlyActivatedTitle = selection.title
            }
        }
        activationBaseline.cancel()

        for item in evidence {
            metrics.append(item, cycle: cycle)
            assertControlTabStructuredSpanEvidence(item)
            XCTAssertTrue(item.satisfied)
            XCTAssertTrue(item.timingValid)
            XCTAssertFalse(item.latePresentationObserved)
            XCTAssertFalse(item.watchdogExpired)
        }
        return exactlyActivatedTitle
    }

    private func assertNoisyControlTabTopologyEvidence(
        since baseline: FlowTabUITestRuntimeLogObservationBaseline,
        targetPID: pid_t,
        metrics: inout ControlTabPressureMetricsRecorder
    ) {
        let pattern =
            #"filtered-fullscreen-((sibling|host)-artifacts stage=(pre-dedupe|presentation)|duplicate-surfaces stage=presentation-final) dropped=[1-9][0-9]*"#
        waitForRuntimeLogFiles(
            matching: pattern,
            since: baseline,
            timeout: 8,
            description: "filtered noisy CG/fullscreen sibling evidence"
        )
        let matched = regularExpression(
            pattern,
            matches: runtimeLogContentsSinceSnapshot(baseline)
        )
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "topology_scope",
                generation: 0,
                processIdentifier: targetPID,
                windowID: "four-user-windows",
                cgWindowID: 0,
                satisfied: matched,
                detail: "standard=2;fullscreen=2;off-space=covered;noisy-cg=filtered"
            )
        )
    }

    private func waitForControlTabVerifiedFocusReadback(
        selection: RuntimeTruthWindowSelection,
        processIdentifier: pid_t,
        since baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) -> Bool {
        let verifiedFocusPattern =
            FlowTabUITestReusableWindowEvidence
            .verifiedFocusReadbackRegexPattern
        let pattern =
            "binding-confidence-change windowID=cg:"
                + "\(processIdentifier):\(selection.windowNumber) "
                + "cg=\(selection.windowNumber) .* "
                + "\(verifiedFocusPattern) verifiedFocusFallbackAX=0"
        waitForRuntimeLogFiles(
            matching: pattern,
            since: baseline,
            timeout: 8,
            description: "Control+Tab exact verified-focus readback"
        )
        return regularExpression(
            pattern,
            matches: runtimeLogContentsSinceSnapshot(baseline)
        )
    }

    private func regularExpression(
        _ pattern: String,
        matches contents: String
    ) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern)
        else { return false }
        let range = NSRange(
            contents.startIndex..<contents.endIndex,
            in: contents
        )
        return expression.firstMatch(
            in: contents,
            range: range
        ) != nil
    }
}
