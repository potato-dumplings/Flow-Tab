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
        let now = ProcessInfo.processInfo.systemUptime
        let activeSpaceIgnoreMs = max(0, (ignoreActiveSpaceChangesUntil - now) * 1_000)
        let terminateProtectionMs = max(0, (terminateInterruptionProtectionUntil - now) * 1_000)
        let searchIndexTraceFields = model.lastSearchIndexReadDiagnostic?.searchTraceFields
            ?? [
                "searchIndexReadiness=none",
                "searchIndexResultState=none",
                "searchIndexDegraded=0",
                "searchIndexCoversCurrentGeneration=0",
                "searchFreshnessBarrierRequested=0"
            ].joined(separator: " ")
        return "panelVisible=\(isPanelPresented ? 1 : 0) panelKey=\(panel.isKeyWindow ? 1 : 0) appActive=\(isAppCurrentlyActive ? 1 : 0) searchActive=\(model.isSearchActive ? 1 : 0) inputFocused=\(model.isSearchInputFocused ? 1 : 0) marked=\(model.hasMarkedSearchText ? 1 : 0) firstResponder=\(panelFirstResponderDebugName()) activeSpaceIgnoreMs=\(formatMilliseconds(activeSpaceIgnoreMs)) terminateProtectionMs=\(formatMilliseconds(terminateProtectionMs)) \(searchIndexTraceFields)"
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

    func beginTerminateInterruptionProtection(
        trigger: String,
        duration: TimeInterval? = nil,
        extendExisting: Bool = true
    ) {
        let protectionWindow = duration ?? terminateInterruptionProtectionWindow
        let protectionUntil = ProcessInfo.processInfo.systemUptime + protectionWindow
        terminateInterruptionProtectionUntil = extendExisting
            ? max(terminateInterruptionProtectionUntil, protectionUntil)
            : protectionUntil
        logSearchTrace(
            "terminateInterruptionProtection trigger=\(trigger) durationMs=\(formatMilliseconds(protectionWindow * 1_000)) \(searchTraceStateSummary())"
        )
    }

    func shouldProtectTerminateSystemInterruption() -> Bool {
        ProcessInfo.processInfo.systemUptime < terminateInterruptionProtectionUntil
            && model.session != nil
    }

    func schedulePanelVisibilityRecovery(
        trigger: String,
        attemptDelaysNanoseconds: [UInt64] = [50_000_000],
        cancelSessionOnFailure: Bool = false,
        activateApplicationIfNeeded: Bool = true,
        recoveryMode: PanelVisibilityRecoveryMode = .hardReorder
    ) {
        let recoveryGeneration = beginPanelPresentationRecoveryTask()
        panelVisibilityRecoveryState = .suspectedHidden(
            trigger: trigger,
            generation: recoveryGeneration
        )
        panelPresentationRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isPanelPresentationRecoveryGenerationCurrent(recoveryGeneration) else { return }
            let delays = attemptDelaysNanoseconds.isEmpty ? [UInt64(0)] : attemptDelaysNanoseconds

            for (attemptIndex, delayNanoseconds) in delays.enumerated() {
                if delayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                }
                guard !Task.isCancelled else { return }
                guard self.isPanelPresentationRecoveryGenerationCurrent(recoveryGeneration) else { return }
                guard self.hasActivePresentationSession else {
                    self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                    return
                }
                if self.isPanelVisibleToUser {
                    self.panelVisibilityRecoveryState = .visibleConfirmed(
                        trigger: trigger,
                        generation: recoveryGeneration,
                        reason: "alreadyVisible"
                    )
                    self.logSearchTrace(
                        "presentationRecovery trigger=\(trigger) action=complete reason=alreadyVisible generation=\(recoveryGeneration) attempt=\(attemptIndex + 1)/\(delays.count) \(self.searchTraceStateSummary())"
                    )
                    self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                    self.scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(trigger: trigger)
                    return
                }

                let attemptAction = recoveryMode == .softReorder ? "softAttempt" : "attempt"
                self.panelVisibilityRecoveryState = .recovering(
                    trigger: trigger,
                    generation: recoveryGeneration,
                    attempt: attemptIndex + 1,
                    totalAttempts: delays.count,
                    mode: recoveryMode
                )
                self.logSearchTrace(
                    "presentationRecovery trigger=\(trigger) action=\(attemptAction) generation=\(recoveryGeneration) index=\(attemptIndex + 1)/\(delays.count) \(self.searchTraceStateSummary())"
                )
                await self.performPanelVisibilityRecoveryAttempt(
                    trigger: trigger,
                    activateApplicationIfNeeded: activateApplicationIfNeeded,
                    recoveryMode: recoveryMode,
                    generation: recoveryGeneration,
                    attempt: attemptIndex + 1,
                    totalAttempts: delays.count
                )

                guard !Task.isCancelled else { return }
                guard self.isPanelPresentationRecoveryGenerationCurrent(recoveryGeneration) else { return }
                guard self.hasActivePresentationSession else {
                    self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                    return
                }
                if self.isPanelVisibleToUser {
                    self.panelVisibilityRecoveryState = .visibleConfirmed(
                        trigger: trigger,
                        generation: recoveryGeneration,
                        reason: "recovered"
                    )
                    self.updatePanelPresentationLevel(
                        trigger: "\(trigger)_steady",
                        behaviorMode: .allSpaces
                    )
                    self.logSearchTrace(
                        "presentationRecovery trigger=\(trigger) action=complete reason=recovered generation=\(recoveryGeneration) attempt=\(attemptIndex + 1)/\(delays.count) \(self.searchTraceStateSummary())"
                    )
                    self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                    self.scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(trigger: trigger)
                    return
                }
            }

            self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
            guard cancelSessionOnFailure else { return }
            guard self.hasActivePresentationSession else { return }
            guard self.isPanelPresentationRecoveryGenerationCurrent(recoveryGeneration) else { return }
            self.panelVisibilityRecoveryState = .failed(
                trigger: trigger,
                generation: recoveryGeneration,
                reason: "attemptsExhausted"
            )
            self.logSearchTrace(
                "presentationRecovery trigger=\(trigger) action=failed generation=\(recoveryGeneration) \(self.searchTraceStateSummary())"
            )
            self.cancelSelectionForSystemInterruption(trigger: trigger)
        }
    }

    @discardableResult
    func beginPanelPresentationRecoveryTask() -> Int {
        panelPresentationRecoveryTask?.cancel()
        panelPresentationRecoveryGeneration += 1
        return panelPresentationRecoveryGeneration
    }

    func cancelPanelPresentationRecoveryTask() {
        panelPresentationRecoveryTask?.cancel()
        panelPresentationRecoveryGeneration += 1
        panelPresentationRecoveryTask = nil
    }

    func clearPanelPresentationRecoveryTaskIfCurrent(_ generation: Int) {
        guard isPanelPresentationRecoveryGenerationCurrent(generation) else { return }
        panelPresentationRecoveryTask = nil
    }

    func isPanelPresentationRecoveryGenerationCurrent(_ generation: Int) -> Bool {
        generation == panelPresentationRecoveryGeneration
    }

    func performPanelVisibilityRecoveryAttempt(
        trigger: String,
        activateApplicationIfNeeded: Bool,
        recoveryMode: PanelVisibilityRecoveryMode = .hardReorder,
        generation: Int? = nil,
        attempt: Int? = nil,
        totalAttempts: Int? = nil
    ) async {
        let beforeSnapshot = panelVisibilitySnapshot()
        defer {
            recordPanelVisibilityRecoveryDiagnostic(
                trigger: trigger,
                generation: generation,
                attempt: attempt,
                totalAttempts: totalAttempts,
                mode: recoveryMode,
                before: beforeSnapshot,
                after: panelVisibilitySnapshot()
            )
        }

        guard recoveryMode == .hardReorder else {
            updatePanelPresentationLevel(
                trigger: "\(trigger)_soft_recovery",
                behaviorMode: .allSpaces
            )
            centerPanelOnActiveScreen(preferredScreen: resolveActivePresentationScreen())
            guard hasActivePresentationSession else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            return
        }

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
        let showStartMs = monotonicMilliseconds()
        guard model.startSession(triggerDirection: direction) else {
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
        guard model.startSearchSession(triggerDirection: direction) else {
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
        let showStartMs = monotonicMilliseconds()
        guard model.startFocusedAppWindowSession(triggerDirection: direction) else {
            let failedMs = monotonicMilliseconds() - showStartMs
            logInputTrace(
                "show kind=inApp result=failed durationMs=\(formatMilliseconds(failedMs))"
            )
            RuntimeLog.info(.session, "start in-app window switch failed: no windows")
            NSSound.beep()
            return
        }
        if let initialKeyInput {
            model.handle(initialKeyInput)
            logInputTrace(
                "show kind=inApp action=initialAdvance key=\(initialKeyInput.debugName) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
        }
        presentStartedHotkeySession(
            kind: .inAppWindowSwitcher,
            trigger: "in_app_show",
            logKind: "inApp",
            showStartMs: showStartMs,
            startLogMessage: "start in-app direction=\(direction.debugName) \(self.model.debugSelectionSummary())"
        )
        if initialKeyInput != nil {
            lastCommittedTabAdvanceTimestamp = ProcessInfo.processInfo.systemUptime
        }
    }

    func presentStartedHotkeySession(
        kind: HotkeySessionKind,
        trigger: String,
        logKind: String,
        showStartMs: Double,
        startLogMessage: String
    ) {
        let sessionReadyMs = monotonicMilliseconds()
        beginPresentationSession(kind: kind, trigger: trigger)
        lastCommittedTabAdvanceTimestamp = nil
        RuntimeLog.info(.session, startLogMessage)

        let targetScreen = resolveActivePresentationScreen()
        let screenReadyMs = monotonicMilliseconds()
        activePresentationScreen = targetScreen
        updatePanelSize(for: targetScreen)
        let sizeReadyMs = monotonicMilliseconds()
        centerPanelOnActiveScreen(preferredScreen: targetScreen)
        let centerReadyMs = monotonicMilliseconds()
        syncPanelAccessibilityAnchors()
        let accessibilityReadyMs = monotonicMilliseconds()
        updatePanelPresentationLevel(trigger: trigger)
        let levelReadyMs = monotonicMilliseconds()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        let firstOrderReadyMs = monotonicMilliseconds()
        hideNonPanelWindowsIfNeeded()
        let hideReadyMs = monotonicMilliseconds()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        let secondOrderReadyMs = monotonicMilliseconds()
        beginIgnoringActiveSpaceChanges(trigger: trigger)
        let ignoreReadyMs = monotonicMilliseconds()
        scheduleInitialPanelVisibilityRecovery(
            trigger: trigger,
            activateApplicationIfNeeded: false
        )
        let recoveryReadyMs = monotonicMilliseconds()
        installEventMonitors()
        let monitorReadyMs = monotonicMilliseconds()
        scheduleDelayedWindowLayerEntryIfNeeded()
        let presentedMs = monotonicMilliseconds()
        logPanelPresentationBreakdown(
            kind: logKind,
            showStartMs: showStartMs,
            sessionReadyMs: sessionReadyMs,
            screenReadyMs: screenReadyMs,
            sizeReadyMs: sizeReadyMs,
            centerReadyMs: centerReadyMs,
            accessibilityReadyMs: accessibilityReadyMs,
            levelReadyMs: levelReadyMs,
            firstOrderReadyMs: firstOrderReadyMs,
            hideReadyMs: hideReadyMs,
            secondOrderReadyMs: secondOrderReadyMs,
            ignoreReadyMs: ignoreReadyMs,
            recoveryReadyMs: recoveryReadyMs,
            monitorReadyMs: monitorReadyMs,
            autoEnterReadyMs: presentedMs
        )
        logInputTrace(
            "show kind=\(logKind) result=presented sessionMs=\(formatMilliseconds(sessionReadyMs - showStartMs)) totalMs=\(formatMilliseconds(presentedMs - showStartMs)) \(searchTraceStateSummary())"
        )
        schedulePanelVisibilityProbe(
            kind: logKind,
            showStartMs: showStartMs,
            presentedMs: presentedMs
        )
    }

    func updatePanelPresentationLevel(
        trigger: String,
        behaviorMode: SwitcherPanelWindowConfiguration.PresentationBehaviorMode = .allSpaces
    ) {
        let resolvedLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: runtimeProjectionHasCurrentSpaceFullscreen()
        )
        panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior(
            mode: behaviorMode
        )
        panel.level = resolvedLevel
    }

    private func runtimeProjectionHasCurrentSpaceFullscreen() -> Bool {
        guard let projection = model.runtimeProjectionService.readSpaceTopologyProjection() else {
            model.runtimeProjectionService.signalSpaceTopologyChanged()
            return false
        }
        guard projection.freshness.isCompleteForScope else { return false }
        let displayID = (activePresentationScreen ?? resolveActivePresentationScreen())?.flowTabDisplayID
        return projection.signature.hasFullscreenWindowOnCurrentSpace(displayID: displayID)
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
        invalidatePresentationSessionGeneration(trigger: "endPresentationSession")
        cancelPanelPresentationRecoveryTask()
        clearInitialPresentationVisibilityTracking(invalidate: true)
        removeEventMonitors()
        panel.orderOut(nil)
        panel.updateSwitcherAccessibilityApps([], tileSize: 1, spacing: 0, appStripHeaderOffset: 0)
        panel.level = SwitcherPanelWindowConfiguration.level
        panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior()
        activeHotkeySessionKind = nil
        activePresentationScreen = nil
        lastSearchLayoutSizingLogSummary = nil
        ignoreActiveSpaceChangesUntil = 0
        terminateInterruptionProtectionUntil = 0
        suppressApplicationActivationUntil = 0
        lastCommittedTabAdvanceTimestamp = nil
        panelVisibilityRecoveryState = .idle
        if panelVisibilityOverride != nil {
            panelVisibilityOverride = false
        }
    }

    func beginPresentationSession(kind: HotkeySessionKind, trigger: String) {
        presentationSessionGeneration += 1
        activeHotkeySessionKind = kind
        resetPointerSelectionGate()
        logInputTrace(
            "presentationSession trigger=\(trigger) action=begin kind=\(kind) generation=\(presentationSessionGeneration)"
        )
    }

    func invalidatePresentationSessionGeneration(trigger: String) {
        presentationSessionGeneration += 1
        logInputTrace(
            "presentationSession trigger=\(trigger) action=invalidate generation=\(presentationSessionGeneration)"
        )
    }

    func isPresentationSessionGenerationCurrent(_ generation: Int) -> Bool {
        generation == presentationSessionGeneration
    }

    func updatePanelSize(for preferredScreen: NSScreen? = nil) {
        let sizingScreen = resolveSizingScreen(preferredScreen: preferredScreen)
        let visibleFrame = sizingScreen?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        updatePanelSize(forVisibleFrame: visibleFrame, recenterScreen: sizingScreen)
    }

    func updatePanelSize(forVisibleFrame visibleFrame: CGRect) {
        updatePanelSize(forVisibleFrame: visibleFrame, recenterScreen: nil)
    }

    private func updatePanelSize(forVisibleFrame visibleFrame: CGRect, recenterScreen: NSScreen?) {
        if model.isWindowOnlyOverlay {
            let targetSize = SwitcherWindowOnlyPanelSizing.preferredSize(
                visibleFrameSize: visibleFrame.size,
                itemCount: model.previewWindowCount
            )
            setPanelContentSize(targetSize, recenterScreen: recenterScreen)
            return
        }

        let maxWidth = max(appLayerMinimumWidth, visibleFrame.width - panelScreenMargin)
        let maxHeight = max(minimumPanelHeight, visibleFrame.height - panelScreenMargin)
        let preferredWidth: CGFloat
        if model.isPreviewLayerMode {
            preferredWidth = preferredPreviewLayerWidth(
                appCount: model.appCount,
                windowCount: model.previewWindowCount,
                maxPanelWidth: maxWidth
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
            let visibleRows = SwitcherPanelLayoutMetrics.Search.visibleRowCount(
                for: model.searchResultCount
            )
            let listHeight = SwitcherPanelLayoutMetrics.Search.resultListHeight(
                visibleRowCount: visibleRows,
                resultRowHeight: model.searchLayoutMeasurements.resultRowHeight
            )
            let desiredHeight = SwitcherPanelLayoutMetrics.Search.panelHeight(
                visibleRowCount: visibleRows,
                measurements: model.searchLayoutMeasurements
            )
            height = min(maxHeight, max(minimumPanelHeight, desiredHeight))
            logSearchLayoutSizing(
                resultCount: model.searchResultCount,
                visibleRows: visibleRows,
                measurements: model.searchLayoutMeasurements,
                listHeight: listHeight,
                neededPanelHeight: desiredHeight,
                finalPanelHeight: height,
                maxHeight: maxHeight
            )
            let targetSize = NSSize(width: width, height: height)
            setPanelContentSize(targetSize, recenterScreen: recenterScreen)
            return
        }

        if model.isPreviewLayerMode {
            let gridLayout = resolveAppGridLayout(
                appCount: model.appCount,
                availableWidth: max(1, width - SwitcherPanelLayoutMetrics.horizontalInset),
                maxTileSize: previewLayerAppTileSize
            )
            let previewSectionHeight = resolvedStandardPreviewSectionHeight(
                panelWidth: width,
                itemCount: model.previewWindowCount
            )
            let desiredHeight =
                SwitcherPanelLayoutMetrics.rootPadding * 2
                + SwitcherPanelLayoutMetrics.bodyVerticalPadding * 2
                + gridLayout.gridHeight
                + SwitcherPanelLayoutMetrics.bodySpacing
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
                availableWidth: max(1, width - SwitcherPanelLayoutMetrics.horizontalInset),
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
        setPanelContentSize(targetSize, recenterScreen: recenterScreen)
    }

    private func setPanelContentSize(_ targetSize: NSSize, recenterScreen _: NSScreen?) {
        let oldFrame = panel.frame
        let currentSize = panel.contentRect(forFrameRect: panel.frame).size
        guard currentSize != targetSize else { return }

        panel.setContentSize(targetSize)

        guard isPanelPresented else { return }
        let newFrame = panel.frame
        panel.setFrameOrigin(
            NSPoint(
                x: oldFrame.midX - newFrame.width / 2,
                y: oldFrame.maxY - newFrame.height
            )
        )
    }

    func resolvedStandardPreviewSectionHeight(panelWidth: CGFloat, itemCount: Int) -> CGFloat {
        let availableWidth = max(
            1,
            panelWidth - SwitcherPanelLayoutMetrics.horizontalInset - standardPreviewWidthAdjustment
        )
        let page = SwitcherWindowPreviewPaging.page(
            itemCount: itemCount,
            selectedIndex: 0,
            availableWidth: availableWidth
        )
        let count = max(page.visibleRange.count, 1)
        let cardWidth = SwitcherWindowPreviewPaging.cardWidth(
            cardAreaWidth: page.cardAreaWidth,
            visibleCount: count
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
        return max(appLayerMinimumWidth, stripWidth + SwitcherPanelLayoutMetrics.horizontalInset)
    }

    func preferredPreviewLayerWidth(
        appCount: Int,
        windowCount: Int,
        maxPanelWidth: CGFloat
    ) -> CGFloat {
        let appStripWidth = preferredAppStripWidth(
            appCount: appCount,
            maxTileSize: previewLayerAppTileSize
        )
        let maximumPreviewAvailableWidth = max(
            1,
            maxPanelWidth - SwitcherPanelLayoutMetrics.horizontalInset - standardPreviewWidthAdjustment
        )
        let previewAvailableWidth = SwitcherWindowPreviewPaging.preferredAvailableWidth(
            itemCount: windowCount,
            maximumAvailableWidth: maximumPreviewAvailableWidth
        )
        let previewPanelWidth =
            previewAvailableWidth
            + SwitcherPanelLayoutMetrics.horizontalInset
            + standardPreviewWidthAdjustment
        return max(appStripWidth, previewPanelWidth)
    }

    func logSearchLayoutSizing(
        resultCount: Int,
        visibleRows: Int,
        measurements: SwitcherSearchLayoutMeasurements,
        listHeight: CGFloat,
        neededPanelHeight: CGFloat,
        finalPanelHeight: CGFloat,
        maxHeight: CGFloat
    ) {
        let summary = [
            "resultCount=\(resultCount)",
            "visibleRows=\(visibleRows)",
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

private extension NSScreen {
    var flowTabDisplayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
