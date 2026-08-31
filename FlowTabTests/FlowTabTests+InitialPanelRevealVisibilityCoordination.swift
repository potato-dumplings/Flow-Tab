import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testWindowPreviewGateDefersVisibilityRecoveryUntilReadyReveal() {
        let visibilityScheduler =
            ManualInitialPanelVisibilityObservationScheduler()
        let previewScheduler = ManualInitialPreviewRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.session = SwitcherSession(apps: terminateScenarioApps())
        model.previewCaptureInFlightKeys = ["preview-a"]
        let controller = SwitcherPanelController(
            model: model,
            initialPanelVisibilityObservationScheduler:
                visibilityScheduler,
            initialWindowOnlyPreviewRevealScheduler:
                previewScheduler
        )
        defer {
            controller.endPresentationSession()
            controller.panel.orderOut(nil)
        }
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []
        controller.beginPresentationSession(
            kind: .inAppWindowSwitcher,
            trigger: "window_preview_visibility_gate"
        )
        controller.prepareInitialPanelReveal(
            kind: .inAppWindowSwitcher
        )
        let visibilityGeneration =
            controller.beginInitialPresentationVisibilityTracking(
                trigger: "window_preview_visibility_gate"
            )
        let recoveryGeneration =
            controller.panelPresentationRecoveryGeneration

        controller.scheduleInitialPanelVisibilityRecovery(
            trigger: "window_preview_visibility_gate",
            initialVisibilityGeneration: visibilityGeneration
        )

        XCTAssertEqual(
            controller.panelPresentationRecoveryGeneration,
            recoveryGeneration
        )
        XCTAssertNil(controller.lastPanelVisibilityRecoveryDiagnostic)
        XCTAssertEqual(controller.panel.alphaValue, 0)

        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = [.visible]
        model.previewCaptureInFlightKeys = []
        model.onWindowOnlyPreviewPreparationChanged?()

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .visibleConfirmed(
                trigger: "window_preview_visibility_gate",
                generation: visibilityGeneration,
                reason:
                    InitialPanelVisibilityEvidenceSource
                        .windowPreviewReveal.rawValue
            )
        )
        XCTAssertTrue(previewScheduler.tokens[0].isCancelled)
    }

    @MainActor
    func testWindowPreviewDegradedRevealCompletesVisibilityReadback() {
        let visibilityScheduler =
            ManualInitialPanelVisibilityObservationScheduler()
        let previewScheduler = ManualInitialPreviewRevealScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.session = SwitcherSession(apps: terminateScenarioApps())
        model.previewCaptureInFlightKeys = ["preview-a"]
        let controller = SwitcherPanelController(
            model: model,
            initialPanelVisibilityObservationScheduler:
                visibilityScheduler,
            initialWindowOnlyPreviewRevealScheduler:
                previewScheduler
        )
        defer {
            controller.endPresentationSession()
            controller.panel.orderOut(nil)
        }
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []
        controller.beginPresentationSession(
            kind: .inAppWindowSwitcher,
            trigger: "window_preview_degraded_reveal"
        )
        controller.prepareInitialPanelReveal(
            kind: .inAppWindowSwitcher
        )
        let visibilityGeneration =
            controller.beginInitialPresentationVisibilityTracking(
                trigger: "window_preview_degraded_reveal"
            )
        controller.scheduleInitialPanelVisibilityRecovery(
            trigger: "window_preview_degraded_reveal",
            initialVisibilityGeneration: visibilityGeneration
        )

        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = [.visible]
        XCTAssertTrue(previewScheduler.fire(at: 0))

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .visibleConfirmed(
                trigger: "window_preview_degraded_reveal",
                generation: visibilityGeneration,
                reason:
                    InitialPanelVisibilityEvidenceSource
                        .windowPreviewReveal.rawValue
            )
        )
    }

    @MainActor
    func testAppContentRevealLeavesTrulyHiddenPanelForEscalation() {
        let visibilityScheduler =
            ManualInitialPanelVisibilityObservationScheduler()
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        model.session = SwitcherSession(apps: terminateScenarioApps())
        let controller = SwitcherPanelController(
            model: model,
            initialPanelVisibilityObservationScheduler:
                visibilityScheduler,
            panelVisibilityRecoveryObservationScheduler:
                recoveryScheduler,
            initialAppContentRevealScheduler:
                ManualInitialAppContentRevealScheduler()
        )
        defer {
            controller.endPresentationSession()
            controller.panel.orderOut(nil)
        }
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "app_content_hidden_after_reveal"
        )
        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )
        let visibilityGeneration =
            controller.beginInitialPresentationVisibilityTracking(
                trigger: "app_content_hidden_after_reveal"
            )
        let recoveryGeneration =
            controller.panelPresentationRecoveryGeneration
        controller.scheduleInitialPanelVisibilityRecovery(
            trigger: "app_content_hidden_after_reveal",
            initialVisibilityGeneration: visibilityGeneration
        )
        guard let renderGeneration =
                model.appLayerRenderSnapshot?.generation
        else {
            return XCTFail("Expected an app render generation")
        }

        controller.requestInitialAppContentRenderPassIfNeeded()
        controller.handleSwitcherRenderMilestone(
            SwitcherRenderMilestoneEvent(
                milestone: .appContent,
                renderGeneration: renderGeneration,
                drawnAtMilliseconds: 100
            )
        )

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertTrue(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        visibilityScheduler.fireNext()
        XCTAssertGreaterThan(
            controller.panelPresentationRecoveryGeneration,
            recoveryGeneration
        )
        XCTAssertTrue(
            controller.hasPendingPanelVisibilityRecoveryObservation
        )
    }

    @MainActor
    func testSearchPresentationKeepsExistingInitialVisibilityRecovery() {
        let defaults = UserDefaults.standard
        let previousSearchEnabled = defaults.object(
            forKey: AppPreferenceKeys.searchEnabled
        )
        defer {
            restoreUserDefaultsValue(
                previousSearchEnabled,
                forKey: AppPreferenceKeys.searchEnabled,
                userDefaults: defaults
            )
        }
        defaults.set(true, forKey: AppPreferenceKeys.searchEnabled)
        let apps = terminateScenarioApps()
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService(
                    appSwitcherApps: apps,
                    committedSearchApps: apps,
                    committedSearchReadiness:
                        .committedGenerationValidated
                )
        )
        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.enterSearchMode())
        let controller = SwitcherPanelController(
            model: model,
            initialPanelVisibilityObservationScheduler:
                ManualInitialPanelVisibilityObservationScheduler()
        )
        defer {
            controller.endPresentationSession()
            controller.panel.orderOut(nil)
        }
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []
        controller.beginPresentationSession(
            kind: .globalAppSwitcher,
            trigger: "search_visibility_recovery"
        )
        controller.prepareInitialPanelReveal(
            kind: .globalAppSwitcher
        )
        let visibilityGeneration =
            controller.beginInitialPresentationVisibilityTracking(
                trigger: "search_visibility_recovery"
            )
        let recoveryGeneration =
            controller.panelPresentationRecoveryGeneration

        controller.scheduleInitialPanelVisibilityRecovery(
            trigger: "search_visibility_recovery",
            initialVisibilityGeneration: visibilityGeneration
        )

        XCTAssertEqual(controller.panel.alphaValue, 1)
        XCTAssertGreaterThan(
            controller.panelPresentationRecoveryGeneration,
            recoveryGeneration
        )
        XCTAssertEqual(
            controller.lastPanelVisibilityRecoveryDiagnostic?.trigger,
            "search_visibility_recovery"
        )
    }
}
