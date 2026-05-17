import AppKit
import Foundation

extension SwitcherPanelController {
    func logPanelPresentationBreakdown(
        kind: String,
        showStartMs: Double,
        sessionReadyMs: Double,
        screenReadyMs: Double,
        sizeReadyMs: Double,
        centerReadyMs: Double,
        accessibilityReadyMs: Double,
        levelReadyMs: Double,
        firstOrderReadyMs: Double,
        hideReadyMs: Double,
        secondOrderReadyMs: Double,
        ignoreReadyMs: Double,
        recoveryReadyMs: Double,
        monitorReadyMs: Double,
        autoEnterReadyMs: Double
    ) {
        logInputTrace(
            "show kind=\(kind) phase=presentBreakdown "
                + "sessionMs=\(formatMilliseconds(sessionReadyMs - showStartMs)) "
                + "screenMs=\(formatMilliseconds(screenReadyMs - sessionReadyMs)) "
                + "sizeMs=\(formatMilliseconds(sizeReadyMs - screenReadyMs)) "
                + "centerMs=\(formatMilliseconds(centerReadyMs - sizeReadyMs)) "
                + "accessibilityMs=\(formatMilliseconds(accessibilityReadyMs - centerReadyMs)) "
                + "levelMs=\(formatMilliseconds(levelReadyMs - accessibilityReadyMs)) "
                + "order1Ms=\(formatMilliseconds(firstOrderReadyMs - levelReadyMs)) "
                + "hideMs=\(formatMilliseconds(hideReadyMs - firstOrderReadyMs)) "
                + "order2Ms=\(formatMilliseconds(secondOrderReadyMs - hideReadyMs)) "
                + "ignoreMs=\(formatMilliseconds(ignoreReadyMs - secondOrderReadyMs)) "
                + "recoveryScheduleMs=\(formatMilliseconds(recoveryReadyMs - ignoreReadyMs)) "
                + "monitorMs=\(formatMilliseconds(monitorReadyMs - recoveryReadyMs)) "
                + "autoEnterMs=\(formatMilliseconds(autoEnterReadyMs - monitorReadyMs)) "
                + "totalMs=\(formatMilliseconds(autoEnterReadyMs - showStartMs))"
        )
    }

    func schedulePanelVisibilityProbe(
        kind: String,
        showStartMs: Double,
        presentedMs: Double
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            let nextTurnMs = self.monotonicMilliseconds()
            self.logPanelVisibilityProbe(
                kind: kind,
                probe: "nextTurn",
                showStartMs: showStartMs,
                presentedMs: presentedMs,
                probeMs: nextTurnMs
            )

            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            let frameDelayMs = self.monotonicMilliseconds()
            self.logPanelVisibilityProbe(
                kind: kind,
                probe: "frameDelay",
                showStartMs: showStartMs,
                presentedMs: presentedMs,
                probeMs: frameDelayMs
            )
        }
    }

    private func logPanelVisibilityProbe(
        kind: String,
        probe: String,
        showStartMs: Double,
        presentedMs: Double,
        probeMs: Double
    ) {
        logInputTrace(
            "show kind=\(kind) phase=visibleProbe probe=\(probe) "
                + "elapsedMs=\(formatMilliseconds(probeMs - showStartMs)) "
                + "sincePresentedMs=\(formatMilliseconds(probeMs - presentedMs)) "
                + panelVisibilityProbeSummary()
        )
    }

    private func panelVisibilityProbeSummary() -> String {
        let occlusionVisible = resolvedPanelOcclusionState.contains(.visible) ? 1 : 0
        return "panelVisible=\(isPanelPresented ? 1 : 0) "
            + "userVisible=\(isPanelVisibleToUser ? 1 : 0) "
            + "occlusionVisible=\(occlusionVisible) "
            + "panelKey=\(panel.isKeyWindow ? 1 : 0) "
            + "appActive=\(isAppCurrentlyActive ? 1 : 0) "
            + "frame=\(formatPanelProbeRect(panel.frame)) "
            + panelContentProbeSummary()
    }

    func panelContentProbeSummary() -> String {
        guard let session = model.session else {
            return "content=empty"
        }
        let selectedWindowID = session.selectedWindow?.id ?? "none"
        return "content=ready "
            + "overlay=\(model.overlayStyle.debugName) "
            + "mode=\(session.mode.debugName) "
            + "selectedAppID=\(session.selectedApp.id) "
            + "selectedWindows=\(session.selectedApp.windows.count) "
            + "selectedWindowID=\(selectedWindowID)"
    }

    func panelVisibilitySnapshot() -> PanelVisibilitySnapshot {
        PanelVisibilitySnapshot(
            panelPresented: isPanelPresented,
            userVisible: isPanelVisibleToUser,
            occlusionVisible: resolvedPanelOcclusionState.contains(.visible),
            panelKey: panel.isKeyWindow,
            appActive: isAppCurrentlyActive,
            searchActive: model.isSearchActive,
            inputFocused: model.isSearchInputFocused,
            firstResponder: panelFirstResponderDebugName()
        )
    }

    func recordPanelVisibilityRecoveryDiagnostic(
        trigger: String,
        generation: Int?,
        attempt: Int?,
        totalAttempts: Int?,
        mode: PanelVisibilityRecoveryMode,
        before: PanelVisibilitySnapshot,
        after: PanelVisibilitySnapshot
    ) {
        let diagnostic = PanelVisibilityRecoveryDiagnostic(
            trigger: trigger,
            generation: generation,
            attempt: attempt,
            totalAttempts: totalAttempts,
            mode: mode,
            before: before,
            after: after
        )
        lastPanelVisibilityRecoveryDiagnostic = diagnostic
        logSearchTrace(diagnostic.logMessage)
    }

    private func formatPanelProbeRect(_ rect: NSRect) -> String {
        let x = formatMilliseconds(rect.origin.x)
        let y = formatMilliseconds(rect.origin.y)
        let width = formatMilliseconds(rect.size.width)
        let height = formatMilliseconds(rect.size.height)
        return "\(x),\(y),\(width),\(height)"
    }
}
