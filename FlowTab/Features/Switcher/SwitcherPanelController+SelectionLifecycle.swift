import Foundation

extension SwitcherPanelController {
    func finishSelection() {
        guard isPanelPresented || hasActivePresentationSession else { return }
        beginSelectionEndReplaySuppression(trigger: "finishSelection")
        logInputTrace(
            "finishSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        model.commitSelection()
        endPresentationSession()
    }

    func cancelSelection(trigger: String) {
        if pendingFocusedWindowSessionPresentation != nil {
            cancelPendingFocusedWindowSessionPresentation(
                reason: trigger
            )
            return
        }
        guard isPanelPresented || hasActivePresentationSession else { return }
        let sessionKind = activeHotkeySessionKind
        beginSelectionEndReplaySuppression(
            sessionKind: sessionKind,
            trigger: trigger
        )
        endPresentationSession()
        logInputTrace(
            "cancelSelection trigger=\(trigger) \(hotkeyHoldSetHardwareStateSummary(for: sessionKind)) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        model.cancelSelection()
        _ = panel.makeFirstResponder(nil)
    }

    private func beginSelectionEndReplaySuppression(
        sessionKind: HotkeySessionKind? = nil,
        trigger: String
    ) {
        let resolvedSessionKind = sessionKind ?? activeHotkeySessionKind
        if let resolvedSessionKind {
            beginHotkeyReplaySuppressionUntilRelease(
                for: resolvedSessionKind,
                trigger: "selection_end:\(trigger)"
            )
        } else {
            beginHotkeyReplaySuppressionUntilReleaseForKnownSessionKinds(
                trigger: "selection_end:\(trigger)"
            )
        }
    }
}
