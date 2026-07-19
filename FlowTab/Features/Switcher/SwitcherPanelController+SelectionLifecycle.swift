import Foundation

extension SwitcherPanelController {
    func finishSelection() {
        guard isPanelPresented || hasActivePresentationSession else { return }
        ignoreHotkeyPressesUntil = ProcessInfo.processInfo.systemUptime + postFinishHotkeyIgnoreWindow
        logInputTrace(
            "finishSelection nowMs=\(formatMilliseconds(monotonicMilliseconds())) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
        )
        model.commitSelection()
        endPresentationSession()
    }

    func cancelSelection(trigger: String) {
        guard isPanelPresented || hasActivePresentationSession else { return }
        let sessionKind = activeHotkeySessionKind
        endPresentationSession()
        ignoreHotkeyPressesUntil = ProcessInfo.processInfo.systemUptime + postFinishHotkeyIgnoreWindow
        logInputTrace(
            "cancelSelection trigger=\(trigger) \(primaryModifierHardwareStateSummary(for: sessionKind)) nowMs=\(formatMilliseconds(monotonicMilliseconds())) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
        )
        model.cancelSelection()
    }
}
