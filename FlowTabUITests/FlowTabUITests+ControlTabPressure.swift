import Foundation
import XCTest
extension FlowTabUITests {
    func testControlTabDeterministicPressureGate() throws {
        continueAfterFailure = true
        let environment = ProcessInfo.processInfo.environment
        let scenario = ControlTabPressureUITestScenario
            .configured(environment: environment)
        let duration = ControlTabPressureUITestPolicy.duration(
            environment: environment
        )
        let cooldown = ControlTabPressureUITestPolicy.cooldown(
            environment: environment
        )
        let metricsURL = URL(
            fileURLWithPath:
                environment[
                    ControlTabPressureUITestEnvironment.metricsPath
                ]
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "flowtab-control-tab-pressure-"
                            + UUID().uuidString
                            + ".csv"
                    ).path
        )
        let observer = ControlTabPressureUITestObserver()
        observer.start()
        defer { observer.cancel() }
        var metrics = ControlTabPressureMetricsRecorder(
            lane: "ready",
            scenario: scenario.name
        )
        defer { try? metrics.write(to: metricsURL) }

        let app = makeApp(
            additionalArguments: scenario.launchArguments
        )
        for item in observer.launchEnvironment {
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
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout: 10
            )
        )

        for cycle in 1...ControlTabPressureUITestPolicy
            .warmupCycles
        {
            _ = try runControlTabPressureCycle(
                observer: observer,
                scenario: scenario,
                cycle: -cycle,
                commits: false,
                capturesScreenshot: cycle == 1,
                metrics: &metrics
            )
        }

        let physicalEvidence = try assertPhysicalControlTabPressureGate(
            in: app,
            observer: observer,
            scenario: scenario
        )
        physicalEvidence.forEach {
            metrics.append($0, cycle: 0)
        }
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "physical_shortcut",
                generation: 0,
                processIdentifier: 0,
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
            cycle += 1
            _ = try runControlTabPressureCycle(
                observer: observer,
                scenario: scenario,
                cycle: cycle,
                commits: cycle.isMultiple(of: 2),
                capturesScreenshot: false,
                metrics: &metrics
            )
        } while Date().timeIntervalSince(measurementStart)
            < duration

        let cooldownBegin = try XCTUnwrap(
            observer.post("cooldownBegin")
        )
        XCTAssertGreaterThan(cooldownBegin, 0)
        metrics.mark("cooldown_start")
        let cooldownFinished = expectation(
            description: "Control+Tab cooldown exposure"
        )
        DispatchQueue.global().asyncAfter(
            deadline: .now() + cooldown
        ) {
            cooldownFinished.fulfill()
        }
        wait(
            for: [cooldownFinished],
            timeout: cooldown + 5
        )
        let cooldownEnd = try XCTUnwrap(
            observer.post("cooldownEnd")
        )
        let cooldownEvidence = try XCTUnwrap(
            observer.wait(
                sequence: cooldownEnd,
                phase: "cooldown"
            ),
            "Control+Tab cooldown evidence watchdog expired"
        )
        metrics.append(cooldownEvidence, cycle: 0)
        metrics.mark("cooldown_end")
        try metrics.write(to: metricsURL)

        XCTAssertTrue(cooldownEvidence.satisfied)
        XCTAssertTrue(cooldownEvidence.timingValid)
        XCTAssertFalse(cooldownEvidence.latePresentationObserved)
        XCTAssertGreaterThan(cycle, 0)
    }

    private func runControlTabPressureCycle(
        observer: ControlTabPressureUITestObserver,
        scenario: ControlTabPressureUITestScenario,
        cycle: Int,
        commits: Bool,
        capturesScreenshot: Bool,
        metrics: inout ControlTabPressureMetricsRecorder
    ) throws -> [ControlTabPressureUITestEvidence] {
        let opened = try postControlTabPressureAction(
            "open",
            observer: observer,
            phase: "open"
        )
        assertControlTabPressureEvidence(
            opened,
            scenario: scenario,
            expectsVisiblePanel: true
        )
        if capturesScreenshot {
            let attachment = XCTAttachment(
                screenshot: XCUIScreen.main.screenshot()
            )
            attachment.name =
                "flowtab-control-tab-ready-"
                    + scenario.name
                    + "-windowContentDraw"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let forward = try postControlTabPressureAction(
            "forward",
            observer: observer,
            phase: "forward"
        )
        let reverse = try postControlTabPressureAction(
            "reverse",
            observer: observer,
            phase: "reverse"
        )
        XCTAssertEqual(
            forward.selectedWindowIDBefore,
            opened.selectedWindowIDAfter
        )
        XCTAssertNotEqual(
            forward.selectedWindowIDAfter,
            opened.selectedWindowIDAfter
        )
        XCTAssertEqual(
            reverse.selectedWindowIDBefore,
            forward.selectedWindowIDAfter
        )
        XCTAssertEqual(
            reverse.selectedWindowIDAfter,
            opened.selectedWindowIDAfter,
            "open=\(opened.selectedWindowIDBefore)->\(opened.selectedWindowIDAfter) "
                + "forward=\(forward.selectedWindowIDBefore)->\(forward.selectedWindowIDAfter) "
                + "reverse=\(reverse.selectedWindowIDBefore)->\(reverse.selectedWindowIDAfter)"
        )

        let terminalPhase = commits ? "commit" : "cancel"
        let terminal = try postControlTabPressureAction(
            terminalPhase,
            observer: observer,
            phase: terminalPhase
        )
        XCTAssertTrue(terminal.satisfied)
        XCTAssertFalse(terminal.panelPresented)
        if commits {
            XCTAssertTrue(terminal.activationRequestIssued)
        }

        let all = [opened, forward, reverse, terminal]
        for evidence in all {
            metrics.append(evidence, cycle: cycle)
            XCTAssertTrue(
                evidence.satisfied,
                "Control+Tab phase failed: \(evidence.phase)"
            )
            XCTAssertTrue(evidence.timingValid)
            XCTAssertFalse(evidence.latePresentationObserved)
            XCTAssertFalse(evidence.watchdogExpired)
        }
        return all
    }

    func postControlTabPressureAction(
        _ action: String,
        observer: ControlTabPressureUITestObserver,
        phase: String
    ) throws -> ControlTabPressureUITestEvidence {
        let sequence = try XCTUnwrap(observer.post(action))
        let evidence = try XCTUnwrap(
            observer.wait(sequence: sequence, phase: phase),
            "Control+Tab evidence watchdog expired "
                + "phase=\(phase) sequence=\(sequence)"
        )
        assertControlTabStructuredSpanEvidence(evidence)
        return evidence
    }

    func assertControlTabPressureEvidence(
        _ evidence: ControlTabPressureUITestEvidence,
        scenario: ControlTabPressureUITestScenario,
        expectsVisiblePanel: Bool
    ) {
        XCTAssertTrue(
            evidence.satisfied,
            "phase=\(evidence.phase) watchdog=\(evidence.watchdogExpired) "
                + "panel=\(evidence.panelPresented) visible=\(evidence.userVisible) "
                + "apps=\(evidence.projectedAppCount) windows=\(evidence.selectedWindowCount) "
                + "partitionsReconciled=\(evidence.partitionsReconciled) "
                + "milestones=\(evidence.milestones)"
        )
        XCTAssertEqual(evidence.panelPresented, expectsVisiblePanel)
        XCTAssertEqual(evidence.userVisible, expectsVisiblePanel)
        XCTAssertEqual(evidence.selectedAppID, scenario.focusedAppID)
        if scenario.expectedAppCount > 0 {
            XCTAssertEqual(
                evidence.projectedAppCount,
                scenario.expectedAppCount
            )
        } else {
            XCTAssertGreaterThanOrEqual(
                evidence.projectedAppCount,
                1
            )
        }
        XCTAssertEqual(
            evidence.selectedWindowCount,
            scenario.expectedWindowCount
        )
        XCTAssertTrue(evidence.accessibilityTrusted)
        XCTAssertTrue(evidence.screenCaptureTrusted)
        XCTAssertTrue(evidence.partitionsReconciled)
        XCTAssertTrue(evidence.timingValid)
        XCTAssertFalse(evidence.latePresentationObserved)
        XCTAssertFalse(evidence.watchdogExpired)
    }

}
