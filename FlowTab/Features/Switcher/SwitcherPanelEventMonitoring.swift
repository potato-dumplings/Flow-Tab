import AppKit

@MainActor
protocol SwitcherPanelEventMonitoring: AnyObject {
    func installEventMonitors()
    func removeEventMonitors()
}

@MainActor
final class SwitcherPanelEventMonitor: SwitcherPanelEventMonitoring {
    unowned let controller: SwitcherPanelController
    init(controller: SwitcherPanelController) { self.controller = controller }
    private var keyDownMonitor: Any?
    private var localFlagsChangedMonitor: Any?
    private var localMouseMovedMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var globalFlagsChangedMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var globalMouseMovedMonitor: Any?

    func installEventMonitors() {
        removeEventMonitors()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return controller.handleKeyDown(event) ? nil : event
        }

        localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.controller.handleFlagsChanged(event)
            return nil
        }

        localMouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.controller.handlePointerMoved()
            return event
        }

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.controller.handleGlobalKeyDown(event)
            }
        }

        globalFlagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.controller.handleFlagsChanged(event)
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.controller.handleGlobalMouseDown(event)
            }
        }

        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.controller.handlePointerMoved()
            }
        }
    }

    func removeEventMonitors() {
        controller.terminatePressFeedbackCompletionOwner.cancel()
        controller.model.clearTerminateSelectedAppAnimation()
        controller.cancelPendingModifierReleaseConfirmation()
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let localFlagsChangedMonitor {
            NSEvent.removeMonitor(localFlagsChangedMonitor)
            self.localFlagsChangedMonitor = nil
        }
        if let localMouseMovedMonitor {
            NSEvent.removeMonitor(localMouseMovedMonitor)
            self.localMouseMovedMonitor = nil
        }
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }
        if let globalFlagsChangedMonitor {
            NSEvent.removeMonitor(globalFlagsChangedMonitor)
            self.globalFlagsChangedMonitor = nil
        }
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }
        if let globalMouseMovedMonitor {
            NSEvent.removeMonitor(globalMouseMovedMonitor)
            self.globalMouseMovedMonitor = nil
        }
        controller.clearDelayedWindowLayerEntryState()
        controller.cancelManualWindowLayerEntryObservation()
    }
    deinit {
        MainActor.assumeIsolated {
            for monitor in [keyDownMonitor, localFlagsChangedMonitor, localMouseMovedMonitor, globalKeyDownMonitor, globalFlagsChangedMonitor, globalMouseDownMonitor, globalMouseMovedMonitor].compactMap({ $0 }) {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
