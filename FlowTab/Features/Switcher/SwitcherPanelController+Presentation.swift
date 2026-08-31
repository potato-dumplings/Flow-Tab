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
        let showStartMs = monotonicMilliseconds()
        switch model.startFocusedAppWindowSession(
            triggerDirection: direction
        ) {
        case .ready:
            presentReadyInAppWindowSwitcher(
                direction: direction,
                initialKeyInput: initialKeyInput,
                showStartMilliseconds: showStartMs,
                trigger: "in_app_show"
            )
        case .awaitingFreshProjection(let request):
            beginPendingFocusedWindowSessionPresentation(
                request: request,
                initialKeyInput: initialKeyInput,
                showStartMilliseconds: showStartMs
            )
            let failedMs = monotonicMilliseconds() - showStartMs
            logInputTrace(
                "show kind=inApp result=awaitingFreshProjection durationMs=\(formatMilliseconds(failedMs)) appID=\(request.appID) pid=\(request.pid)"
            )
        case .unavailable:
            let failedMs = monotonicMilliseconds() - showStartMs
            logInputTrace(
                "show kind=inApp result=failed durationMs=\(formatMilliseconds(failedMs))"
            )
            RuntimeLog.info(
                .session,
                "start in-app window switch failed: no windows"
            )
            NSSound.beep()
        }
    }

    private func presentReadyInAppWindowSwitcher(
        direction: CycleDirection,
        initialKeyInput: KeyInput?,
        showStartMilliseconds: Double,
        trigger: String
    ) {
        if let initialKeyInput {
            model.handle(initialKeyInput)
            logInputTrace(
                "show kind=inApp action=initialAdvance key=\(initialKeyInput.debugName) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
        }
        _ = model.prewarmWindowOnlySessionPreviews()
        presentStartedHotkeySession(
            kind: .inAppWindowSwitcher,
            trigger: trigger,
            logKind: "inApp",
            showStartMs: showStartMilliseconds,
            startLogMessage: "start in-app direction=\(direction.debugName) \(self.model.debugSelectionSummary())"
        )
    }

    private func beginPendingFocusedWindowSessionPresentation(
        request: PendingFocusedAppWindowSession,
        initialKeyInput: KeyInput?,
        showStartMilliseconds: Double
    ) {
        cancelPendingFocusedWindowSessionPresentation(
            reason: "replaced",
            resetsModel: false
        )
        let observationGeneration =
            focusedWindowSessionFreshnessObservationOwner.start {
                [weak self] expiredGeneration in
                self?.handleFocusedWindowSessionFreshnessWatchdog(
                    generation: expiredGeneration
                )
            }
        pendingFocusedWindowSessionPresentation =
            PendingFocusedWindowSessionPresentation(
                request: request,
                initialKeyInput: initialKeyInput,
                showStartMilliseconds: showStartMilliseconds,
                observationGeneration: observationGeneration
            )
    }

    @discardableResult
    func resolvePendingFocusedWindowSessionPresentation(
        appID: String?,
        evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence?
    ) -> Bool {
        guard let pending = pendingFocusedWindowSessionPresentation,
              appID == pending.request.appID,
              let evidence,
              evidence.appID == pending.request.appID,
              evidence.processIdentifier == pending.request.pid,
              evidence.isCompleteForScope,
              isHotkeyHoldSetPressed(for: .inAppWindowSwitcher)
        else {
            return false
        }
        guard model.completePendingFocusedAppWindowSession(
            pending.request
        ) else {
            return false
        }
        guard focusedWindowSessionFreshnessObservationOwner.resolve(
            generation: pending.observationGeneration
        ) else {
            model.resetSessionState()
            return false
        }
        pendingFocusedWindowSessionPresentation = nil
        presentReadyInAppWindowSwitcher(
            direction: pending.request.triggerDirection,
            initialKeyInput: pending.initialKeyInput,
            showStartMilliseconds: pending.showStartMilliseconds,
            trigger: "in_app_fresh_projection_ready"
        )
        return true
    }

    func cancelPendingFocusedWindowSessionPresentation(
        reason: String,
        resetsModel: Bool = true
    ) {
        guard pendingFocusedWindowSessionPresentation != nil else {
            return
        }
        focusedWindowSessionFreshnessObservationOwner.cancel()
        pendingFocusedWindowSessionPresentation = nil
        if resetsModel {
            model.resetSessionState()
        }
        logInputTrace(
            "show kind=inApp result=cancelled reason=\(reason)"
        )
    }

    private func handleFocusedWindowSessionFreshnessWatchdog(
        generation: Int
    ) {
        guard let pending = pendingFocusedWindowSessionPresentation,
              pending.observationGeneration == generation
        else {
            return
        }
        pendingFocusedWindowSessionPresentation = nil
        model.resetSessionState()
        logInputTrace(
            "show kind=inApp result=freshnessWatchdogExpired generation=\(generation) appID=\(pending.request.appID) pid=\(pending.request.pid) panelVisible=0"
        )
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
        let preparesStandardAppRevealBeforeLayout =
            kind == .globalAppSwitcher
                && !model.isSearchActive
        if preparesStandardAppRevealBeforeLayout {
            prepareInitialPanelReveal(kind: kind)
        }
        RuntimeLog.info(.session, startLogMessage)

        let targetScreen = resolveActivePresentationScreen()
        let screenReadyMs = monotonicMilliseconds()
        activePresentationScreen = targetScreen
        updatePanelSize(for: targetScreen)
        activePresentationInitialContentSize = panel.contentRect(
            forFrameRect: panel.frame
        ).size
        let sizeReadyMs = monotonicMilliseconds()
        centerPanelOnActiveScreen(preferredScreen: targetScreen)
        let centerReadyMs = monotonicMilliseconds()
        syncPanelAccessibilityAnchors()
        let accessibilityReadyMs = monotonicMilliseconds()
        updatePanelPresentationLevel(trigger: trigger)
        if !preparesStandardAppRevealBeforeLayout {
            prepareInitialPanelReveal(kind: kind)
        }
        let levelReadyMs = monotonicMilliseconds()

        let initialVisibilityTrackingStartMs = monotonicMilliseconds()
        let initialVisibilityGeneration =
            beginInitialPresentationVisibilityTracking(trigger: trigger)
        let initialVisibilityTrackingMs =
            monotonicMilliseconds() - initialVisibilityTrackingStartMs

        if model.isSearchActive {
            activateApplicationForPanelPresentationIfNeeded()
        }

        let panelWasAlreadyOrdered = panel.isVisible
        var stageStartMs = monotonicMilliseconds()
        if panelWasAlreadyOrdered {
            panel.makeKey()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        let firstMakeKeyMs = monotonicMilliseconds() - stageStartMs
        stageStartMs = monotonicMilliseconds()
        panel.orderFrontRegardless()
        let firstOrderRegardlessMs =
            monotonicMilliseconds() - stageStartMs

        requestInitialAppContentRenderPassIfNeeded()

        stageStartMs = monotonicMilliseconds()
        hideNonPanelWindowsIfNeeded()
        let hideMs = monotonicMilliseconds() - stageStartMs

        let secondMakeKeyMs = 0.0
        let secondOrderRegardlessMs = 0.0

        stageStartMs = monotonicMilliseconds()
        scheduleInitialPanelVisibilityRecovery(
            trigger: trigger,
            initialVisibilityGeneration: initialVisibilityGeneration
        )
        let presentationReadbackMs =
            monotonicMilliseconds() - stageStartMs

        stageStartMs = monotonicMilliseconds()
        installEventMonitors()
        let monitorMs = monotonicMilliseconds() - stageStartMs

        stageStartMs = monotonicMilliseconds()
        if !model.isSearchActive && !model.isWindowOnlyOverlay {
            _ = model.scheduleSelectedAppWindowProjectionIfNeeded()
        }
        scheduleDelayedWindowLayerEntryIfNeeded(
            prewarmsPreviews: false
        )
        let presentedMs = monotonicMilliseconds()
        let autoEnterMs = presentedMs - stageStartMs
        logPanelPresentationBreakdown(
            kind: logKind,
            showStartMs: showStartMs,
            sessionReadyMs: sessionReadyMs,
            screenReadyMs: screenReadyMs,
            sizeReadyMs: sizeReadyMs,
            centerReadyMs: centerReadyMs,
            accessibilityReadyMs: accessibilityReadyMs,
            levelReadyMs: levelReadyMs,
            hideMs: hideMs,
            initialVisibilityTrackingMs: initialVisibilityTrackingMs,
            monitorMs: monitorMs,
            firstMakeKeyMs: firstMakeKeyMs,
            firstOrderRegardlessMs: firstOrderRegardlessMs,
            secondMakeKeyMs: secondMakeKeyMs,
            secondOrderRegardlessMs: secondOrderRegardlessMs,
            presentationReadbackMs: presentationReadbackMs,
            autoEnterMs: autoEnterMs
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
        guard panel.frame.origin != origin else { return }
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
        let reusableShellContentSize = activePresentationInitialContentSize
        cancelPendingFocusedWindowSessionPresentation(
            reason: "presentationEnded"
        )
        invalidatePresentationSessionGeneration(trigger: "endPresentationSession")
        cancelActiveSpaceTransitionObservation()
        cancelTerminateInterruptionProtection()
        cancelPanelPresentationRecovery()
        clearInitialPresentationVisibilityTracking(invalidate: true)
        clearInitialVisibleFrameTracking()
        removeEventMonitors()
        cancelInitialPanelReveal()
        panelPresentationActive = false
        panel.orderOut(nil)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.updateSwitcherAccessibilityApps([], tileSize: 1, spacing: 0, appStripHeaderOffset: 0)
        panel.level = SwitcherPanelWindowConfiguration.level
        panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior()
        activeHotkeySessionKind = nil
        activePresentationInitialContentSize = nil
        activePresentationScreen = nil
        lastSearchLayoutSizingLogSummary = nil
        panelVisibilityRecoveryState = .idle
        if panelVisibilityOverride != nil {
            panelVisibilityOverride = false
        }
        panel.orderFrontRegardless()
        prepareReusablePanelShell(contentSize: reusableShellContentSize)
    }

    func beginPresentationSession(kind: HotkeySessionKind, trigger: String) {
        cancelPanelVisibilityProbe()
        presentationSessionGeneration += 1
        activeHotkeySessionKind = kind
        activePresentationInitialContentSize = nil
        panelPresentationActive = true
        panel.ignoresMouseEvents = false
        beginInitialVisibleFrameTracking()
        resetPointerSelectionGate()
        logInputTrace(
            "presentationSession trigger=\(trigger) action=begin kind=\(kind) generation=\(presentationSessionGeneration)"
        )
    }

    private func prepareReusablePanelShell(contentSize: NSSize?) {
        guard let contentSize else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !panelPresentationActive else { return }
            setPanelContentSize(contentSize, recenterScreen: nil)
            panel.orderFrontRegardless()
        }
    }

    func invalidatePresentationSessionGeneration(trigger: String) {
        cancelPanelVisibilityProbe()
        presentationSessionGeneration += 1
        clearInitialVisibleFrameTracking()
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
        let appStripPreferredWidth = preferredAppStripWidth(
            appCount: model.appCount,
            maxTileSize: appLayerMaxAdaptiveTileSize
        )
        let preferredWidth: CGFloat
        if model.isPreviewLayerMode {
            preferredWidth = preferredPreviewLayerWidth(
                appCount: model.appCount,
                windowCount: model.previewWindowCount,
                maxPanelWidth: maxWidth
            )
        } else {
            preferredWidth = appStripPreferredWidth
        }
        let width = resolvedAppLayerPanelWidth(
            preferredWidth: preferredWidth,
            visibleFrameWidth: visibleFrame.width
        )
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
                maxHeight: maxHeight,
                visibleFrameWidth: visibleFrame.width,
                preferredAppStripWidth: appStripPreferredWidth,
                finalPanelWidth: width
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

    func resolvedAppLayerPanelWidth(
        preferredWidth: CGFloat,
        visibleFrameWidth: CGFloat
    ) -> CGFloat {
        min(
            preferredWidth,
            max(appLayerMinimumWidth, visibleFrameWidth - panelScreenMargin)
        )
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
