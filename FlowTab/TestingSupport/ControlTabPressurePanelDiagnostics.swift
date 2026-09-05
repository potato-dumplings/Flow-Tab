#if FLOWTAB_TESTING
import AppKit
import Foundation

struct SwitcherPresentationMilestoneReceipt: Equatable {
    let generation: UInt64
    let recordedAtUptimeNanoseconds: UInt64

    static let empty = SwitcherPresentationMilestoneReceipt(
        generation: 0, recordedAtUptimeNanoseconds: 0
    )
}

@MainActor
final class ControlTabPressurePanelDiagnostics {
    var reusableShellGeneration: UInt64 = 0
    var completedReusableShellGeneration: UInt64 = 0
    var panelHidden: SwitcherPresentationMilestoneReceipt = .empty
    var cleanupComplete: SwitcherPresentationMilestoneReceipt = .empty
    var focusedSessionGeneration = 0
    var lastFocusedSession: FocusedWindowSessionDiagnostic?
    var firstVisibleFrameObservers: [UUID: (FocusedWindowSessionDiagnostic) -> Void] = [:]
    var renderObservers: [UUID: (ControlTabPressureRenderEvent) -> Void] = [:]
    var pendingRenderEvent: ControlTabPressureRenderEvent?
    var lastObservedRenderGeneration: UInt64?
}

extension SwitcherPanelController {
    var reusableShellPreparationGeneration: UInt64 {
        get { controlTabPressureDiagnostics.reusableShellGeneration }
        set { controlTabPressureDiagnostics.reusableShellGeneration = newValue }
    }
    var completedReusableShellPreparationGeneration: UInt64 {
        get { controlTabPressureDiagnostics.completedReusableShellGeneration }
        set { controlTabPressureDiagnostics.completedReusableShellGeneration = newValue }
    }
    var panelHiddenReceipt: SwitcherPresentationMilestoneReceipt {
        controlTabPressureDiagnostics.panelHidden
    }
    var cleanupCompleteReceipt: SwitcherPresentationMilestoneReceipt {
        controlTabPressureDiagnostics.cleanupComplete
    }
    var focusedWindowSessionDiagnosticGeneration: Int {
        get { controlTabPressureDiagnostics.focusedSessionGeneration }
        set { controlTabPressureDiagnostics.focusedSessionGeneration = newValue }
    }
    var lastFocusedWindowSessionDiagnostic: FocusedWindowSessionDiagnostic? {
        get { controlTabPressureDiagnostics.lastFocusedSession }
        set { controlTabPressureDiagnostics.lastFocusedSession = newValue }
    }
    var focusedWindowFirstVisibleFrameObservers: [UUID: (FocusedWindowSessionDiagnostic) -> Void] {
        get { controlTabPressureDiagnostics.firstVisibleFrameObservers }
        set { controlTabPressureDiagnostics.firstVisibleFrameObservers = newValue }
    }

    func recordPanelHiddenMilestone() {
        controlTabPressureDiagnostics.pendingRenderEvent = nil
        controlTabPressureDiagnostics.panelHidden = .init(
            generation: panelHiddenReceipt.generation &+ 1,
            recordedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    func recordCleanupCompleteMilestone() {
        controlTabPressureDiagnostics.cleanupComplete = .init(
            generation: cleanupCompleteReceipt.generation &+ 1,
            recordedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    func addPressureRenderMilestoneObserver(_ observer: @escaping (ControlTabPressureRenderEvent) -> Void) -> UUID {
        let id = UUID()
        controlTabPressureDiagnostics.renderObservers[id] = observer
        return id
    }

    func removePressureRenderMilestoneObserver(_ id: UUID) {
        controlTabPressureDiagnostics.renderObservers[id] = nil
    }

    func handlePressureRenderMilestone(_ event: ControlTabPressureRenderEvent) {
        guard model.isWindowOnlyOverlay,
              event.renderGeneration == model.windowContentRenderGeneration,
              event.identity == pressureDrawIdentity else { return }
        controlTabPressureDiagnostics.lastObservedRenderGeneration = event.renderGeneration
        controlTabPressureDiagnostics.pendingRenderEvent = event
        deliverPressureRenderMilestoneIfVisible()
    }

    func deliverPressureRenderMilestoneIfVisible() {
        guard isPanelPresented, isPanelVisibleToUser,
              model.isWindowOnlyOverlay,
              let event = controlTabPressureDiagnostics.pendingRenderEvent,
              event.renderGeneration == model.windowContentRenderGeneration,
              event.identity == pressureDrawIdentity else { return }
        controlTabPressureDiagnostics.pendingRenderEvent = nil
        if lastFocusedWindowSessionDiagnostic?.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey.firstVisibleFrame
        ] == nil {
            recordFocusedWindowFirstVisibleFrame(
                renderEvent: event,
                visibleAtMilliseconds: monotonicMilliseconds()
            )
        }
        recordFreshVisiblePreviewsComplete(renderEvent: event)
        for observer in controlTabPressureDiagnostics.renderObservers.values {
            observer(event)
        }
    }
}
#endif
