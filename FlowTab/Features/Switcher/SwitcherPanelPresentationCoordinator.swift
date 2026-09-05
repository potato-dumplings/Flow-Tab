import AppKit
import FlowTabCore

@MainActor
protocol SwitcherPanelPresenting: AnyObject {
    typealias HotkeySessionKind = SwitcherPanelController.HotkeySessionKind
    func showInAppWindowSwitcher(
        direction: CycleDirection,
        initialKeyInput: KeyInput?
    )
    func resolvePendingFocusedWindowSessionPresentation(
        appID: String?,
        evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence?
    ) -> Bool
    func cancelPendingFocusedWindowSessionPresentation(
        reason: String,
        resetsModel: Bool
    )
    func presentStartedHotkeySession(
        kind: HotkeySessionKind,
        trigger: String,
        logKind: String,
        showStartMs: Double,
        startLogMessage: String
    )
    func endPresentationSession()
    func beginPresentationSession(kind: HotkeySessionKind, trigger: String)
    func invalidatePresentationSessionGeneration(trigger: String)
}

@MainActor
final class SwitcherPanelPresentationCoordinator: SwitcherPanelPresenting {
    typealias HotkeySessionKind = SwitcherPanelController.HotkeySessionKind
    unowned let controller: SwitcherPanelController
    init(controller: SwitcherPanelController) { self.controller = controller }
}

@MainActor
final class SwitcherPanelPresentationState {
    var generation = 0
    var kind: SwitcherPanelController.HotkeySessionKind?
    var isActive = false
    var initialContentSize: NSSize?
    var pendingFocusedSession: SwitcherPanelController.PendingFocusedWindowSessionPresentation?
    var screen: NSScreen?
}
