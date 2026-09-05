import AppKit
import Combine
import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testControlTabPressureCPUDeltaUsesUserAndSystemTime() {
        let duration = ControlTabPressureMetricRules.duration(
            startedAtNanoseconds: 1_000_000_000,
            completedAtNanoseconds: 1_100_000_000,
            startedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 200_000_000,
                systemNanoseconds: 100_000_000
            ),
            completedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 280_000_000,
                systemNanoseconds: 140_000_000
            )
        )

        XCTAssertEqual(duration.wallMilliseconds, 100)
        XCTAssertEqual(duration.cpuTimeMilliseconds, 120)
        XCTAssertEqual(duration.cpuPercent, 120)
        XCTAssertTrue(duration.isValid)
    }

    func testControlTabPressureCPUDeltaClampsRegressedClocks() {
        let duration = ControlTabPressureMetricRules.duration(
            startedAtNanoseconds: 20,
            completedAtNanoseconds: 10,
            startedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 50,
                systemNanoseconds: 30
            ),
            completedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 20,
                systemNanoseconds: 10
            )
        )

        XCTAssertEqual(duration.wallMilliseconds, 0)
        XCTAssertEqual(duration.cpuTimeMilliseconds, 0)
        XCTAssertEqual(duration.cpuPercent, 0)
        XCTAssertFalse(duration.isValid)
    }

    func testControlTabPressureCPUDeltaRejectsInvalidSnapshot() {
        let duration = ControlTabPressureMetricRules.duration(
            startedAtNanoseconds: 10,
            completedAtNanoseconds: 20,
            startedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 0,
                systemNanoseconds: 0,
                isValid: false
            ),
            completedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 10,
                systemNanoseconds: 10
            )
        )

        XCTAssertEqual(duration.wallMilliseconds, 0.00001)
        XCTAssertEqual(duration.cpuTimeMilliseconds, 0)
        XCTAssertFalse(duration.isValid)
    }

    func testControlTabPressureCommandSequenceRejectsDuplicatesAndOldValues() {
        var gate = ControlTabPressureCommandSequenceGate()

        XCTAssertTrue(gate.accept(1))
        XCTAssertFalse(gate.accept(1))
        XCTAssertFalse(gate.accept(0))
        XCTAssertTrue(gate.accept(3))
        XCTAssertFalse(gate.accept(2))
        XCTAssertEqual(gate.lastAcceptedSequence, 3)
    }

    func testControlTabPressureSequenceGateResetsForObserverLifecycle() {
        var gate = ControlTabPressureCommandSequenceGate()
        XCTAssertTrue(gate.accept(1))
        XCTAssertFalse(gate.accept(1))

        gate.reset()

        XCTAssertEqual(gate.lastAcceptedSequence, 0)
        XCTAssertTrue(gate.accept(1))
    }

    func testControlTabPressureCommandEnvelopeRequiresKnownPositiveAction() {
        let valid = Notification(
            name: Notification.Name("control-tab-test"),
            userInfo: [
                "sequence": NSNumber(value: 7),
                "action": "reverse"
            ]
        )
        let invalid = Notification(
            name: Notification.Name("control-tab-test"),
            userInfo: [
                "sequence": NSNumber(value: 0),
                "action": "unknown"
            ]
        )

        let envelope = ControlTabPressureCommandEnvelope(
            notification: valid
        )
        XCTAssertEqual(envelope?.sequence, 7)
        XCTAssertEqual(envelope?.action, .reverse)
        XCTAssertNil(
            ControlTabPressureCommandEnvelope(
                notification: invalid
            )
        )
    }

    func testControlTabPressureRouteRequiresAllAcknowledgedChannels() {
        let complete = [
            ControlTabPressureRoute.commandEnvironmentKey: "command",
            ControlTabPressureRoute
                .commandAcknowledgementEnvironmentKey: "command-ack",
            ControlTabPressureRoute.evidenceEnvironmentKey: "evidence",
            ControlTabPressureRoute
                .evidenceAcknowledgementEnvironmentKey: "evidence-ack"
        ]

        XCTAssertNotNil(
            ControlTabPressureRoute(environment: complete)
        )
        XCTAssertNil(
            ControlTabPressureRoute(
                environment: complete.filter {
                    $0.key
                        != ControlTabPressureRoute
                            .evidenceAcknowledgementEnvironmentKey
                }
            )
        )
    }

    func testFocusedWindowDiagnosticKeepsPartitionsAndMilestonesSeparate() {
        let reconciled = FocusedWindowSessionDiagnostic(
            generation: 1,
            startedAtMilliseconds: 100,
            presentationSessionGeneration: 7,
            result: "ready",
            appID: "fixture",
            windowCount: 5,
            partitions: [
                "invalidation_ms": 1,
                "projection_read_ms": 1,
                "freshness_wait_ms": 1,
                "recency_ms": 1,
                "session_build_ms": 1,
                "session_publish_ms": 1,
                "preview_prewarm_ms": 1,
                "screen_resolve_ms": 1,
                "panel_size_ms": 1,
                "panel_center_ms": 1,
                "accessibility_ms": 1,
                "panel_presentation_ms": 1,
                "unattributed_ms": 1
            ],
            milestones: [
                "session_ready_ms": 6,
                "panel_presented_ms": 13,
                "first_window_content_draw_ms": 15,
                "visibility_readback_ms": 16,
                "first_visible_frame_ms": 16
            ]
        )
        var overcounted = reconciled
        overcounted.partitions["preview_prewarm_ms"] = 2
        var missingPartition = reconciled
        missingPartition.partitions.removeValue(
            forKey: "freshness_wait_ms"
        )
        var inconsistentFrame = reconciled
        inconsistentFrame.milestones["first_visible_frame_ms"] = 17
        var drawDuringPresentationCompletion = reconciled
        drawDuringPresentationCompletion.milestones[
            "first_window_content_draw_ms"
        ] = 12
        drawDuringPresentationCompletion.milestones[
            "visibility_readback_ms"
        ] = 11
        drawDuringPresentationCompletion.milestones[
            "first_visible_frame_ms"
        ] = 12

        XCTAssertEqual(
            reconciled.partitionTotalMilliseconds,
            13
        )
        XCTAssertTrue(reconciled.reconciles)
        XCTAssertFalse(overcounted.reconciles)
        XCTAssertFalse(missingPartition.reconciles)
        XCTAssertFalse(inconsistentFrame.reconciles)
        XCTAssertTrue(drawDuringPresentationCompletion.reconciles)
    }

    func testControlTabPressureLifecyclePhasesRemainStable() {
        XCTAssertEqual(
            ControlTabPressurePhase.allCases.map(\.rawValue),
            [
                "open",
                "forward",
                "reverse",
                "commit",
                "cancel",
                "cooldown"
            ]
        )
    }



    func testControlTabCommandsUseExpectedObservationStrategies() {
        let expectations: [(
            ControlTabPressureCommandAction,
            ControlTabPressurePhase,
            ControlTabPressureObservationStrategy
        )] = [
            (.open, .open, .firstVisibleFrame),
            (.forward, .forward, .externalStateReadback),
            (.reverse, .reverse, .externalStateReadback),
            (.commit, .commit, .externalStateReadback),
            (.cancel, .cancel, .externalStateReadback),
            (.physicalOpen, .open, .externalStateReadback),
            (.physicalForward, .forward, .externalStateReadback),
            (.physicalReverse, .reverse, .externalStateReadback),
            (.physicalCommit, .commit, .externalStateReadback),
            (
                .physicalCancel,
                .cancel,
                .cancelledPresentationReadback
            )
        ]

        for (action, phase, strategy) in expectations {
            XCTAssertEqual(action.phase, phase)
            XCTAssertEqual(action.observationStrategy, strategy)
        }
    }

    func testPhysicalCancelAllowsCachedFirstFramePresentation() {
        XCTAssertFalse(
            ControlTabPressureEventObservation
                .cancelledPresentationIsLate(
                    panelWasPresented: false,
                    presentationGenerationBefore: 8,
                    observedPresentationGeneration: 9
                )
        )
        XCTAssertTrue(
            ControlTabPressureEventObservation
                .cancelledPresentationIsLate(
                    panelWasPresented: false,
                    presentationGenerationBefore: 8,
                    observedPresentationGeneration: 11
                )
        )
    }

    func testPhysicalCancelUsesGenerationCapturedByFirstVisibleFrame() {
        let observedGeneration = ControlTabPressureEventObservation
            .observedPresentationGeneration(
                diagnosticGeneration: 9,
                currentGeneration: 10
            )

        XCTAssertEqual(observedGeneration, 9)
        XCTAssertFalse(
            ControlTabPressureEventObservation
                .cancelledPresentationIsLate(
                    panelWasPresented: false,
                    presentationGenerationBefore: 8,
                    observedPresentationGeneration:
                        observedGeneration
                )
        )
    }

    func testPhysicalCancelAllowsCurrentVisiblePresentationOnly() {
        XCTAssertFalse(
            ControlTabPressureEventObservation
                .cancelledPresentationIsLate(
                    panelWasPresented: true,
                    presentationGenerationBefore: 9,
                    observedPresentationGeneration: 9
                )
        )
        XCTAssertTrue(
            ControlTabPressureEventObservation
                .cancelledPresentationIsLate(
                    panelWasPresented: true,
                    presentationGenerationBefore: 9,
                    observedPresentationGeneration: 11
                )
        )
    }

    func testControlTabOpenRenderMilestonesSeparateFirstFrameAndFreshDraw() {
        let firstFrame = ControlTabPressureEventObservation
            .openRenderMilestoneDisposition(
                eventGeneration: 8,
                renderGenerationBefore: 7,
                expectedRenderGeneration: 9,
                currentRenderGeneration: 9,
                previewPreparationSucceeded: false,
                firstRenderObserved: false
            )
        let freshDraw = ControlTabPressureEventObservation
            .openRenderMilestoneDisposition(
                eventGeneration: 9,
                renderGenerationBefore: 7,
                expectedRenderGeneration: 8,
                currentRenderGeneration: 9,
                previewPreparationSucceeded: true,
                firstRenderObserved: true
            )

        XCTAssertEqual(firstFrame, .firstFrame)
        XCTAssertEqual(freshDraw, .freshPreviews)
    }

    func testControlTabOpenRenderMilestoneCanCompleteBothBoundaries() {
        XCTAssertEqual(
            ControlTabPressureEventObservation
                .openRenderMilestoneDisposition(
                    eventGeneration: 8,
                    renderGenerationBefore: 7,
                    expectedRenderGeneration: 8,
                    currentRenderGeneration: 8,
                    previewPreparationSucceeded: true,
                    firstRenderObserved: false
                ),
            .firstFrameAndFreshPreviews
        )
    }

    func testControlTabRenderMilestoneUsesDisplayTimeCPUSnapshot() {
        var fallbackWasRead = false
        let event = ControlTabPressureRenderEvent(
            milestone: .windowContent,
            renderGeneration: 8,
            drawnAtMilliseconds: 12,
            processCPUSnapshot: RuntimeProcessCPUSnapshot(
                userNanoseconds: 4_000_000,
                systemNanoseconds: 2_000_000,
                isValid: true
            ),
            identity: .init(presentationGeneration: 0, selectedWindowID: nil, previewVersion: 8)
        )

        let result = ControlTabPressureEventObservation
            .processCPUSnapshot(
                for: event,
                fallback: {
                    fallbackWasRead = true
                    return ControlTabProcessCPUSnapshot(
                        userNanoseconds: 40_000_000,
                        systemNanoseconds: 20_000_000
                    )
                }()
            )

        XCTAssertEqual(result.userNanoseconds, 4_000_000)
        XCTAssertEqual(result.systemNanoseconds, 2_000_000)
        XCTAssertFalse(fallbackWasRead)
    }

    func testControlTabRenderDependentReadbackWaitsForMatchingDraw() {
        for phase in [
            ControlTabPressurePhase.open,
            .forward,
            .reverse
        ] {
            XCTAssertFalse(
                ControlTabPressureEventObservation
                    .stateReadbackCanStart(
                        phase: phase,
                        matchingRenderObserved: false
                    )
            )
            XCTAssertTrue(
                ControlTabPressureEventObservation
                    .stateReadbackCanStart(
                        phase: phase,
                        matchingRenderObserved: true
                    )
            )
        }
        for phase in [
            ControlTabPressurePhase.commit,
            .cancel
        ] {
            XCTAssertTrue(
                ControlTabPressureEventObservation
                    .stateReadbackCanStart(
                        phase: phase,
                        matchingRenderObserved: false
                    )
            )
        }
        XCTAssertFalse(
            ControlTabPressureEventObservation
                .stateReadbackCanStart(
                    phase: .cooldown,
                    matchingRenderObserved: true
                )
        )
    }

    func testControlTabStateReadbackWaitsForCommandReturnBeforeFinishing() {
        XCTAssertFalse(
            ControlTabPressureEventObservation
                .stateReadbackCanFinish(
                    commandReturnedAtNanoseconds: nil
                )
        )
        XCTAssertTrue(
            ControlTabPressureEventObservation
                .stateReadbackCanFinish(
                    commandReturnedAtNanoseconds: 1
                )
        )
    }

    func testWindowMutationPressureCommandRequiresStrictFields() {
        let valid = Notification(
            name: Notification.Name("window-mutation"),
            userInfo: [
                "sequence": NSNumber(value: 2),
                "generation": NSNumber(value: 4),
                "action": "close",
                "targetWindowPlanIndex": NSNumber(value: 3)
            ]
        )
        let command = SpaceFixtureWindowMutationPressureCommand(
            notification: valid
        )

        XCTAssertEqual(command?.sequence, 2)
        XCTAssertEqual(command?.generation, 4)
        XCTAssertEqual(command?.action, .close)
        XCTAssertEqual(command?.targetWindowPlanIndex, 3)
        XCTAssertNil(
            SpaceFixtureWindowMutationPressureCommand(
                notification: Notification(
                    name: valid.name,
                    userInfo: [
                        "sequence": NSNumber(value: 3),
                        "generation": NSNumber(value: 0),
                        "action": "open",
                        "targetWindowPlanIndex": NSNumber(value: 3)
                    ]
                )
            )
        )
    }

    func testWindowMutationPressureGenerationGateRejectsReplayAndSkew() {
        var gate = SpaceFixtureWindowMutationPressureGenerationGate()

        XCTAssertTrue(gate.accepts(sequence: 1, generation: 1))
        XCTAssertFalse(gate.accepts(sequence: 1, generation: 2))
        XCTAssertFalse(gate.accepts(sequence: 2, generation: 1))
        XCTAssertTrue(gate.accepts(sequence: 3, generation: 4))
        XCTAssertFalse(gate.accepts(sequence: 4, generation: 3))
        XCTAssertEqual(gate.latestSequence, 3)
        XCTAssertEqual(gate.latestGeneration, 4)
    }
}

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testControlTabPressureRetainsTransparentDrawUntilVisibleReadback() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let model = LiveSwitcherModel(
            runtimeProjectionService: makeCurrentAppWindowProjectionService(
                appID: appID,
                runningApp: currentApp,
                windows: manyWindowLayoutApp(windowCount: 2).windows
            )
        )
        XCTAssertEqual(
            model.startFocusedAppWindowSession(triggerDirection: .forward),
            .ready
        )
        let controller = SwitcherPanelController(
            model: model,
            initialWindowOnlyPreviewRevealScheduler: ManualInitialPreviewRevealScheduler()
        )
        defer {
            controller.endPresentationSession()
            model.cancelSelection()
            controller.panel.orderOut(nil)
        }
        controller.panelVisibilityOverride = true
        controller.beginFocusedWindowSessionDiagnostic(
            showStartMilliseconds: controller.monotonicMilliseconds()
        )
        controller.beginPresentationSession(
            kind: .inAppWindowSwitcher,
            trigger: "pressure_transparent_draw"
        )
        model.previewCaptureInFlightKeys = ["pending"]
        controller.prepareInitialPanelReveal(kind: .inAppWindowSwitcher)
        _ = controller.beginInitialPresentationVisibilityTracking(
            trigger: "pressure_transparent_draw"
        )
        let visibility = ControlTabPressurePanelVisibilityObservation(controller: controller)
        defer { visibility.cancel() }
        var observed: [ControlTabPressureRenderEvent] = []
        let observer = controller.addPressureRenderMilestoneObserver {
            observed.append($0)
        }
        defer { controller.removePressureRenderMilestoneObserver(observer) }
        let event = ControlTabPressureRenderEvent(
            milestone: .windowContent,
            renderGeneration: model.windowContentRenderGeneration,
            drawnAtMilliseconds: controller.monotonicMilliseconds(),
            identity: controller.pressureDrawIdentity
        )

        controller.handlePressureRenderMilestone(event)
        XCTAssertEqual(controller.panel.alphaValue, 0)
        XCTAssertTrue(observed.isEmpty)
        XCTAssertNil(controller.lastFocusedWindowSessionDiagnostic?.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey.firstVisibleFrame
        ])

        model.previewCaptureInFlightKeys = []
        model.onWindowOnlyPreviewPreparationChanged?()

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertEqual(observed, [event])
        XCTAssertNotNil(controller.lastFocusedWindowSessionDiagnostic?.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey.firstVisibleFrame
        ])
        controller.deliverPressureRenderMilestoneIfVisible()
        XCTAssertEqual(observed.count, 1)
    }

    @MainActor
    func testControlTabPreviewReadinessRequiresSuccessfulSynchronousCapture() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let windows = manyWindowLayoutApp(windowCount: 2).windows
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
        )
        model.previewCaptureOverride = { _, _, _, _ in
            (
                image: self.makeColorImage(color: .systemBlue),
                resolvedWindowID: 1,
                titleBarStyle: nil
            )
        }

        XCTAssertEqual(
            model.startFocusedAppWindowSession(
                triggerDirection: .forward
            ),
            .ready
        )
        defer { model.cancelSelection() }
        _ = model.prewarmWindowOnlySessionPreviews()

        XCTAssertTrue(model.windowOnlyPreviewPreparationSucceeded)
    }

    @MainActor
    func testControlTabPreviewReadinessRejectsFailedCapture() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let windows = manyWindowLayoutApp(windowCount: 2).windows
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
        )
        model.previewCaptureOverride = { _, _, _, _ in nil }

        XCTAssertEqual(
            model.startFocusedAppWindowSession(
                triggerDirection: .forward
            ),
            .ready
        )
        defer { model.cancelSelection() }
        _ = model.prewarmWindowOnlySessionPreviews()

        XCTAssertFalse(model.windowOnlyPreviewPreparationSucceeded)
    }

    @MainActor
    func testControlTabPreviewReadinessWaitsForAsynchronousCapture() async {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let windows = manyWindowLayoutApp(windowCount: 2).windows
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
        )
        let batchStarted = expectation(
            description: "Control+Tab preview capture started"
        )
        let batchReleased = DispatchSemaphore(value: 0)
        defer { batchReleased.signal() }
        let image = makeColorImage(color: .systemPurple)
        model.previewCaptureBatchOverride = { requests in
            batchStarted.fulfill()
            batchReleased.wait()
            return requests.enumerated().map { index, _ in
                RuntimeWindowPreviewProvider.CaptureResult(
                    image: image,
                    resolvedWindowID: CGWindowID(index + 1),
                    titleBarStyle: nil
                )
            }
        }

        XCTAssertEqual(
            model.startFocusedAppWindowSession(
                triggerDirection: .forward
            ),
            .ready
        )
        defer { model.cancelSelection() }
        let ready = expectation(
            description: "Control+Tab preview capture applied"
        )
        var didObserveReady = false
        var cancellables: Set<AnyCancellable> = []
        model.objectWillChange.sink {
            guard model.windowOnlyPreviewPreparationSucceeded,
                  !didObserveReady
            else {
                return
            }
            didObserveReady = true
            ready.fulfill()
        }.store(in: &cancellables)
        defer { cancellables.removeAll() }

        _ = model.prewarmWindowOnlySessionPreviews()
        XCTAssertFalse(model.windowOnlyPreviewPreparationSucceeded)
        await fulfillment(of: [batchStarted], timeout: 2)
        batchReleased.signal()
        await fulfillment(of: [ready], timeout: 2)

        XCTAssertTrue(model.windowOnlyPreviewPreparationSucceeded)
    }


}
