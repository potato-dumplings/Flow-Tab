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

    func logInputTrace(_ message: String) {
        RuntimeLog.info("InputTrace", message)
    }

    func logSearchTrace(_ message: String) {
        RuntimeDiagnostics.shared.log(level: .info, category: "SearchTrace", message: message)
    }

    func panelFirstResponderDebugName() -> String {
        guard let firstResponder = panel.firstResponder else { return "nil" }
        return String(describing: type(of: firstResponder))
    }

    func searchTraceStateSummary() -> String {
        let now = ProcessInfo.processInfo.systemUptime
        let activeSpaceIgnoreMs = max(0, (ignoreActiveSpaceChangesUntil - now) * 1_000)
        return "panelVisible=\(isPanelPresented ? 1 : 0) panelKey=\(panel.isKeyWindow ? 1 : 0) appActive=\(isAppCurrentlyActive ? 1 : 0) searchActive=\(model.isSearchActive ? 1 : 0) inputFocused=\(model.isSearchInputFocused ? 1 : 0) marked=\(model.hasMarkedSearchText ? 1 : 0) firstResponder=\(panelFirstResponderDebugName()) activeSpaceIgnoreMs=\(formatMilliseconds(activeSpaceIgnoreMs))"
    }

    func beginIgnoringActiveSpaceChanges(trigger: String) {
        ignoreActiveSpaceChangesUntil = ProcessInfo.processInfo.systemUptime + activeSpaceChangeIgnoreWindow
        logSearchTrace(
            "activeSpaceIgnore trigger=\(trigger) durationMs=\(formatMilliseconds(activeSpaceChangeIgnoreWindow * 1_000)) \(searchTraceStateSummary())"
        )
    }

    func shouldIgnoreActiveSpaceDidChange() -> Bool {
        ProcessInfo.processInfo.systemUptime < ignoreActiveSpaceChangesUntil
    }

    func schedulePanelVisibilityRecovery(
        trigger: String,
        attemptDelaysNanoseconds: [UInt64] = [50_000_000],
        cancelSessionOnFailure: Bool = false,
        activateApplicationIfNeeded: Bool = true
    ) {
        panelPresentationRecoveryTask?.cancel()
        panelPresentationRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delays = attemptDelaysNanoseconds.isEmpty ? [UInt64(0)] : attemptDelaysNanoseconds

            for (attemptIndex, delayNanoseconds) in delays.enumerated() {
                if delayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                }
                guard !Task.isCancelled else { return }
                guard self.hasActivePresentationSession else {
                    self.panelPresentationRecoveryTask = nil
                    return
                }
                if self.isPanelVisibleToUser {
                    self.logSearchTrace(
                        "presentationRecovery trigger=\(trigger) action=complete reason=alreadyVisible attempt=\(attemptIndex + 1)/\(delays.count) \(self.searchTraceStateSummary())"
                    )
                    self.panelPresentationRecoveryTask = nil
                    self.scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(trigger: trigger)
                    return
                }

                self.logSearchTrace(
                    "presentationRecovery trigger=\(trigger) action=attempt index=\(attemptIndex + 1)/\(delays.count) \(self.searchTraceStateSummary())"
                )
                await self.performPanelVisibilityRecoveryAttempt(
                    trigger: trigger,
                    activateApplicationIfNeeded: activateApplicationIfNeeded
                )

                guard !Task.isCancelled else { return }
                guard self.hasActivePresentationSession else {
                    self.panelPresentationRecoveryTask = nil
                    return
                }
                if self.isPanelVisibleToUser {
                    self.updatePanelPresentationLevel(
                        trigger: "\(trigger)_steady",
                        behaviorMode: .allSpaces
                    )
                    self.logSearchTrace(
                        "presentationRecovery trigger=\(trigger) action=complete reason=recovered attempt=\(attemptIndex + 1)/\(delays.count) \(self.searchTraceStateSummary())"
                    )
                    self.panelPresentationRecoveryTask = nil
                    self.scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(trigger: trigger)
                    return
                }
            }

            self.panelPresentationRecoveryTask = nil
            guard cancelSessionOnFailure else { return }
            guard self.hasActivePresentationSession else { return }
            self.logSearchTrace(
                "presentationRecovery trigger=\(trigger) action=failed \(self.searchTraceStateSummary())"
            )
            self.cancelSelectionForSystemInterruption(trigger: trigger)
        }
    }

    func performPanelVisibilityRecoveryAttempt(
        trigger: String,
        activateApplicationIfNeeded: Bool
    ) async {
        if activateApplicationIfNeeded {
            activateApplicationForPanelPresentationIfNeeded()
        }
        panel.orderOut(nil)
        updatePanelPresentationLevel(
            trigger: "\(trigger)_recovery",
            behaviorMode: .activeSpaceMove
        )
        centerPanelOnActiveScreen(preferredScreen: resolveActivePresentationScreen())
        try? await Task.sleep(nanoseconds: panelPresentationRecoveryReorderDelayNs)
        guard hasActivePresentationSession else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func activateApplicationForPanelPresentationIfNeeded() {
        guard !isAppCurrentlyActive else { return }
        guard ProcessInfo.processInfo.systemUptime >= suppressApplicationActivationUntil else { return }
        if let activateApplicationIgnoringOtherAppsOverride {
            activateApplicationIgnoringOtherAppsOverride()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(
        trigger: String
    ) {
        guard let sessionKind = activeHotkeySessionKind else { return }
        guard !model.isSearchActive else { return }
        guard !isPrimaryModifierPressedInHardwareState(for: sessionKind) else { return }
        logInputTrace(
            "presentationRecovery trigger=\(trigger) action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        scheduleModifierReleaseConfirmation(trigger: "presentation_recovered")
    }
    func show(direction: CycleDirection) {
        guard model.startSession(triggerDirection: direction) else {
            RuntimeLog.info("Session", "start failed: no apps")
            NSSound.beep()
            return
        }
        activeHotkeySessionKind = .globalAppSwitcher
        lastCommittedTabAdvanceTimestamp = nil
        RuntimeLog.info("Session", "start direction=\(direction.debugName) \(self.model.debugSelectionSummary())")

        let targetScreen = resolveActivePresentationScreen()
        activePresentationScreen = targetScreen
        updatePanelSize(for: targetScreen)
        centerPanelOnActiveScreen(preferredScreen: targetScreen)
        updatePanelPresentationLevel(trigger: "global_show")
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        hideNonPanelWindowsIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        beginIgnoringActiveSpaceChanges(trigger: "global_show")
        schedulePanelVisibilityRecovery(
            trigger: "global_show",
            attemptDelaysNanoseconds: initialPresentationRecoveryAttemptDelaysNs
        )
        installEventMonitors()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    func showInAppWindowSwitcher(direction: CycleDirection) {
        guard model.startFocusedAppWindowSession(triggerDirection: direction) else {
            RuntimeLog.info("Session", "start in-app window switch failed: no windows")
            NSSound.beep()
            return
        }
        activeHotkeySessionKind = .inAppWindowSwitcher
        lastCommittedTabAdvanceTimestamp = nil
        RuntimeLog.info("Session", "start in-app direction=\(direction.debugName) \(self.model.debugSelectionSummary())")

        let targetScreen = resolveActivePresentationScreen()
        activePresentationScreen = targetScreen
        updatePanelSize(for: targetScreen)
        centerPanelOnActiveScreen(preferredScreen: targetScreen)
        updatePanelPresentationLevel(trigger: "in_app_show")
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        hideNonPanelWindowsIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        beginIgnoringActiveSpaceChanges(trigger: "in_app_show")
        schedulePanelVisibilityRecovery(
            trigger: "in_app_show",
            attemptDelaysNanoseconds: initialPresentationRecoveryAttemptDelaysNs
        )
        installEventMonitors()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    func updatePanelPresentationLevel(
        trigger: String,
        behaviorMode: SwitcherPanelWindowConfiguration.PresentationBehaviorMode = .allSpaces
    ) {
        let inspection = FrontmostWindowInspector.inspect()
        let requiresFallbackElevation = inspection.failureReason != nil
        let resolvedLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: inspection.fullScreenDetected,
            requiresFallbackElevation: requiresFallbackElevation
        )
        panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior(
            mode: behaviorMode
        )
        panel.level = resolvedLevel
    }

    func centerPanelOnActiveScreen(preferredScreen: NSScreen? = nil) {
        let targetScreen = preferredScreen
            ?? resolveActivePresentationScreen()
            ?? activePresentationScreen
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        activePresentationScreen = targetScreen
        guard let targetScreen else {
            panel.center()
            return
        }

        let frame = targetScreen.frame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.midY - panelSize.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    func resolveActivePresentationScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }
        return panel.screen
            ?? activePresentationScreen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    func resolveSizingScreen(preferredScreen: NSScreen? = nil) -> NSScreen? {
        preferredScreen
            ?? activePresentationScreen
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    func hideNonPanelWindowsIfNeeded() {
        guard !isAppCurrentlyActive else { return }
        hideNonPanelWindows()
    }

    func hideNonPanelWindows() {
        if let hideNonPanelWindowsOverride {
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

    func endPresentationSession() {
        guard isPanelPresented || hasActivePresentationSession else { return }
        panelPresentationRecoveryTask?.cancel()
        panelPresentationRecoveryTask = nil
        removeEventMonitors()
        panel.orderOut(nil)
        panel.level = SwitcherPanelWindowConfiguration.level
        panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior()
        activeHotkeySessionKind = nil
        activePresentationScreen = nil
        ignoreActiveSpaceChangesUntil = 0
        suppressApplicationActivationUntil = 0
        lastCommittedTabAdvanceTimestamp = nil
        if panelVisibilityOverride != nil {
            panelVisibilityOverride = false
        }
    }

    func finishSelection() {
        guard isPanelPresented || hasActivePresentationSession else { return }
        endPresentationSession()
        ignoreHotkeyPressesUntil = ProcessInfo.processInfo.systemUptime + postFinishHotkeyIgnoreWindow
        logInputTrace(
            "finishSelection nowMs=\(formatMilliseconds(monotonicMilliseconds())) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
        )
        model.commitSelection()
    }

    func cancelSelection() {
        guard isPanelPresented || hasActivePresentationSession else { return }
        endPresentationSession()
        ignoreHotkeyPressesUntil = ProcessInfo.processInfo.systemUptime + postFinishHotkeyIgnoreWindow
        logInputTrace(
            "cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds())) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
        )
        model.cancelSelection()
    }

    func updatePanelSize(for preferredScreen: NSScreen? = nil) {
        let visibleFrame = resolveSizingScreen(preferredScreen: preferredScreen)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        updatePanelSize(forVisibleFrame: visibleFrame)
    }

    func updatePanelSize(forVisibleFrame visibleFrame: CGRect) {
        if model.isWindowOnlyOverlay {
            let width = max(640, visibleFrame.width - windowOnlyOverlayScreenMargin)
            let height = max(360, visibleFrame.height - windowOnlyOverlayScreenMargin)
            let targetSize = NSSize(
                width: min(visibleFrame.width, width),
                height: min(visibleFrame.height, height)
            )
            if panel.contentRect(forFrameRect: panel.frame).size != targetSize {
                panel.setContentSize(targetSize)
            }
            return
        }

        let maxWidth = max(appLayerMinimumWidth, visibleFrame.width - panelScreenMargin)
        let maxHeight = max(minimumPanelHeight, visibleFrame.height - panelScreenMargin)
        let preferredWidth: CGFloat
        if model.isPreviewLayerMode {
            preferredWidth = preferredAppStripWidth(
                appCount: model.appCount,
                maxTileSize: previewLayerAppTileSize
            )
        } else {
            preferredWidth = preferredAppStripWidth(
                appCount: model.appCount,
                maxTileSize: appLayerMaxAdaptiveTileSize
            )
        }
        let width = min(maxWidth, preferredWidth)
        let height: CGFloat

        if model.isSearchActive {
            let visibleRows = max(1, min(model.searchResultCount, searchResultVisibleRowLimit))
            let desiredHeight = searchHeaderHeight + CGFloat(visibleRows) * searchResultRowHeight + 58
            height = min(maxHeight, max(minimumPanelHeight, desiredHeight))
            let targetSize = NSSize(width: width, height: height)
            if panel.contentRect(forFrameRect: panel.frame).size != targetSize {
                panel.setContentSize(targetSize)
            }
            return
        }

        if model.isPreviewLayerMode {
            let gridLayout = resolveAppGridLayout(
                appCount: model.appCount,
                availableWidth: max(1, width - overlayHorizontalInset),
                maxTileSize: previewLayerAppTileSize
            )
            let previewSectionHeight = resolvedStandardPreviewSectionHeight(
                panelWidth: width,
                itemCount: model.previewWindowCount
            )
            let desiredHeight =
                standardOverlayOuterPadding * 2
                + standardOverlayInnerVerticalPadding * 2
                + gridLayout.gridHeight
                + standardOverlaySectionSpacing
                + previewSectionHeight
            height = min(maxHeight, max(minimumPanelHeight, desiredHeight))
            model.updateAppGridLayout(
                tileSize: gridLayout.tileSize,
                spacing: gridLayout.spacing
            )
            model.updatePreviewSectionHeight(previewSectionHeight)
        } else {
            let gridLayout = resolveAppGridLayout(
                appCount: model.appCount,
                availableWidth: max(1, width - overlayHorizontalInset),
                maxTileSize: appLayerMaxAdaptiveTileSize
            )
            let searchHeaderHeight = searchFeatureEnabled ? appLayerSearchHeaderExtraHeight : 0
            let desiredHeight = appLayerStaticHeight + searchHeaderHeight + gridLayout.gridHeight

            height = min(maxHeight, max(minimumPanelHeight, desiredHeight))
            model.updateAppGridLayout(
                tileSize: gridLayout.tileSize,
                spacing: gridLayout.spacing
            )
        }

        let targetSize = NSSize(width: width, height: height)
        if panel.contentRect(forFrameRect: panel.frame).size != targetSize {
            panel.setContentSize(targetSize)
        }
    }

    func resolvedStandardPreviewSectionHeight(panelWidth: CGFloat, itemCount: Int) -> CGFloat {
        let count = max(itemCount, 1)
        let availableWidth = max(
            1,
            panelWidth - overlayHorizontalInset - standardPreviewWidthAdjustment
        )
        let totalSpacing = standardPreviewCardSpacing * CGFloat(max(count - 1, 0))
        let rawCardWidth = (availableWidth - totalSpacing) / CGFloat(count)
        let cardWidth = max(
            standardPreviewCardMinimumWidth,
            min(standardPreviewCardMaximumWidth, rawCardWidth)
        )
        let cardHeight = max(
            standardPreviewSectionMinimumHeight,
            min(standardPreviewSectionMaximumHeight, cardWidth * standardPreviewHeightRatio)
        )
        return cardHeight
    }

    func preferredAppStripWidth(appCount: Int, maxTileSize: CGFloat) -> CGFloat {
        let count = max(appCount, 1)
        let spacing = count > 1 ? maxAppTileSpacing : 0
        let stripWidth =
            CGFloat(count) * maxTileSize
            + CGFloat(max(count - 1, 0)) * spacing
        return max(appLayerMinimumWidth, stripWidth + overlayHorizontalInset)
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
        let count = max(appCount, 1)
        let safeWidth = max(1, availableWidth)
        let spacing = count > 1 ? maxAppTileSpacing : 0
        let totalSpacing = CGFloat(max(count - 1, 0)) * spacing
        let tileSize = max(
            minAppTileSize,
            min(
                maxTileSize,
                (safeWidth - totalSpacing) / CGFloat(count)
            )
        )

        return AppGridLayout(
            tileSize: tileSize,
            spacing: spacing,
            columns: count,
            rows: 1
        )
    }
}
