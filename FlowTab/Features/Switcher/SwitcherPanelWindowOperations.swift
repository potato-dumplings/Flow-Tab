import AppKit

@MainActor
protocol SwitcherPanelWindowOperating {
    func updatePanelPresentationLevel(
        trigger: String,
        behaviorMode: SwitcherPanelWindowConfiguration.PresentationBehaviorMode
    )
    func hideNonPanelWindowsIfNeeded()
    func hideNonPanelWindows()
    func makeKey(wasAlreadyOrdered: Bool)
    func orderFront()
    func hidePanel()
}

@MainActor
final class SwitcherPanelWindowOperations: SwitcherPanelWindowOperating {
    unowned let controller: SwitcherPanelController
    init(controller: SwitcherPanelController) { self.controller = controller }
    func makeKey(wasAlreadyOrdered: Bool) {
        if wasAlreadyOrdered { controller.panel.makeKey() }
        else { controller.panel.makeKeyAndOrderFront(nil) }
    }
    func orderFront() { controller.panel.orderFrontRegardless() }
    func hidePanel() {
        controller.panelPresentationActive = false
        controller.panel.orderOut(nil)
        controller.panel.alphaValue = 0
        controller.panel.ignoresMouseEvents = true
    }
    func updatePanelPresentationLevel(
        trigger: String,
        behaviorMode: SwitcherPanelWindowConfiguration.PresentationBehaviorMode = .allSpaces
    ) {
        let resolvedLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: runtimeProjectionHasCurrentSpaceFullscreen()
        )
        controller.panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior(
            mode: behaviorMode
        )
        controller.panel.level = resolvedLevel
    }

    func runtimeProjectionHasCurrentSpaceFullscreen() -> Bool {
        guard let projection = controller.model.runtimeProjectionService.readSpaceTopologyProjection() else {
            controller.model.runtimeProjectionService.signalSpaceTopologyChanged()
            return false
        }
        guard projection.freshness.isCompleteForScope else { return false }
        let displayID = (controller.activePresentationScreen ?? controller.resolveActivePresentationScreen())?.flowTabDisplayID
        return projection.signature.hasFullscreenWindowOnCurrentSpace(displayID: displayID)
    }

    func hideNonPanelWindowsIfNeeded() {
        guard !controller.isAppCurrentlyActive else { return }
        hideNonPanelWindows()
    }

    func hideNonPanelWindows() {
        if let hideNonPanelWindowsOverride = controller.hideNonPanelWindowsOverride {
            hideNonPanelWindowsOverride()
            return
        }
        for window in NSApp.windows {
            guard !(window is NSPanel) else { continue }
            guard window.isVisible else { continue }
            // Keep menu-bar status-item windows visible; only hide regular app windows.
            guard window.level == .normal else { continue }
            window.orderOut(nil)
        }
    }
}

private extension NSScreen {
    var flowTabDisplayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
