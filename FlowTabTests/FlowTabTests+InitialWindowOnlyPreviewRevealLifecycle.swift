import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testInitialAppContentRenderPassDoesNotInvalidatePanelRoot() async {
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.session = SwitcherSession(apps: terminateScenarioApps())
        let controller = SwitcherPanelController(model: model)
        let contentView = RecordingInitialAppContentRootView()
        controller.panel.contentView = contentView
        controller.panel.orderFrontRegardless()
        defer {
            controller.panel.orderOut(nil)
        }
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "app_content_root_invalidation_regression"
        )
        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        contentView.resetCounts()
        let panelSettled = expectation(
            description: "panel settled before initial render pass"
        )
        DispatchQueue.main.async {
            panelSettled.fulfill()
        }
        await fulfillment(of: [panelSettled], timeout: 1)
        contentView.resetCounts()

        controller.requestInitialAppContentRenderPassIfNeeded()
        let renderPassCompleted = expectation(
            description: "initial app-content render pass"
        )
        DispatchQueue.main.async {
            renderPassCompleted.fulfill()
        }
        await fulfillment(of: [renderPassCompleted], timeout: 1)

        XCTAssertEqual(contentView.layoutCount, 0)
        XCTAssertEqual(contentView.drawCount, 0)
    }

    @MainActor
    func testStandardAppPanelRemainsTransparentUntilCurrentAppContentDraw() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.session = SwitcherSession(apps: terminateScenarioApps())
        let controller = SwitcherPanelController(
            model: model,
            initialAppContentRevealScheduler: scheduler
        )
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "app_content_reveal_regression"
        )

        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )

        XCTAssertEqual(controller.panel.alphaValue, 0)
        guard let renderGeneration =
                model.appLayerRenderSnapshot?.generation
        else {
            XCTFail("Expected an app render generation")
            return
        }
        controller.requestInitialAppContentRenderPassIfNeeded()
        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .windowContent,
                renderGeneration: renderGeneration,
                drawnAtMilliseconds: 100
            )
        )
        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .appContent,
                renderGeneration: renderGeneration &- 1,
                drawnAtMilliseconds: 101
            )
        )
        XCTAssertEqual(controller.panel.alphaValue, 0)

        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .appContent,
                renderGeneration: renderGeneration,
                drawnAtMilliseconds: 102
            )
        )

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertFalse(
            controller.initialAppContentRevealObservationOwner
                .isObserving
        )
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        controller.endPresentationSession()
    }

    @MainActor
    func testInitialAppContentGateDefersVisibilityRecoveryUntilDraw() {
        let visibilityScheduler =
            ManualInitialPanelVisibilityObservationScheduler()
        let appRevealScheduler =
            ManualInitialAppContentRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.session = SwitcherSession(apps: terminateScenarioApps())
        let controller = SwitcherPanelController(
            model: model,
            initialPanelVisibilityObservationScheduler:
                visibilityScheduler,
            initialAppContentRevealScheduler: appRevealScheduler
        )
        defer {
            controller.endPresentationSession()
            controller.panel.orderOut(nil)
        }
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "app_content_visibility_gate"
        )
        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )
        let visibilityGeneration =
            controller.beginInitialPresentationVisibilityTracking(
                trigger: "app_content_visibility_gate"
            )
        let recoveryGeneration =
            controller.panelPresentationRecoveryGeneration

        controller.scheduleInitialPanelVisibilityRecovery(
            trigger: "app_content_visibility_gate",
            initialVisibilityGeneration: visibilityGeneration
        )

        XCTAssertEqual(
            controller.panelPresentationRecoveryGeneration,
            recoveryGeneration
        )
        XCTAssertNil(controller.lastPanelVisibilityRecoveryDiagnostic)
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .presenting(
                trigger: "app_content_visibility_gate",
                generation: visibilityGeneration
            )
        )
        XCTAssertEqual(controller.panel.alphaValue, 0)
        guard let renderGeneration =
                model.appLayerRenderSnapshot?.generation
        else {
            return XCTFail("Expected an app render generation")
        }

        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = [.visible]
        controller.requestInitialAppContentRenderPassIfNeeded()
        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .appContent,
                renderGeneration: renderGeneration,
                drawnAtMilliseconds: 100
            )
        )

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .visibleConfirmed(
                trigger: "app_content_visibility_gate",
                generation: visibilityGeneration,
                reason:
                    InitialPanelVisibilityEvidenceSource
                        .appContentRenderMilestone.rawValue
            )
        )
        XCTAssertNil(controller.lastPanelVisibilityRecoveryDiagnostic)
    }

    @MainActor
    func testStandardAppPanelRunsPreparedDisplayOnceAndWaitsForDrawBeforeReveal() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.session = SwitcherSession(apps: terminateScenarioApps())
        let controller = SwitcherPanelController(
            model: model,
            initialAppContentRevealScheduler: scheduler
        )
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "app_content_prepared_display_regression"
        )
        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )
        guard let renderGeneration =
                model.appLayerRenderSnapshot?.generation
        else {
            XCTFail("Expected an app render generation")
            return
        }
        var displayCount = 0
        controller.handleSwitcherRenderPreparation(
            SwitcherRenderMilestonePreparation(
                milestone: .appContent,
                renderGeneration: renderGeneration,
                displayAction: {
                    displayCount += 1
                    return SwitcherRenderMilestoneDisplayEvidence(
                        milestone: .appContent,
                        renderGeneration: renderGeneration,
                        durationMilliseconds: 2.5,
                        completedAtMilliseconds: 300
                    )
                }
            )
        )

        controller.requestInitialAppContentRenderPassIfNeeded()
        XCTAssertEqual(scheduler.renderPassTokens.count, 1)
        XCTAssertTrue(scheduler.fireRenderPass(at: 0))
        XCTAssertEqual(displayCount, 1)
        XCTAssertEqual(controller.panel.alphaValue, 0)
        XCTAssertEqual(
            controller.initialAppContentRevealObservationOwner
                .lastRenderPassEvidence?.durationMilliseconds,
            2.5
        )

        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .appContent,
                renderGeneration: renderGeneration,
                drawnAtMilliseconds: 301
            )
        )
        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertEqual(displayCount, 1)
        controller.endPresentationSession()
    }

    @MainActor
    func testRetainedStandardAppPanelReopenDrawsCurrentAppGenerationBeforeReveal() async {
        let orderA = terminateScenarioApps()
        let orderB = [orderA[2], orderA[0], orderA[1]]
        let runtimeService = RecordingRuntimeProjectionService(
            appSwitcherApps: orderA
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeService
            )
        )
        controller.setModifierReleaseConfirmationSuppressedForTesting(
            true
        )
        defer {
            if controller.hasActivePresentationSession {
                controller.cancelSelectionForTesting()
            }
            controller.panel.orderOut(nil)
        }

        let firstDraw = expectation(
            description: "first app order draw"
        )
        var firstEvent: SwitcherRenderMilestoneEvent?
        let firstObserver = controller.addRenderMilestoneObserver {
            event in
            guard event.milestone == .appContent,
                  event.renderGeneration
                    == controller.modelForTesting
                        .appLayerRenderSnapshot?.generation,
                  controller.panel.alphaValue == 1,
                  firstEvent == nil
            else {
                return
            }
            firstEvent = event
            firstDraw.fulfill()
        }
        XCTAssertTrue(
            controller.presentGlobalHotkeySessionForTesting()
        )
        XCTAssertEqual(controller.panel.alphaValue, 0)
        await fulfillment(of: [firstDraw], timeout: 1)
        controller.removeRenderMilestoneObserver(firstObserver)
        XCTAssertEqual(
            firstEvent?.renderGeneration,
            controller.modelForTesting
                .appLayerRenderSnapshot?.generation
        )
        controller.cancelSelectionForTesting()

        runtimeService.installAppSwitcherProjection(
            apps: orderB,
            generatedAt: 20,
            projectionGeneration: 2
        )
        let secondDraw = expectation(
            description: "reordered retained app draw"
        )
        var secondEvent: SwitcherRenderMilestoneEvent?
        let secondObserver = controller.addRenderMilestoneObserver {
            event in
            guard event.milestone == .appContent,
                  event.renderGeneration
                    == controller.modelForTesting
                        .appLayerRenderSnapshot?.generation,
                  controller.panel.alphaValue == 1,
                  secondEvent == nil
            else {
                return
            }
            secondEvent = event
            secondDraw.fulfill()
        }
        XCTAssertTrue(
            controller.presentGlobalHotkeySessionForTesting()
        )
        let secondRenderGeneration = controller.modelForTesting
            .appLayerRenderSnapshot?.generation
        XCTAssertEqual(
            controller.modelForTesting.session?.apps.map(\.id),
            orderB.map(\.id)
        )
        XCTAssertEqual(controller.panel.alphaValue, 0)
        await fulfillment(of: [secondDraw], timeout: 1)
        controller.removeRenderMilestoneObserver(secondObserver)

        XCTAssertEqual(
            secondEvent?.renderGeneration,
            secondRenderGeneration
        )
        if let fallbackEvidence =
                controller.initialAppContentRevealObservationOwner
                    .lastRenderPassEvidence
        {
            XCTAssertEqual(
                fallbackEvidence.target.renderGeneration,
                secondRenderGeneration
            )
        }
    }

    @MainActor
    func testStandardAppPanelWatchdogCancelsHiddenPresentation() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.session = SwitcherSession(apps: terminateScenarioApps())
        let controller = SwitcherPanelController(
            model: model,
            initialAppContentRevealScheduler: scheduler
        )
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "app_content_watchdog_regression"
        )
        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )
        let expectedGeneration =
            model.appLayerRenderSnapshot?.generation
        let staleEvent = SwitcherRenderMilestoneEvent(
            milestone: .appContent,
            renderGeneration: (expectedGeneration ?? 1) &- 1,
            drawnAtMilliseconds: 100
        )
        controller.handleSwitcherRenderMilestone(staleEvent)

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(controller.panel.alphaValue, 0)
        XCTAssertFalse(controller.isPanelPresented)
        XCTAssertNil(model.session)
        XCTAssertEqual(
            controller.initialAppContentRevealObservationOwner
                .lastWatchdogFailure?.target.renderGeneration,
            expectedGeneration
        )
        XCTAssertEqual(
            controller.initialAppContentRevealObservationOwner
                .lastWatchdogFailure?.lastEvent,
            staleEvent
        )
    }

    @MainActor
    func testRapidStandardAppPanelReplacementRejectsPreviousRenderGeneration() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        let initialApps = terminateScenarioApps()
        model.session = SwitcherSession(apps: initialApps)
        let controller = SwitcherPanelController(
            model: model,
            initialAppContentRevealScheduler: scheduler
        )
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "app_content_first_generation"
        )
        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )
        guard let firstRenderGeneration =
                model.appLayerRenderSnapshot?.generation
        else {
            XCTFail("Expected the first app render generation")
            return
        }
        controller.requestInitialAppContentRenderPassIfNeeded()

        model.session = nil
        model.session = SwitcherSession(
            apps: [initialApps[2], initialApps[0], initialApps[1]]
        )
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "app_content_second_generation"
        )
        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )
        guard let secondRenderGeneration =
                model.appLayerRenderSnapshot?.generation
        else {
            XCTFail("Expected the second app render generation")
            return
        }
        controller.requestInitialAppContentRenderPassIfNeeded()

        XCTAssertGreaterThan(
            secondRenderGeneration,
            firstRenderGeneration
        )
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .appContent,
                renderGeneration: firstRenderGeneration,
                drawnAtMilliseconds: 100
            )
        )
        XCTAssertEqual(controller.panel.alphaValue, 0)

        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .appContent,
                renderGeneration: secondRenderGeneration,
                drawnAtMilliseconds: 101
            )
        )
        XCTAssertEqual(controller.panel.alphaValue, 1)
        controller.endPresentationSession()
    }

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

        controller.prepareInitialPanelReveal(
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
        controller.prepareInitialPanelReveal(
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
        controller.prepareInitialPanelReveal(
            kind: .inAppWindowSwitcher
        )

        controller.endPresentationSession()

        XCTAssertEqual(controller.panel.alphaValue, 0)
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
        XCTAssertEqual(controller.panel.alphaValue, 0)
    }

    @MainActor
    func testPresentationEndParksPanelForWarmReuse() {
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    RecordingRuntimeProjectionService(
                        appSwitcherApps: terminateScenarioApps()
                    )
            )
        )
        defer {
            controller.panel.orderOut(nil)
        }

        XCTAssertTrue(
            controller.presentGlobalHotkeySessionForTesting()
        )
        XCTAssertTrue(controller.panel.isVisible)

        controller.cancelSelectionForTesting()

        XCTAssertFalse(controller.isPanelPresented)
        XCTAssertTrue(controller.panel.isVisible)
        XCTAssertEqual(controller.panel.alphaValue, 0)
        XCTAssertTrue(controller.panel.ignoresMouseEvents)
        XCTAssertFalse(controller.panel.isKeyWindow)

        XCTAssertTrue(
            controller.presentGlobalHotkeySessionForTesting()
        )
        XCTAssertTrue(controller.isPanelPresented)
        XCTAssertEqual(controller.panel.alphaValue, 0)
        guard let renderGeneration =
                controller.modelForTesting
                    .appLayerRenderSnapshot?.generation
        else {
            XCTFail("Expected a reused app render generation")
            return
        }
        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .appContent,
                renderGeneration: renderGeneration,
                drawnAtMilliseconds: 100
            )
        )
        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertFalse(controller.panel.ignoresMouseEvents)

        controller.cancelSelectionForTesting()
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

private final class RecordingInitialAppContentRootView: NSView {
    private(set) var layoutCount = 0
    private(set) var drawCount = 0

    override func layout() {
        layoutCount += 1
        super.layout()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        super.draw(dirtyRect)
    }

    func resetCounts() {
        layoutCount = 0
        drawCount = 0
    }
}
