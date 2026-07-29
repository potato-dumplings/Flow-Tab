import AppKit
import Foundation

struct PanelVisibilitySnapshot: Equatable {
    let panelPresented: Bool
    let userVisible: Bool
    let occlusionVisible: Bool
    let panelKey: Bool
    let appActive: Bool
    let searchActive: Bool
    let inputFocused: Bool
    let firstResponder: String

    var logFields: String {
        "panelVisible=\(panelPresented ? 1 : 0) "
            + "userVisible=\(userVisible ? 1 : 0) "
            + "occlusionVisible=\(occlusionVisible ? 1 : 0) "
            + "panelKey=\(panelKey ? 1 : 0) "
            + "appActive=\(appActive ? 1 : 0) "
            + "searchActive=\(searchActive ? 1 : 0) "
            + "inputFocused=\(inputFocused ? 1 : 0) "
            + "firstResponder=\(firstResponder)"
    }
}

struct PanelVisibilityRecoveryDiagnostic: Equatable {
    let trigger: String
    let generation: Int?
    let attempt: Int?
    let totalAttempts: Int?
    let mode: SwitcherPanelController.PanelVisibilityRecoveryMode
    let before: PanelVisibilitySnapshot
    let after: PanelVisibilitySnapshot

    var logMessage: String {
        var fields = [
            "presentationRecovery",
            "trigger=\(trigger)",
            "action=visibilityReadback",
            "mode=\(mode.debugName)",
            "generation=\(generation.map(String.init) ?? "nil")"
        ]
        if let attempt, let totalAttempts {
            fields.append("attempt=\(attempt)/\(totalAttempts)")
        }
        fields.append("before{\(before.logFields)}")
        fields.append("after{\(after.logFields)}")
        return fields.joined(separator: " ")
    }
}

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
                + "recoveryScheduleMs=\(formatMilliseconds(recoveryReadyMs - secondOrderReadyMs)) "
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
        let presentationGeneration = presentationSessionGeneration
        panelPresentationDiagnosticProbeOwner.start(
            presentationGeneration: presentationGeneration,
            kind: kind,
            showStartMs: showStartMs,
            presentedMs: presentedMs,
            now: { [weak self] in
                self?.monotonicMilliseconds() ?? presentedMs
            },
            onProbe: { [weak self] probe in
                guard let self,
                      self.isPresentationSessionGenerationCurrent(
                        probe.presentationGeneration
                      )
                else {
                    return
                }
                self.logPanelVisibilityProbe(probe)
            }
        )
    }

    private func logPanelVisibilityProbe(
        _ probe: PanelPresentationDiagnosticProbe
    ) {
        logInputTrace(
            "show kind=\(probe.kind) phase=visibleProbe probe=\(probe.source.rawValue) "
                + "elapsedMs=\(formatMilliseconds(probe.elapsedMs)) "
                + "sincePresentedMs=\(formatMilliseconds(probe.sincePresentedMs)) "
                + panelVisibilityProbeSummary()
        )
    }

    func cancelPanelVisibilityProbe() {
        panelPresentationDiagnosticProbeOwner.cancel()
    }

    var lastPanelPresentationDiagnosticProbe:
        PanelPresentationDiagnosticProbe?
    {
        panelPresentationDiagnosticProbeOwner.lastProbe
    }

    var hasPendingPanelPresentationDiagnosticProbe: Bool {
        panelPresentationDiagnosticProbeOwner.isPending
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
