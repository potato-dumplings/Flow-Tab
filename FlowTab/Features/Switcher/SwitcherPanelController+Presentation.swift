import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension SwitcherPanelController {
    func monotonicMilliseconds() -> Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }

    func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    func logInputTrace(_ message: @autoclosure () -> String) {
        RuntimeLog.debug(.inputTrace, message())
    }

    func logSearchTrace(_ message: String) {
        RuntimeLog.debug(.searchTrace, message)
    }

    func panelFirstResponderDebugName() -> String {
        guard let firstResponder = panel.firstResponder else { return "nil" }
        return String(describing: type(of: firstResponder))
    }

    func searchTraceStateSummary() -> String {
        let searchIndexTraceFields = model.lastSearchIndexReadDiagnostic?.searchTraceFields
            ?? [
                "searchIndexReadiness=none",
                "searchIndexResultState=none",
                "searchIndexDegraded=0",
                "searchIndexCoversCurrentGeneration=0",
                "searchFreshnessBarrierRequested=0"
            ].joined(separator: " ")
        return "panelVisible=\(isPanelPresented ? 1 : 0) panelKey=\(panel.isKeyWindow ? 1 : 0) appActive=\(isAppCurrentlyActive ? 1 : 0) searchActive=\(model.isSearchActive ? 1 : 0) inputFocused=\(model.isSearchInputFocused ? 1 : 0) marked=\(model.hasMarkedSearchText ? 1 : 0) firstResponder=\(panelFirstResponderDebugName()) activeSpaceTransitionPending=\(hasPendingActiveSpaceTransitionObservation ? 1 : 0) applicationActivationSuppressed=\(isApplicationActivationSuppressedForActiveSpaceTransition ? 1 : 0) terminateProtectionPending=\(hasPendingTerminateInterruptionProtection ? 1 : 0) \(searchIndexTraceFields)"
    }

    func show(direction: CycleDirection) {
        lastPanelPresentationBreakdownDiagnostic = nil
        let showStartMs = monotonicMilliseconds()
        guard model.startSession(
            triggerDirection: direction,
            deferMaintenanceUntilFirstVisibleFrame: true
        ) else {
            let failedMs = monotonicMilliseconds() - showStartMs
            logInputTrace(
                "show kind=global result=failed durationMs=\(formatMilliseconds(failedMs))"
            )
            RuntimeLog.info(.session, "start failed: no apps")
            NSSound.beep()
            return
        }
        presentStartedHotkeySession(
            kind: .globalAppSwitcher,
            trigger: "global_show",
            logKind: "global",
            showStartMs: showStartMs,
            startLogMessage: "start direction=\(direction.debugName) \(self.model.debugSelectionSummary())"
        )
    }

    func showSearch(direction: CycleDirection) {
        let showStartMs = monotonicMilliseconds()
        guard model.startSearchSession(
            triggerDirection: direction,
            deferMaintenanceUntilFirstVisibleFrame: true
        ) else {
            let failedMs = monotonicMilliseconds() - showStartMs
            if model.pendingSearchActivationAfterFreshnessBarrier {
                logInputTrace(
                    "show kind=search result=deferred durationMs=\(formatMilliseconds(failedMs)) \(searchTraceStateSummary())"
                )
                RuntimeLog.info(.session, "start search deferred: awaiting committed search index")
                return
            }
            logInputTrace(
                "show kind=search result=failed durationMs=\(formatMilliseconds(failedMs)) \(searchTraceStateSummary())"
            )
            RuntimeLog.info(.session, "start search failed: no committed search index")
            NSSound.beep()
            return
        }
        presentStartedHotkeySession(
            kind: .globalAppSwitcher,
            trigger: "search_show",
            logKind: "search",
            showStartMs: showStartMs,
            startLogMessage: "start search direction=\(direction.debugName) \(self.model.debugSelectionSummary())"
        )
    }

    func showInAppWindowSwitcher(
        direction: CycleDirection,
        initialKeyInput: KeyInput? = nil
    ) {
        presentationCoordinator.showInAppWindowSwitcher(direction: direction, initialKeyInput: initialKeyInput)
    }

    @discardableResult
    func resolvePendingFocusedWindowSessionPresentation(
        appID: String?,
        evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence?
    ) -> Bool {
        presentationCoordinator.resolvePendingFocusedWindowSessionPresentation(appID: appID, evidence: evidence)
    }

    func cancelPendingFocusedWindowSessionPresentation(
        reason: String,
        resetsModel: Bool = true
    ) {
        presentationCoordinator.cancelPendingFocusedWindowSessionPresentation(reason: reason, resetsModel: resetsModel)
    }

    func presentStartedHotkeySession(
        kind: HotkeySessionKind,
        trigger: String,
        logKind: String,
        showStartMs: Double,
        startLogMessage: String
    ) {
        presentationCoordinator.presentStartedHotkeySession(kind: kind, trigger: trigger, logKind: logKind, showStartMs: showStartMs, startLogMessage: startLogMessage)
    }

    func updatePanelPresentationLevel(
        trigger: String,
        behaviorMode: SwitcherPanelWindowConfiguration.PresentationBehaviorMode = .allSpaces
    ) {
        panelWindowOperations.updatePanelPresentationLevel(trigger: trigger, behaviorMode: behaviorMode)
    }

    func centerPanelOnActiveScreen(preferredScreen: NSScreen? = nil) {
        panelGeometry.centerPanelOnActiveScreen(preferredScreen: preferredScreen)
    }

    func resolveActivePresentationScreen() -> NSScreen? {
        panelGeometry.resolveActivePresentationScreen()
    }

    func resolveSizingScreen(preferredScreen: NSScreen? = nil) -> NSScreen? {
        panelGeometry.resolveSizingScreen(preferredScreen: preferredScreen)
    }

    func hideNonPanelWindowsIfNeeded() {
        panelWindowOperations.hideNonPanelWindowsIfNeeded()
    }

    func hideNonPanelWindows() {
        panelWindowOperations.hideNonPanelWindows()
    }

    func endPresentationSession() {
        presentationCoordinator.endPresentationSession()
    }

    func beginPresentationSession(kind: HotkeySessionKind, trigger: String) {
        presentationCoordinator.beginPresentationSession(kind: kind, trigger: trigger)
    }

    func invalidatePresentationSessionGeneration(trigger: String) {
        presentationCoordinator.invalidatePresentationSessionGeneration(trigger: trigger)
    }

    func isPresentationSessionGenerationCurrent(_ generation: Int) -> Bool {
        generation == presentationSessionGeneration
    }

    func updatePanelSize(for preferredScreen: NSScreen? = nil) {
        panelGeometry.updatePanelSize(for: preferredScreen)
    }

    func updatePanelSize(forVisibleFrame visibleFrame: CGRect) {
        panelGeometry.updatePanelSize(forVisibleFrame: visibleFrame)
    }

    func resolvedStandardPreviewSectionHeight(panelWidth: CGFloat, itemCount: Int) -> CGFloat {
        panelGeometry.resolvedStandardPreviewSectionHeight(panelWidth: panelWidth, itemCount: itemCount)
    }

    func preferredAppStripWidth(appCount: Int, maxTileSize: CGFloat) -> CGFloat {
        panelGeometry.preferredAppStripWidth(appCount: appCount, maxTileSize: maxTileSize)
    }

    func resolvedAppLayerPanelWidth(
        preferredWidth: CGFloat,
        visibleFrameWidth: CGFloat
    ) -> CGFloat {
        panelGeometry.resolvedAppLayerPanelWidth(preferredWidth: preferredWidth, visibleFrameWidth: visibleFrameWidth)
    }

    func preferredPreviewLayerWidth(
        appCount: Int,
        windowCount: Int,
        maxPanelWidth: CGFloat
    ) -> CGFloat {
        panelGeometry.preferredPreviewLayerWidth(appCount: appCount, windowCount: windowCount, maxPanelWidth: maxPanelWidth)
    }

    func logSearchLayoutSizing(
        resultCount: Int,
        visibleRows: Int,
        measurements: SwitcherSearchLayoutMeasurements,
        listHeight: CGFloat,
        neededPanelHeight: CGFloat,
        finalPanelHeight: CGFloat,
        maxHeight: CGFloat,
        visibleFrameWidth: CGFloat,
        preferredAppStripWidth: CGFloat,
        finalPanelWidth: CGFloat
    ) {
        let summary = [
            "resultCount=\(resultCount)",
            "visibleRows=\(visibleRows)",
            "visibleFrameWidth=\(formatLayoutPoint(visibleFrameWidth))",
            "preferredAppStripWidth=\(formatLayoutPoint(preferredAppStripWidth))",
            "finalPanelWidth=\(formatLayoutPoint(finalPanelWidth))",
            "header=\(formatLayoutPoint(measurements.presentationHeaderHeight))",
            "row=\(formatLayoutPoint(measurements.resultRowHeight))",
            "listHeight=\(formatLayoutPoint(listHeight))",
            "neededPanelHeight=\(formatLayoutPoint(neededPanelHeight))",
            "finalPanelHeight=\(formatLayoutPoint(finalPanelHeight))",
            "maxHeight=\(formatLayoutPoint(maxHeight))"
        ].joined(separator: " ")
        guard lastSearchLayoutSizingLogSummary != summary else { return }
        lastSearchLayoutSizingLogSummary = summary
        RuntimeLog.debug(
            .switcherLayout,
            "searchPanelSizing \(summary)"
        )
    }

    struct AppGridLayout {
        let tileSize: CGFloat
        let spacing: CGFloat
        let columns: Int
        let rows: Int

        var gridWidth: CGFloat {
            CGFloat(columns) * tileSize + CGFloat(max(columns - 1, 0)) * spacing
        }

        var gridHeight: CGFloat {
            CGFloat(rows) * tileSize + CGFloat(max(rows - 1, 0)) * spacing
        }
    }

    func resolveAppGridLayout(
        appCount: Int,
        availableWidth: CGFloat,
        maxTileSize: CGFloat
    ) -> AppGridLayout {
        panelGeometry.resolveAppGridLayout(appCount: appCount, availableWidth: availableWidth, maxTileSize: maxTileSize)
    }
}
