import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testControllerRevealsInitialWindowOnlyPanelFromPreviewBatchEvidence() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.previewCaptureInFlightKeys = ["preview-a", "preview-b"]
        let controller = SwitcherPanelController(
            model: model,
            initialWindowOnlyPreviewRevealScheduler: scheduler
        )
        controller.panelVisibilityOverride = true
        controller.beginPresentationSession(
            kind: .inAppWindowSwitcher,
            trigger: "preview_reveal_test"
        )

        controller.prepareInitialWindowOnlyPanelReveal(
            kind: .inAppWindowSwitcher
        )

        XCTAssertEqual(controller.panel.alphaValue, 0)
        XCTAssertTrue(
            controller
                .initialWindowOnlyPreviewRevealObservationOwner
                .isObserving
        )
        model.previewCaptureInFlightKeys = []
        model.onWindowOnlyPreviewPreparationChanged?()

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertFalse(
            controller
                .initialWindowOnlyPreviewRevealObservationOwner
                .isObserving
        )
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertNil(
            controller
                .initialWindowOnlyPreviewRevealObservationOwner
                .lastWatchdogFailure
        )
        controller.endPresentationSession()
    }

    @MainActor
    func testControllerDegradedPreviewRevealRecordsWatchdogReadbacks() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.previewCaptureInFlightKeys = ["preview-a", "preview-b"]
        let controller = SwitcherPanelController(
            model: model,
            initialWindowOnlyPreviewRevealScheduler: scheduler
        )
        controller.panelVisibilityOverride = true
        controller.beginPresentationSession(
            kind: .inAppWindowSwitcher,
            trigger: "preview_watchdog_test"
        )
        controller.prepareInitialWindowOnlyPanelReveal(
            kind: .inAppWindowSwitcher
        )
        model.previewCaptureInFlightKeys = ["preview-b"]
        model.onWindowOnlyPreviewPreparationChanged?()

        XCTAssertTrue(scheduler.fire(at: 0))

        let failure =
            controller
                .initialWindowOnlyPreviewRevealObservationOwner
                .lastWatchdogFailure
        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertEqual(
            failure?.lastEventEvidence.snapshot.pendingCaptureCount,
            1
        )
        XCTAssertEqual(
            failure?.finalEvidence.snapshot.pendingCaptureCount,
            1
        )
        XCTAssertEqual(
            failure?.finalEvidence.source,
            .watchdogReadback
        )
        controller.endPresentationSession()
    }

    @MainActor
    func testPresentationEndCancelsInitialPreviewRevealAndRejectsLateWatchdog() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.previewCaptureInFlightKeys = ["preview-a"]
        let controller = SwitcherPanelController(
            model: model,
            initialWindowOnlyPreviewRevealScheduler: scheduler
        )
        controller.panelVisibilityOverride = true
        controller.beginPresentationSession(
            kind: .inAppWindowSwitcher,
            trigger: "preview_cancel_test"
        )
        controller.prepareInitialWindowOnlyPanelReveal(
            kind: .inAppWindowSwitcher
        )

        controller.endPresentationSession()

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertFalse(
            controller
                .initialWindowOnlyPreviewRevealObservationOwner
                .isObserving
        )
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertNil(
            controller
                .initialWindowOnlyPreviewRevealObservationOwner
                .lastWatchdogFailure
        )
        XCTAssertEqual(controller.panel.alphaValue, 1)
    }

    @MainActor
    func testInitialPreviewRevealPressurePreservesReadinessOracleAndCancellation() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let owner = InitialWindowOnlyPreviewRevealObservationOwner(
            scheduler: scheduler
        )
        var pendingCaptureCount = 1
        var readyGenerations: [Int] = []
        let cycleCount = 500

        for cycle in 0..<cycleCount {
            pendingCaptureCount = 1
            let generation = owner.start(
                presentationGeneration: cycle,
                readback: {
                    InitialWindowOnlyPreviewReadinessSnapshot(
                        pendingCaptureCount: pendingCaptureCount
                    )
                },
                onReady: {
                    readyGenerations.append(
                        $0.observationGeneration
                    )
                },
                onWatchdog: { _ in
                    XCTFail("Unexpected watchdog")
                }
            )
            if cycle.isMultiple(of: 2) {
                owner.cancel()
            } else {
                pendingCaptureCount = 0
                XCTAssertTrue(
                    owner.observe(
                        source: .previewBatchCompleted,
                        observationGeneration: generation,
                        presentationGeneration: cycle
                    )
                )
            }
            XCTAssertTrue(
                scheduler.fire(
                    at: cycle,
                    includingCancelled: true
                )
            )
        }

        XCTAssertEqual(readyGenerations.count, cycleCount / 2)
        XCTAssertEqual(readyGenerations, readyGenerations.sorted())
        XCTAssertFalse(owner.isObserving)
        XCTAssertNil(owner.lastWatchdogFailure)
    }
}
