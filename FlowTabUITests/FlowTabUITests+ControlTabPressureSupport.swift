import Carbon
import Foundation
import XCTest

extension FlowTabUITests {
    func assertControlTabStructuredSpanEvidence(
        _ evidence: ControlTabPressureUITestEvidence
    ) {
        let detail = "phase=\(evidence.phase) sequence=\(evidence.sequence)"
        XCTAssertTrue(
            evidence.requiredComponentsPresent,
            "Missing required component span: \(detail)"
        )
        XCTAssertTrue(
            evidence.timelineReconciled,
            "Exclusive timeline did not reconcile: \(detail)"
        )
        XCTAssertTrue(
            evidence.componentTimingValid,
            "Component timing or outcome is invalid: \(detail)"
        )
        XCTAssertFalse(
            evidence.spans.isEmpty,
            "No structured span evidence: \(detail)"
        )
        XCTAssertTrue(
            evidence.spans.allSatisfy {
                $0.phase == evidence.phase
                    && $0.sequence == evidence.sequence
                    && $0.timingValid
                    && $0.completedAtNanoseconds
                        >= $0.startedAtNanoseconds
            },
            "Span identity or timing mismatch: \(detail)"
        )
        XCTAssertTrue(
            evidence.spans.contains {
                $0.scope == "timeline_exclusive"
            },
            "Exclusive timeline is absent: \(detail)"
        )
    }

    func controlTabPressureMetricsURL(
        _ environment: [String: String]
    ) -> URL {
        URL(
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
    }

    func waitForControlTabSamplerReadiness(
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws -> ControlTabPressureProof {
        guard let rawPath = environment[
            ControlTabPressureUITestEnvironment.samplerReadyPath
        ], !rawPath.isEmpty else {
            return ControlTabPressureProof(
                kind: "sampler_readiness",
                generation: 0,
                processIdentifier: 0,
                windowID: "none",
                cgWindowID: 0,
                satisfied: true,
                detail: "direct-ui-run"
            )
        }

        let readinessURL = URL(fileURLWithPath: rawPath)
            .standardizedFileURL
        let deadline = Date().addingTimeInterval(
            ControlTabPressureUITestPolicy
                .samplerReadinessWatchdogSeconds
        )
        var resolved: ControlTabPressureProof?
        repeat {
            if let data = try? Data(contentsOf: readinessURL),
               let document = try? JSONSerialization.jsonObject(
                   with: data
               ) as? [String: Any],
               (document["schema_version"] as? NSNumber)?
                    .intValue == 1,
               (document["ready"] as? NSNumber)?
                    .boolValue == true,
               let processIdentifier = Int32(
                   exactly: (document["pid"] as? NSNumber)?
                       .intValue ?? 0
               ),
               processIdentifier > 0,
               let monotonicNanoseconds =
                    (document["monotonic_nanoseconds"]
                        as? NSNumber)?.uint64Value,
               monotonicNanoseconds > 0,
               document["identity_verdict"] as? String
                    == "matched"
            {
                resolved = ControlTabPressureProof(
                    kind: "sampler_readiness",
                    generation: 0,
                    processIdentifier: processIdentifier,
                    windowID: "none",
                    cgWindowID: 0,
                    satisfied: true,
                    detail:
                        "stable-pid;monotonic-ns="
                        + String(monotonicNanoseconds)
                )
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        return try XCTUnwrap(
            resolved,
            "Stable PID sampler readiness receipt was not published at "
                + readinessURL.path
        )
    }

    func applyControlTabFixtureMutation(
        _ action: SpaceFixtureWindowMutationPressureAction,
        observer: ControlTabMutationFixtureObserver,
        expectedWindowCount: Int,
        app: XCUIApplication,
        metrics: inout ControlTabPressureMetricsRecorder
    ) throws -> SpaceFixtureWindowMutationPressureEvidence {
        let diagnostics = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertFalse(
            diagnostics.isHittable,
            "Window mutation must start while the panel is closed."
        )
        let evidence = try XCTUnwrap(observer.mutate(action))
        assertControlTabFixtureMutationEvidence(
            evidence,
            expectedWindowCount: expectedWindowCount,
            app: app
        )
        let targetCGWindowID = evidence.snapshot
            .activeCGWindowIDsByPlanIndex[
                evidence.targetWindowPlanIndex
            ] ?? evidence.retiredCGWindowID
        metrics.appendProof(
            ControlTabPressureProof(
                kind: "mutation_generation",
                generation: evidence.generation,
                processIdentifier:
                    evidence.identity.processIdentifier,
                windowID:
                    "window-plan-\(evidence.targetWindowPlanIndex)",
                cgWindowID: targetCGWindowID,
                satisfied: evidence.readbackSatisfied
                    && !evidence.watchdogExpired,
                detail:
                    "action=\(action.rawValue);windows=\(expectedWindowCount)"
            )
        )
        return evidence
    }

    func assertControlTabFixtureMutationEvidence(
        _ evidence: SpaceFixtureWindowMutationPressureEvidence,
        expectedWindowCount: Int,
        app: XCUIApplication,
        expectsClosedPanel: Bool = true
    ) {
        XCTAssertTrue(evidence.readbackSatisfied)
        XCTAssertFalse(evidence.watchdogExpired)
        XCTAssertEqual(
            evidence.snapshot.activeWindowPlanIndices.count,
            expectedWindowCount
        )
        XCTAssertEqual(
            evidence.snapshot.activeWindowTitlesByPlanIndex.count,
            expectedWindowCount
        )
        XCTAssertEqual(
            evidence.snapshot.activeCGWindowIDsByPlanIndex.count,
            expectedWindowCount
        )
        if expectsClosedPanel {
            XCTAssertFalse(
                element(in: app, identifier: Identifier.switcherSummary)
                    .isHittable,
                "Fixture mutation unexpectedly presented the switcher."
            )
        }
    }

    @discardableResult
    func runControlTabRealRuntimeCycle(
        observer: ControlTabPressureUITestObserver,
        expectedAppID: String,
        expectedWindowCount: Int,
        expectedTitles: [String],
        cycle: Int,
        commits: Bool,
        app: XCUIApplication,
        screenshotName: String? = nil,
        metrics: inout ControlTabPressureMetricsRecorder
    ) throws -> [ControlTabPressureUITestEvidence] {
        let opened = try postControlTabPressureAction(
            "open",
            observer: observer,
            phase: "open"
        )
        XCTAssertTrue(
            opened.satisfied,
            "Focused open evidence failed "
                + "phase=\(opened.phase) "
                + "panel=\(opened.panelPresented) "
                + "visible=\(opened.userVisible) "
                + "app=\(opened.selectedAppID) "
                + "apps=\(opened.projectedAppCount) "
                + "windows=\(opened.selectedWindowCount) "
                + "generation=\(opened.projectionGeneration) "
                + "reconciled=\(opened.partitionsReconciled) "
                + "watchdog=\(opened.watchdogExpired)"
        )
        XCTAssertTrue(opened.panelPresented)
        XCTAssertTrue(opened.userVisible)
        XCTAssertEqual(opened.selectedAppID, expectedAppID)
        XCTAssertEqual(
            opened.selectedWindowCount,
            expectedWindowCount
        )
        XCTAssertGreaterThan(opened.projectedAppCount, 0)
        XCTAssertTrue(opened.accessibilityTrusted)
        XCTAssertTrue(opened.screenCaptureTrusted)
        XCTAssertTrue(opened.partitionsReconciled)
        XCTAssertTrue(opened.timingValid)
        XCTAssertFalse(opened.latePresentationObserved)
        XCTAssertFalse(opened.watchdogExpired)

        let diagnostics = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForSwitcherPreviewTitles(
                diagnostics,
                toExactlyMatch: expectedTitles,
                timeout: 8
            )
        )
        if let screenshotName {
            let attachment = XCTAttachment(
                screenshot: XCUIScreen.main.screenshot()
            )
            attachment.name = screenshotName
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
        XCTAssertTrue(forward.satisfied)
        XCTAssertTrue(reverse.satisfied)
        XCTAssertEqual(
            forward.selectedWindowIDBefore,
            opened.selectedWindowIDAfter
        )
        XCTAssertEqual(
            reverse.selectedWindowIDBefore,
            forward.selectedWindowIDAfter
        )
        XCTAssertEqual(
            reverse.selectedWindowIDAfter,
            opened.selectedWindowIDAfter
        )

        let terminalPhase = commits ? "commit" : "cancel"
        let terminal = try postControlTabPressureAction(
            terminalPhase,
            observer: observer,
            phase: terminalPhase
        )
        XCTAssertTrue(terminal.satisfied)
        XCTAssertFalse(terminal.panelPresented)
        XCTAssertFalse(terminal.userVisible)
        if commits {
            XCTAssertTrue(terminal.activationRequestIssued)
        }
        let evidence = [opened, forward, reverse, terminal]
        evidence.forEach {
            metrics.append($0, cycle: cycle)
            assertControlTabStructuredSpanEvidence($0)
            XCTAssertTrue($0.timingValid)
            XCTAssertFalse($0.latePresentationObserved)
            XCTAssertFalse($0.watchdogExpired)
        }
        XCTAssertTrue(
            waitForControlTabPanelToBecomeUserHidden(
                diagnostics,
                timeout: 5
            )
        )
        return evidence
    }

    func waitForControlTabPanelToBecomeUserHidden(
        _ diagnostics: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !diagnostics.isHittable {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return !diagnostics.isHittable
    }

    func pressAndReleasePhysicalControlTab(in app: XCUIApplication) {
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        // End the registered chord with Control release so Carbon observes
        // the released hold set while freshness is still pending.
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: [],
            requiresActiveProcess: false
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: [],
            requiresActiveProcess: false
        )
    }

    func pressAndHoldPhysicalControlTab(in app: XCUIApplication) {
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
    }

    func releasePhysicalControlTab(in app: XCUIApplication) {
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: [],
            requiresActiveProcess: false
        )
    }

    func controlTabPhysicalShortcutEvidenceSatisfied(
        _ evidence: [ControlTabPressureUITestEvidence]
    ) -> Bool {
        evidence.map(\.phase) == [
            "open", "forward", "reverse", "commit"
        ]
            && evidence.allSatisfy {
                $0.satisfied
                    && $0.timingValid
                    && $0.requiredComponentsPresent
                    && $0.timelineReconciled
                    && $0.componentTimingValid
                    && !$0.watchdogExpired
                    && !$0.latePresentationObserved
            }
            && evidence.last?.activationRequestIssued == true
    }

    func finishControlTabPressureCooldown(
        observer: ControlTabPressureUITestObserver,
        seconds: TimeInterval,
        metrics: inout ControlTabPressureMetricsRecorder
    ) throws {
        _ = try XCTUnwrap(observer.post("cooldownBegin"))
        metrics.mark("cooldown_start")
        let finished = expectation(
            description: "Control+Tab pressure cooldown"
        )
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: seconds + 5)
        let sequence = try XCTUnwrap(observer.post("cooldownEnd"))
        let evidence = try XCTUnwrap(
            observer.wait(sequence: sequence, phase: "cooldown")
        )
        metrics.append(evidence, cycle: 0)
        metrics.mark("cooldown_end")
        assertControlTabStructuredSpanEvidence(evidence)
        XCTAssertTrue(evidence.satisfied)
        XCTAssertTrue(evidence.timingValid)
        XCTAssertFalse(evidence.latePresentationObserved)
    }
}
