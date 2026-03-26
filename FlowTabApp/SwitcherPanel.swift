import AppKit
import Carbon
import SwiftUI
import FlowTabCore

@MainActor
final class SwitcherPanelController {
    private enum HotkeySessionKind {
        case globalAppSwitcher
        case inAppWindowSwitcher
    }

    private let model = LiveSwitcherModel()
    private let panel: NSPanel

    private var keyDownMonitor: Any?
    private var localFlagsChangedMonitor: Any?
    private var globalFlagsChangedMonitor: Any?
    private var pendingModifierReleaseConfirmationTask: Task<Void, Never>?
    private var delayedWindowLayerTimer: Timer?
    private var lastCommittedTabAdvanceTimestamp: TimeInterval?
    private var ignoreHotkeyPressesUntil: TimeInterval = 0
    private var windowLayerPresentationDelay: TimeInterval {
        WindowLayerPreferencesStore.loadAutoEnterDelay()
    }
    private let modifierReleaseConfirmationSampleIntervalNs: UInt64 = 25_000_000
    private let modifierReleaseConfirmationSampleCount: Int = 2
    private let postFinishHotkeyIgnoreWindow: TimeInterval = 0.02
    private let autoEnterWindowLayerEnabled = true
    private let tabAdvanceMinimumInterval: TimeInterval = 0.016
    private let panelScreenMargin: CGFloat = 80
    private let windowOnlyOverlayScreenMargin: CGFloat = 20
    private let appLayerMinimumWidth: CGFloat = 440
    private let overlayHorizontalInset: CGFloat = 64
    private let appLayerStaticHeight: CGFloat = 56
    private let standardOverlayOuterPadding: CGFloat = 16
    private let standardOverlayInnerVerticalPadding: CGFloat = 14
    private let standardOverlaySectionSpacing: CGFloat = 12
    private let standardPreviewSectionMinimumHeight: CGFloat = 130
    private let standardPreviewSectionMaximumHeight: CGFloat = 220
    private let standardPreviewCardMinimumWidth: CGFloat = 120
    private let standardPreviewCardMaximumWidth: CGFloat = 360
    private let standardPreviewCardSpacing: CGFloat = 12
    private let standardPreviewHeightRatio: CGFloat = 0.62
    private let standardPreviewWidthAdjustment: CGFloat = 4
    private let minimumPanelHeight: CGFloat = 140
    private let previewLayerAppTileSize: CGFloat = 68
    private let appLayerMaxAdaptiveTileSize: CGFloat = 90
    private let maxAppTileSpacing: CGFloat = 10
    private let minAppTileSize: CGFloat = 1
    private var activeHotkeySessionKind: HotkeySessionKind?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 290),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let hostingView = NSHostingView(rootView: SwitcherPanelRootView(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    private func monotonicMilliseconds() -> Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }

    private func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func logInputTrace(_ message: String) {
        RuntimeLog.info("InputTrace", message)
    }

    func handleGlobalHotkey(isBackward: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let nowMs = monotonicMilliseconds()
        let directionText = isBackward ? "backward" : "forward"
        if now < ignoreHotkeyPressesUntil {
            logInputTrace(
                "hotkeyPressed dir=\(directionText) dropped=postFinishWindow nowMs=\(formatMilliseconds(nowMs)) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
            )
            return
        }
        if panel.isVisible {
            guard activeHotkeySessionKind == .globalAppSwitcher else { return }
            guard isPrimaryModifierLikelyPressed() else {
                logInputTrace(
                    "hotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=0 action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(nowMs))"
                )
                scheduleModifierReleaseConfirmation(trigger: "pressed_without_modifier")
                return
            }
            logInputTrace(
                "hotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=1 action=advance nowMs=\(formatMilliseconds(nowMs))"
            )
            // Main switch hotkey is registered globally, so repeated key presses should keep
            // advancing while the panel is visible.
            advance(isBackward ? .tabBackward : .tabForward)
            return
        }
        logInputTrace(
            "hotkeyPressed dir=\(directionText) panelVisible=0 action=show nowMs=\(formatMilliseconds(nowMs))"
        )
        let direction: CycleDirection = isBackward ? .backward : .forward
        show(direction: direction)
    }

    func handleGlobalHotkeyReleased() {
        guard panel.isVisible else { return }
        guard activeHotkeySessionKind == .globalAppSwitcher else { return }
        // Carbon hotkey "released" also fires when the main key (for example Tab) is released
        // while the modifier is still held. Ignore those events to avoid repeatedly spinning up
        // release-confirmation work during rapid cycling.
        guard !isPrimaryModifierPressedInHardwareState() else { return }
        let nowMs = monotonicMilliseconds()
        logInputTrace(
            "hotkeyReleased panelVisible=1 action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(nowMs))"
        )
        scheduleModifierReleaseConfirmation(trigger: "hotkey_released")
    }

    func handleInAppWindowHotkey(isBackward: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let nowMs = monotonicMilliseconds()
        let directionText = isBackward ? "backward" : "forward"
        if now < ignoreHotkeyPressesUntil {
            logInputTrace(
                "inAppHotkeyPressed dir=\(directionText) dropped=postFinishWindow nowMs=\(formatMilliseconds(nowMs)) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
            )
            return
        }
        if panel.isVisible {
            guard activeHotkeySessionKind == .inAppWindowSwitcher else { return }
            guard isPrimaryModifierLikelyPressed() else {
                logInputTrace(
                    "inAppHotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=0 action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(nowMs))"
                )
                scheduleModifierReleaseConfirmation(trigger: "in_app_pressed_without_modifier")
                return
            }
            logInputTrace(
                "inAppHotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=1 action=advance nowMs=\(formatMilliseconds(nowMs))"
            )
            advance(isBackward ? .tabBackward : .tabForward)
            return
        }
        logInputTrace(
            "inAppHotkeyPressed dir=\(directionText) panelVisible=0 action=show nowMs=\(formatMilliseconds(nowMs))"
        )
        let direction: CycleDirection = isBackward ? .backward : .forward
        showInAppWindowSwitcher(direction: direction)
    }

    func handleInAppWindowHotkeyReleased() {
        guard panel.isVisible else { return }
        guard activeHotkeySessionKind == .inAppWindowSwitcher else { return }
        guard !isPrimaryModifierPressedInHardwareState() else { return }
        let nowMs = monotonicMilliseconds()
        logInputTrace(
            "inAppHotkeyReleased panelVisible=1 action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(nowMs))"
        )
        scheduleModifierReleaseConfirmation(trigger: "in_app_hotkey_released")
    }

    private func show(direction: CycleDirection) {
        guard model.startSession(triggerDirection: direction) else {
            RuntimeLog.info("Session", "start failed: no apps")
            NSSound.beep()
            return
        }
        activeHotkeySessionKind = .globalAppSwitcher
        lastCommittedTabAdvanceTimestamp = nil
        RuntimeLog.info("Session", "start direction=\(direction.debugName) \(self.model.debugSelectionSummary())")

        updatePanelSize()

        panel.center()
        hideNonPanelWindows()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installEventMonitors()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    private func showInAppWindowSwitcher(direction: CycleDirection) {
        guard model.startFocusedAppWindowSession(triggerDirection: direction) else {
            RuntimeLog.info("Session", "start in-app window switch failed: no windows")
            NSSound.beep()
            return
        }
        activeHotkeySessionKind = .inAppWindowSwitcher
        lastCommittedTabAdvanceTimestamp = nil
        RuntimeLog.info("Session", "start in-app direction=\(direction.debugName) \(self.model.debugSelectionSummary())")

        updatePanelSize()

        panel.center()
        hideNonPanelWindows()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installEventMonitors()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    private func hideNonPanelWindows() {
        for window in NSApp.windows {
            guard !(window is NSPanel) else { continue }
            guard window.isVisible else { continue }
            // Keep menu-bar status-item windows visible; only hide regular app windows.
            guard window.level == .normal else { continue }
            window.orderOut(nil)
        }
    }

    private func finishSelection() {
        guard panel.isVisible else { return }
        removeEventMonitors()
        panel.orderOut(nil)
        activeHotkeySessionKind = nil
        lastCommittedTabAdvanceTimestamp = nil
        ignoreHotkeyPressesUntil = ProcessInfo.processInfo.systemUptime + postFinishHotkeyIgnoreWindow
        logInputTrace(
            "finishSelection nowMs=\(formatMilliseconds(monotonicMilliseconds())) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
        )
        model.commitSelection()
    }

    private func cancelSelection() {
        guard panel.isVisible else { return }
        removeEventMonitors()
        panel.orderOut(nil)
        activeHotkeySessionKind = nil
        lastCommittedTabAdvanceTimestamp = nil
        ignoreHotkeyPressesUntil = ProcessInfo.processInfo.systemUptime + postFinishHotkeyIgnoreWindow
        logInputTrace(
            "cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds())) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
        )
        model.cancelSelection()
    }

    private func updatePanelSize() {
        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
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
        let width = maxWidth
        let height: CGFloat

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
            let desiredHeight = appLayerStaticHeight + gridLayout.gridHeight

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

    private func resolvedStandardPreviewSectionHeight(panelWidth: CGFloat, itemCount: Int) -> CGFloat {
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

    private struct AppGridLayout {
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

    private func resolveAppGridLayout(
        appCount: Int,
        availableWidth: CGFloat,
        maxTileSize: CGFloat
    ) -> AppGridLayout {
        let count = max(appCount, 1)
        let safeWidth = max(1, availableWidth)
        let baselineSpacing = maxAppTileSpacing
        let tileByBaselineSpacing = (
            safeWidth - CGFloat(max(count - 1, 0)) * baselineSpacing
        ) / CGFloat(count)
        let tileSize = max(minAppTileSize, min(maxTileSize, tileByBaselineSpacing))
        let spacing: CGFloat
        if count <= 1 {
            spacing = 0
        } else {
            let fillSpacing = (
                safeWidth - CGFloat(count) * tileSize
            ) / CGFloat(count - 1)
            spacing = max(0, fillSpacing)
        }

        return AppGridLayout(
            tileSize: tileSize,
            spacing: spacing,
            columns: count,
            rows: 1
        )
    }

    private func advance(_ keyInput: KeyInput) {
        if keyInput == .tabForward || keyInput == .tabBackward {
            guard isPrimaryModifierLikelyPressed() else {
                logInputTrace(
                    "advance key=\(keyInput.debugName) dropped=modifierNotPressed action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
                )
                scheduleModifierReleaseConfirmation(trigger: "advance_without_modifier")
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let nowMs = now * 1_000
            if
                let lastCommittedTabAdvanceTimestamp,
                now - lastCommittedTabAdvanceTimestamp < tabAdvanceMinimumInterval
            {
                logInputTrace(
                    "advance key=\(keyInput.debugName) dropped=throttle nowMs=\(formatMilliseconds(nowMs)) deltaMs=\(formatMilliseconds((now - lastCommittedTabAdvanceTimestamp) * 1_000)) thresholdMs=\(formatMilliseconds(tabAdvanceMinimumInterval * 1_000))"
                )
                return
            }
            self.lastCommittedTabAdvanceTimestamp = now
            logInputTrace(
                "advance key=\(keyInput.debugName) accepted nowMs=\(formatMilliseconds(nowMs))"
            )
        }

        cancelPendingModifierReleaseConfirmation()
        model.handle(keyInput)
        RuntimeLog.info("Session", "advance key=\(keyInput.debugName) \(self.model.debugSelectionSummary())")
        updatePanelSize()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    private func installEventMonitors() {
        removeEventMonitors()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handleKeyDown(event) ? nil : event
        }

        localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return nil
        }

        globalFlagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    private func removeEventMonitors() {
        cancelPendingModifierReleaseConfirmation()
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let localFlagsChangedMonitor {
            NSEvent.removeMonitor(localFlagsChangedMonitor)
            self.localFlagsChangedMonitor = nil
        }
        if let globalFlagsChangedMonitor {
            NSEvent.removeMonitor(globalFlagsChangedMonitor)
            self.globalFlagsChangedMonitor = nil
        }
        if let delayedWindowLayerTimer {
            delayedWindowLayerTimer.invalidate()
            self.delayedWindowLayerTimer = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 48:
            if activeHotkeySessionKind == .inAppWindowSwitcher {
                return true
            }
            if SwitcherHotkeyPreferencesStore.load().mainKey == .tab {
                return true
            }
            advance(event.modifierFlags.contains(.shift) ? .tabBackward : .tabForward)
            return true
        case 123:
            advance(.leftArrow)
            return true
        case 124:
            advance(.rightArrow)
            return true
        case 125:
            advance(.downArrow)
            return true
        case 126:
            advance(.upArrow)
            return true
        case 36, 76:
            finishSelection()
            return true
        case 53:
            cancelSelection()
            return true
        default:
            if isTerminateSelectedAppShortcut(event) {
                terminateSelectedApp()
                return true
            }
            return false
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isPrimaryEvent = isPrimaryModifierFlagsEvent(event)
        guard isPrimaryEvent else { return }
        guard panel.isVisible else { return }
        logInputTrace(
            "flagsChanged keyCode=\(event.keyCode) action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        scheduleModifierReleaseConfirmation(trigger: "flags_changed")
    }

    private func scheduleModifierReleaseConfirmation(trigger: String) {
        if pendingModifierReleaseConfirmationTask != nil {
            logInputTrace(
                "releaseConfirm alreadyRunning trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
            return
        }
        logInputTrace(
            "releaseConfirm start trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds())) intervalMs=\(formatMilliseconds(Double(modifierReleaseConfirmationSampleIntervalNs) / 1_000_000)) samples=\(modifierReleaseConfirmationSampleCount)"
        )

        pendingModifierReleaseConfirmationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var releasedSampleCount = 0

            while true {
                try? await Task.sleep(nanoseconds: self.modifierReleaseConfirmationSampleIntervalNs)
                guard !Task.isCancelled else { return }
                guard self.panel.isVisible else {
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=panelHidden nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.pendingModifierReleaseConfirmationTask = nil
                    return
                }

                if self.isPrimaryModifierLikelyPressed() {
                    if releasedSampleCount > 0 {
                        self.logInputTrace(
                            "releaseConfirm reset trigger=\(trigger) releasedSamples=\(releasedSampleCount) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                        )
                    }
                    releasedSampleCount = 0
                    continue
                }
                releasedSampleCount += 1
                self.logInputTrace(
                    "releaseConfirm sample trigger=\(trigger) releasedSamples=\(releasedSampleCount)/\(self.modifierReleaseConfirmationSampleCount) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                if releasedSampleCount < self.modifierReleaseConfirmationSampleCount {
                    continue
                }

                self.pendingModifierReleaseConfirmationTask = nil
                self.logInputTrace(
                    "releaseConfirm confirmed trigger=\(trigger) action=finishSelection nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                self.finishSelection()
                return
            }
        }
    }

    private func cancelPendingModifierReleaseConfirmation() {
        guard let pendingModifierReleaseConfirmationTask else { return }
        logInputTrace(
            "releaseConfirm canceled nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        pendingModifierReleaseConfirmationTask.cancel()
        self.pendingModifierReleaseConfirmationTask = nil
    }

    private func isPrimaryModifierFlagsEvent(_ event: NSEvent) -> Bool {
        switch activePrimaryModifier() {
        case .option:
            return event.keyCode == UInt16(kVK_Option) || event.keyCode == UInt16(kVK_RightOption)
        case .control:
            return event.keyCode == UInt16(kVK_Control) || event.keyCode == UInt16(kVK_RightControl)
        case .command:
            return event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand)
        }
    }

    private func isPrimaryModifierPressedInHardwareState() -> Bool {
        switch activePrimaryModifier() {
        case .option:
            return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Option))
                || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightOption))
        case .control:
            return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Control))
                || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightControl))
        case .command:
            return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Command))
                || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightCommand))
        }
    }

    private func isPrimaryModifierLikelyPressed(event: NSEvent? = nil) -> Bool {
        if isPrimaryModifierPressedInHardwareState() {
            return true
        }
        guard let event else { return false }
        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return eventFlags.contains(activePrimaryModifierFlag())
    }

    private func scheduleDelayedWindowLayerEntryIfNeeded() {
        if let delayedWindowLayerTimer {
            delayedWindowLayerTimer.invalidate()
            self.delayedWindowLayerTimer = nil
        }
        guard autoEnterWindowLayerEnabled else { return }

        guard panel.isVisible else {
            RuntimeLog.info("AutoEnter", "skip panelHidden")
            return
        }
        guard model.canAutoEnterWindowLayer else {
            RuntimeLog.info("AutoEnter", "skip \(self.model.debugSelectionSummary())")
            return
        }
        RuntimeLog.info("AutoEnter", "schedule delay=\(self.windowLayerPresentationDelay)s \(self.model.debugSelectionSummary())")

        let timer = Timer(timeInterval: windowLayerPresentationDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.panel.isVisible else { return }
                if self.model.autoEnterWindowLayerIfPossible() {
                    RuntimeLog.info("AutoEnter", "entered window layer \(self.model.debugSelectionSummary())")
                    self.updatePanelSize()
                } else {
                    RuntimeLog.info("AutoEnter", "timer fired but stay app layer \(self.model.debugSelectionSummary())")
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        delayedWindowLayerTimer = timer
    }

    private func terminateSelectedApp() {
        switch model.terminateSelectedApp() {
        case .notHandled:
            RuntimeLog.info("Session", "terminate selected app ignored")
            NSSound.beep()
        case .updatedSession:
            RuntimeLog.info("Session", "terminate selected app \(self.model.debugSelectionSummary())")
            updatePanelSize()
            scheduleDelayedWindowLayerEntryIfNeeded()
        case .sessionEnded:
            RuntimeLog.info("Session", "terminate selected app ended session")
            removeEventMonitors()
            panel.orderOut(nil)
            activeHotkeySessionKind = nil
        }
    }

    private func activePrimaryModifier() -> SwitcherPrimaryModifier {
        if activeHotkeySessionKind == .inAppWindowSwitcher {
            return .control
        }
        return SwitcherHotkeyPreferencesStore.load().primaryModifier
    }

    private func activePrimaryModifierFlag() -> NSEvent.ModifierFlags {
        activePrimaryModifier().eventModifierFlag
    }

    private func isTerminateSelectedAppShortcut(_ event: NSEvent) -> Bool {
        guard activeHotkeySessionKind != .inAppWindowSwitcher else { return false }
        let hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()
        guard event.keyCode == hotkeyConfiguration.quitKeyCode else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(hotkeyConfiguration.primaryModifier.eventModifierFlag) else { return false }
        guard !flags.contains(.shift) else { return false }

        switch hotkeyConfiguration.primaryModifier {
        case .option:
            return !flags.contains(.command) && !flags.contains(.control)
        case .control:
            return !flags.contains(.command) && !flags.contains(.option)
        case .command:
            return !flags.contains(.control) && !flags.contains(.option)
        }
    }
}

@MainActor
final class LiveSwitcherModel: ObservableObject {
    enum TerminateSelectedAppResult {
        case notHandled
        case updatedSession
        case sessionEnded
    }

    @Published private(set) var session: SwitcherSession?
    @Published private(set) var appGridTileSize: CGFloat = 68
    @Published private(set) var appGridSpacing: CGFloat = 10
    @Published private(set) var previewSectionHeight: CGFloat = 220
    @Published private(set) var overlayStyle: SwitcherOverlayStyle = .appAndWindow

    private let snapshotProvider = RuntimeSnapshotProvider()
    private let activator = RuntimeActivator()
    private let iconProvider = AppIconProvider()

    private var runtimeContextsByID: [String: RuntimeAppContext] = [:]
    private var rememberedWindowIDByAppID: [String: String] = [:]
    private var previewCaptureAttemptedKeys: Set<String> = []
    private var autoEnterSuppressedAppID: String?
    private var titleBarStyleInferenceEnabled = false

    init() {}

    var appCount: Int {
        session?.apps.count ?? 0
    }

    var previewWindowCount: Int {
        guard let session else { return 0 }
        guard case .windowCycle(let appID) = session.mode else { return 0 }
        guard let app = session.apps.first(where: { $0.id == appID }) else { return 0 }
        return app.windows.count
    }

    func updateAppGridLayout(tileSize: CGFloat, spacing: CGFloat) {
        let normalizedTileSize = max(1, min(90, tileSize))
        let normalizedSpacing = max(0, spacing)
        guard appGridTileSize != normalizedTileSize || appGridSpacing != normalizedSpacing else {
            return
        }
        appGridTileSize = normalizedTileSize
        appGridSpacing = normalizedSpacing
    }

    func updatePreviewSectionHeight(_ height: CGFloat) {
        let normalizedHeight = max(130, min(220, height))
        guard previewSectionHeight != normalizedHeight else { return }
        previewSectionHeight = normalizedHeight
    }

    var isPreviewLayerMode: Bool {
        guard let session else { return false }
        if case .windowCycle = session.mode {
            return true
        }
        return false
    }

    var isWindowOnlyOverlay: Bool {
        overlayStyle == .windowOnly
    }

    private func previewData(
        for appID: String,
        window: WindowCandidate
    ) -> (image: NSImage?, titleBarStyle: WindowTitleBarStyleGuess?) {
        guard var appContext = runtimeContextsByID[appID] else {
            return (image: nil, titleBarStyle: nil)
        }
        guard var windowContext = appContext.windowsByID[window.id] else {
            return (image: nil, titleBarStyle: nil)
        }
        if let cached = windowContext.previewImage {
            return (
                image: cached,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }

        let attemptKey = "\(appID)#\(window.id)"
        if previewCaptureAttemptedKeys.contains(attemptKey) {
            return (
                image: nil,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }
        previewCaptureAttemptedKeys.insert(attemptKey)

        RuntimeLog.info(
            "Preview",
            "attempt appID=\(appID) pid=\(appContext.runningApp.processIdentifier) windowID=\(window.id) mappedCG=\(windowContext.cgWindowID.map(String.init) ?? "nil") title=\(windowContext.title)"
        )
        guard
            let capture = RuntimeWindowPreviewProvider.captureWindowPreview(
                preferredWindowID: windowContext.cgWindowID,
                ownerPID: appContext.runningApp.processIdentifier,
                preferredTitle: windowContext.title,
                inferTitleBarStyle: titleBarStyleInferenceEnabled
            )
        else {
            RuntimeLog.info("Preview", "attempt failed appID=\(appID) windowID=\(window.id)")
            return (
                image: nil,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }

        windowContext.cgWindowID = capture.resolvedWindowID
        windowContext.previewImage = capture.image
        windowContext.inferredTitleBarStyle = capture.titleBarStyle
        var windowsByID = appContext.windowsByID
        windowsByID[window.id] = windowContext
        appContext = RuntimeAppContext(
            appID: appContext.appID,
            runningApp: appContext.runningApp,
            windowsByID: windowsByID
        )
        runtimeContextsByID[appID] = appContext
        RuntimeLog.info(
            "Preview",
            "attempt success appID=\(appID) windowID=\(window.id) resolvedCG=\(capture.resolvedWindowID) titleBarStyle=\(capture.titleBarStyle?.rawValue ?? "nil")"
        )
        return (
            image: capture.image,
            titleBarStyle: titleBarStyleInferenceEnabled ? capture.titleBarStyle : nil
        )
    }

    fileprivate func windowPreviewItems() -> [WindowPreviewItem] {
        guard let session else { return [] }
        guard case .windowCycle(let appID) = session.mode else { return [] }
        guard let app = session.apps.first(where: { $0.id == appID }) else { return [] }

        let selectedIndex = session.selectedWindowIndexByAppID[appID] ?? 0
        return app.windows.enumerated().map { index, window in
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = overlayStyle == .windowOnly
                ? "Window \(index + 1)"
                : app.displayName
            let preview = previewData(for: appID, window: window)
            return WindowPreviewItem(
                id: window.id,
                title: title.isEmpty ? fallbackTitle : title,
                image: preview.image,
                titleBarStyle: preview.titleBarStyle,
                isSelected: index == selectedIndex
            )
        }
    }

    var selectedApp: AppSwitchCandidate? {
        session?.selectedApp
    }

    var canAutoEnterWindowLayer: Bool {
        guard let session else { return false }
        if case .windowCycle = session.mode {
            return false
        }
        if autoEnterSuppressedAppID == session.selectedApp.id {
            return false
        }
        return session.selectedApp.windows.count >= 2
    }

    func icon(for app: AppSwitchCandidate) -> NSImage? {
        iconProvider.icon(for: app, context: runtimeContextsByID[app.id])
    }

    func startSession(triggerDirection: CycleDirection) -> Bool {
        overlayStyle = .appAndWindow
        titleBarStyleInferenceEnabled = false
        return loadSnapshot(triggerDirection: triggerDirection, preferredSelectedAppID: nil)
    }

    func startFocusedAppWindowSession(triggerDirection: CycleDirection) -> Bool {
        overlayStyle = .windowOnly
        titleBarStyleInferenceEnabled = true
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            resetSessionState()
            return false
        }

        let frontmostAppID = frontmostApp.bundleIdentifier
            ?? "pid:\(frontmostApp.processIdentifier)"
        let snapshot = snapshotProvider.snapshot()
        guard
            let appCandidate = snapshot.apps.first(where: { $0.id == frontmostAppID }),
            let context = snapshot.contextsByID[frontmostAppID]
        else {
            resetSessionState()
            return false
        }
        guard !appCandidate.windows.isEmpty else {
            resetSessionState()
            return false
        }

        runtimeContextsByID = [frontmostAppID: context]
        previewCaptureAttemptedKeys = []
        autoEnterSuppressedAppID = nil
        let preferences = SwitcherBehaviorPreferencesStore.loadSwitcherPreferences()
        var rebuiltSession = SwitcherSession(
            apps: [appCandidate],
            preferences: preferences,
            triggerDirection: triggerDirection,
            rememberedWindowIDByAppID: rememberedWindowIDByAppID
        )
        guard rebuiltSession.enterWindowCycle(allowSingleWindow: true) else {
            resetSessionState()
            return false
        }

        session = rebuiltSession
        return true
    }

    func terminateSelectedApp() -> TerminateSelectedAppResult {
        guard let currentSession = session else { return .notHandled }

        let selectedApp = currentSession.selectedApp
        guard let context = runtimeContextsByID[selectedApp.id] else { return .notHandled }

        let preferredSelectedAppID = preferredAppIDAfterRemovingSelectedApp(from: currentSession)
        let sent = context.runningApp.terminate()
        RuntimeLog.info(
            "Session",
            "terminate request app=\(selectedApp.displayName) appID=\(selectedApp.id) sent=\(sent)"
        )
        guard sent else { return .notHandled }

        if loadSnapshot(triggerDirection: .forward, preferredSelectedAppID: preferredSelectedAppID) {
            return .updatedSession
        }
        return .sessionEnded
    }

    private func loadSnapshot(
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?
    ) -> Bool {
        let snapshot = snapshotProvider.snapshot()
        guard !snapshot.apps.isEmpty else {
            resetSessionState()
            return false
        }

        runtimeContextsByID = snapshot.contextsByID
        previewCaptureAttemptedKeys = []
        autoEnterSuppressedAppID = nil
        let preferences = SwitcherBehaviorPreferencesStore.loadSwitcherPreferences()
        var rebuiltSession = SwitcherSession(
            apps: snapshot.apps,
            preferences: preferences,
            triggerDirection: triggerDirection,
            rememberedWindowIDByAppID: rememberedWindowIDByAppID
        )

        if
            let preferredSelectedAppID,
            rebuiltSession.apps.contains(where: { $0.id == preferredSelectedAppID })
        {
            for _ in 0..<rebuiltSession.apps.count {
                if rebuiltSession.selectedApp.id == preferredSelectedAppID {
                    break
                }
                rebuiltSession.handle(.tabForward)
            }
        }

        session = rebuiltSession
        return true
    }

    private func preferredAppIDAfterRemovingSelectedApp(from session: SwitcherSession) -> String? {
        guard session.apps.count > 1 else { return nil }
        let remainingAppIDs = session.apps.map(\.id).filter { $0 != session.selectedApp.id }
        guard !remainingAppIDs.isEmpty else { return nil }
        let preferredIndex = min(session.selectedAppIndex, remainingAppIDs.count - 1)
        return remainingAppIDs[preferredIndex]
    }

    func handle(_ keyInput: KeyInput) {
        guard var session else { return }
        let previousMode = session.mode
        let previousAppID = session.selectedApp.id
        session.handle(keyInput)

        let currentAppID = session.selectedApp.id
        if currentAppID != previousAppID {
            autoEnterSuppressedAppID = nil
        }

        if
            case .windowCycle(let appID) = previousMode,
            case .appCycle = session.mode,
            keyInput == .upArrow
        {
            autoEnterSuppressedAppID = appID
        }

        if
            case .appCycle = previousMode,
            case .windowCycle = session.mode,
            keyInput == .downArrow
        {
            autoEnterSuppressedAppID = nil
        }
        self.session = session
    }

    @discardableResult
    func autoEnterWindowLayerIfPossible() -> Bool {
        guard var session else { return false }
        if case .windowCycle = session.mode {
            return false
        }
        if autoEnterSuppressedAppID == session.selectedApp.id {
            return false
        }
        guard session.selectedApp.windows.count >= 2 else { return false }
        session.enterWindowCycleIfPossible()
        self.session = session
        if case .windowCycle = session.mode {
            return true
        }
        return false
    }

    func debugSelectionSummary() -> String {
        guard let session else { return "session=nil" }
        return "app=\(session.selectedApp.displayName) windows=\(session.selectedApp.windows.count) mode=\(session.mode.debugName)"
    }

    func commitSelection() {
        guard var session else { return }
        let target = session.commitSelection()
        rememberedWindowIDByAppID = session.rememberedWindowIDByAppID
        self.session = nil

        guard let target else {
            overlayStyle = .appAndWindow
            resetRuntimeState()
            return
        }
        activator.activate(target: target, contextsByID: runtimeContextsByID)
        overlayStyle = .appAndWindow
        resetRuntimeState()
    }

    func cancelSelection() {
        resetSessionState()
    }

    private func resetSessionState() {
        session = nil
        overlayStyle = .appAndWindow
        resetRuntimeState()
    }

    private func resetRuntimeState() {
        runtimeContextsByID = [:]
        previewCaptureAttemptedKeys = []
        autoEnterSuppressedAppID = nil
        titleBarStyleInferenceEnabled = false
    }
}

private extension SessionMode {
    var debugName: String {
        switch self {
        case .appCycle:
            return "appCycle"
        case .groupCycle:
            return "groupCycle"
        case .windowCycle(let appID):
            return "windowCycle(\(appID))"
        }
    }
}

private extension KeyInput {
    var debugName: String {
        switch self {
        case .tabForward:
            return "tabForward"
        case .tabBackward:
            return "tabBackward"
        case .upArrow:
            return "upArrow"
        case .downArrow:
            return "downArrow"
        case .leftArrow:
            return "leftArrow"
        case .rightArrow:
            return "rightArrow"
        }
    }
}

private extension CycleDirection {
    var debugName: String {
        switch self {
        case .forward:
            return "forward"
        case .backward:
            return "backward"
        }
    }
}

enum SwitcherOverlayStyle {
    case appAndWindow
    case windowOnly
}

private struct SwitcherPanelRootView: View {
    @ObservedObject var model: LiveSwitcherModel
    @ObservedObject private var systemTheme = SystemThemeState.shared
    @AppStorage(AppPreferenceKeys.themeMode)
    private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue

    private var themeMode: ThemeMode {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
    }

    private var resolvedColorScheme: ColorScheme {
        themeMode.resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    var body: some View {
        ZStack {
            if let session = model.session {
                CommandTabOverlay(
                    session: session,
                    overlayStyle: model.overlayStyle,
                    isPreviewLayer: model.isPreviewLayerMode,
                    previewSectionHeight: model.previewSectionHeight,
                    windowPreviewItems: model.windowPreviewItems(),
                    selectedApp: model.selectedApp,
                    appTileSize: model.appGridTileSize,
                    appTileSpacing: model.appGridSpacing,
                    iconForApp: { app in
                        model.icon(for: app)
                    }
                )
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .preferredColorScheme(resolvedColorScheme)
        .animation(.none, value: resolvedColorScheme)
    }
}

private struct CommandTabOverlay: View {
    let session: SwitcherSession
    let overlayStyle: SwitcherOverlayStyle
    let isPreviewLayer: Bool
    let previewSectionHeight: CGFloat
    let windowPreviewItems: [WindowPreviewItem]
    let selectedApp: AppSwitchCandidate?
    let appTileSize: CGFloat
    let appTileSpacing: CGFloat
    let iconForApp: (AppSwitchCandidate) -> NSImage?
    @Environment(\.colorScheme) private var colorScheme

    private var isWindowOnlyMode: Bool {
        overlayStyle == .windowOnly
    }

    private var showsAppStrip: Bool {
        overlayStyle == .appAndWindow
    }

    private func previewCardWidth(availableWidth: CGFloat, itemCount: Int) -> CGFloat {
        let count = max(itemCount, 1)
        let spacing: CGFloat = 12
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let rawWidth = (availableWidth - totalSpacing) / CGFloat(count)
        return max(120, min(360, rawWidth))
    }

    private func previewCardHeight(for cardWidth: CGFloat) -> CGFloat {
        let maxHeight: CGFloat = showsAppStrip ? 220 : 248
        return max(130, min(maxHeight, cardWidth * 0.62))
    }

    private struct WindowOnlyGridLayout {
        let columns: Int
        let rows: Int
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
    }

    private func windowOnlyGridLayout(
        availableSize: CGSize,
        itemCount: Int
    ) -> WindowOnlyGridLayout {
        let count = max(itemCount, 1)
        let maxColumns = min(8, count)
        let minCardWidth: CGFloat = 120
        let titleBarHeight: CGFloat = 30
        let minPreviewHeight: CGFloat = 74
        let minCardHeight: CGFloat = titleBarHeight + minPreviewHeight
        let maxCardWidth: CGFloat = 460
        let previewAspectRatio: CGFloat = 1.58
        let columnSpacing: CGFloat = 24
        let rowSpacing: CGFloat = 28
        let horizontalPadding: CGFloat = max(14, min(64, availableSize.width * 0.04))
        let verticalPadding: CGFloat = max(12, min(52, availableSize.height * 0.05))
        let usableWidth = max(220, availableSize.width - horizontalPadding * 2)
        let usableHeight = max(160, availableSize.height - verticalPadding * 2)

        var bestLayout: (columns: Int, rows: Int, cardWidth: CGFloat, cardHeight: CGFloat, score: CGFloat)?

        for columns in 1...maxColumns {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let totalColumnSpacing = CGFloat(max(columns - 1, 0)) * columnSpacing
            let totalRowSpacing = CGFloat(max(rows - 1, 0)) * rowSpacing
            let cellWidth = (usableWidth - totalColumnSpacing) / CGFloat(columns)
            let cellHeight = (usableHeight - totalRowSpacing) / CGFloat(rows)
            guard cellWidth > 0, cellHeight > 0 else { continue }

            var cardWidth = min(maxCardWidth, cellWidth)
            var cardHeight = cardWidth / previewAspectRatio + titleBarHeight

            if cardHeight > cellHeight {
                cardHeight = cellHeight
                cardWidth = max(1, (cardHeight - titleBarHeight) * previewAspectRatio)
            }
            guard cardWidth > 0, cardHeight > 0 else { continue }
            if cardWidth < minCardWidth || cardHeight < minCardHeight {
                continue
            }

            let score = cardWidth * cardHeight
            if let bestLayout, bestLayout.score >= score {
                continue
            }
            bestLayout = (columns, rows, cardWidth, cardHeight, score)
        }

        let resolved = bestLayout ?? {
            let columns = min(maxColumns, max(1, Int(round(sqrt(Double(count))))))
            let rows = Int(ceil(Double(count) / Double(columns)))
            let totalColumnSpacing = CGFloat(max(columns - 1, 0)) * columnSpacing
            let totalRowSpacing = CGFloat(max(rows - 1, 0)) * rowSpacing
            let cellWidth = max(1, (usableWidth - totalColumnSpacing) / CGFloat(columns))
            let cellHeight = max(1, (usableHeight - totalRowSpacing) / CGFloat(rows))
            let cardWidth = min(maxCardWidth, cellWidth)
            let cardHeight = min(cellHeight, cardWidth / previewAspectRatio + titleBarHeight)
            return (columns, rows, cardWidth, cardHeight, cardWidth * cardHeight)
        }()

        return WindowOnlyGridLayout(
            columns: resolved.columns,
            rows: resolved.rows,
            cardWidth: resolved.cardWidth,
            cardHeight: resolved.cardHeight,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )
    }

    private var selectedWindowPreviewID: String? {
        windowPreviewItems.first(where: \.isSelected)?.id
    }

    private var appGridColumns: [GridItem] {
        let count = max(session.apps.count, 1)
        return Array(
            repeating: GridItem(
                .fixed(appTileSize),
                spacing: appTileSpacing,
                alignment: .leading
            ),
            count: count
        )
    }

    private func scrollToSelectedPreview(using proxy: ScrollViewProxy) {
        guard let selectedWindowPreviewID else { return }
        proxy.scrollTo(selectedWindowPreviewID, anchor: .center)
    }

    @ViewBuilder
    private var standardOverlayBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(
                columns: appGridColumns,
                alignment: .leading,
                spacing: appTileSpacing
            ) {
                ForEach(Array(session.apps.enumerated()), id: \.element.id) { index, app in
                    AppTileView(
                        app: app,
                        isSelected: index == session.selectedAppIndex,
                        size: appTileSize,
                        icon: iconForApp(app)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)

            if isPreviewLayer {
                GeometryReader { proxy in
                    let cardWidth = previewCardWidth(
                        availableWidth: max(0, proxy.size.width - 4),
                        itemCount: windowPreviewItems.count
                    )
                    let cardHeight = previewCardHeight(for: cardWidth)

                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(windowPreviewItems) { preview in
                                    WindowPreviewCard(
                                        image: preview.image,
                                        title: preview.title,
                                        appIcon: selectedApp.flatMap(iconForApp),
                                        isSelected: preview.isSelected,
                                        width: cardWidth,
                                        height: cardHeight
                                    )
                                    .id(preview.id)
                                }
                            }
                            .padding(.horizontal, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onAppear {
                            scrollToSelectedPreview(using: scrollProxy)
                        }
                        .onChange(of: selectedWindowPreviewID) { _ in
                            scrollToSelectedPreview(using: scrollProxy)
                        }
                    }
                }
                .frame(height: previewSectionHeight)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color.black : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    @ViewBuilder
    private var windowOnlyOverlayBody: some View {
        GeometryReader { proxy in
            let layout = windowOnlyGridLayout(
                availableSize: proxy.size,
                itemCount: windowPreviewItems.count
            )
            let columns = Array(
                repeating: GridItem(
                    .fixed(layout.cardWidth),
                    spacing: layout.columnSpacing,
                    alignment: .top
                ),
                count: layout.columns
            )

            VStack(spacing: 0) {
                Spacer(minLength: layout.verticalPadding)
                LazyVGrid(
                    columns: columns,
                    alignment: .center,
                    spacing: layout.rowSpacing
                ) {
                    ForEach(windowPreviewItems) { preview in
                        WindowOnlyPreviewCard(
                            image: preview.image,
                            title: preview.title,
                            titleBarStyle: preview.titleBarStyle,
                            isSelected: preview.isSelected,
                            width: layout.cardWidth,
                            height: layout.cardHeight
                        )
                        .id(preview.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, layout.horizontalPadding)
                Spacer(minLength: layout.verticalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    var body: some View {
        if isWindowOnlyMode {
            windowOnlyOverlayBody
        } else {
            standardOverlayBody
        }
    }
}

private struct WindowPreviewItem: Identifiable {
    let id: String
    let title: String
    let image: NSImage?
    let titleBarStyle: WindowTitleBarStyleGuess?
    let isSelected: Bool
}

private struct WindowPreviewCard: View {
    let image: NSImage?
    let title: String
    let appIcon: NSImage?
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let titleAreaHeight: CGFloat = 26
    private var previewAreaHeight: CGFloat {
        max(84, height - titleAreaHeight)
    }
    private var previewBorderColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.accentColor.opacity(0.95) : Color.accentColor.opacity(0.72)
        }
        return colorScheme == .dark ? Color.white.opacity(0.20) : Color.primary.opacity(0.12)
    }
    private var previewBorderWidth: CGFloat {
        if isSelected {
            return colorScheme == .dark ? 2.6 : 2.1
        }
        return 1
    }
    private var previewGlowColor: Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.accentColor.opacity(0.42) : Color.accentColor.opacity(0.18)
    }
    private var titleForegroundColor: Color {
        if colorScheme == .dark {
            return isSelected ? Color.white.opacity(0.98) : Color.white.opacity(0.80)
        }
        return isSelected ? Color.primary : Color.primary.opacity(0.86)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    (colorScheme == .dark ? Color.black : Color.white)

                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 84, height: 84)
                            .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    }
                }
            }
            .frame(width: width, height: previewAreaHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(previewBorderColor, lineWidth: previewBorderWidth)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .inset(by: 1)
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.16),
                                lineWidth: 0.8
                            )
                    }
                }
            )
            .shadow(color: previewGlowColor, radius: isSelected ? 14 : 0, y: 0)
            .shadow(color: .black.opacity(isSelected ? 0.16 : 0.12), radius: isSelected ? 12 : 10, y: 5)

            Text(title)
                .lineLimit(1)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(titleForegroundColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 4)
        }
        .frame(width: width, height: height, alignment: .top)
    }
}

private struct WindowOnlyPreviewCard: View {
    let image: NSImage?
    let title: String
    let titleBarStyle: WindowTitleBarStyleGuess?
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let titleAreaHeight: CGFloat = 30
    private var previewAreaHeight: CGFloat {
        max(1, height - titleAreaHeight)
    }
    private var usesDarkTitleBar: Bool {
        if let titleBarStyle {
            return titleBarStyle == .dark
        }
        return colorScheme == .dark
    }
    private var titleForegroundColor: Color {
        if usesDarkTitleBar {
            return Color.white.opacity(isSelected ? 0.98 : 0.92)
        }
        return Color.black.opacity(isSelected ? 0.84 : 0.74)
    }
    private var titleBarBackgroundColor: Color {
        if usesDarkTitleBar {
            return Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1.0))
        }
        return Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1.0))
    }
    private var titleBarDividerColor: Color {
        if usesDarkTitleBar {
            return Color.white.opacity(0.14)
        }
        return Color.black.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .lineLimit(1)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(titleForegroundColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 10)
                .frame(height: titleAreaHeight)
                .background(titleBarBackgroundColor)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(titleBarDividerColor)
                        .frame(height: 1)
                }
                .zIndex(1)

            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: usesDarkTitleBar
                            ? [Color.white.opacity(0.08), Color.white.opacity(0.03)]
                            : [Color.black.opacity(0.06), Color.black.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "macwindow")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: width, height: previewAreaHeight)
            .clipped()
        }
        .frame(width: width, height: height, alignment: .top)
        .background(Color.black.opacity(usesDarkTitleBar ? 0.20 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.28),
                    lineWidth: isSelected ? 2.1 : 1.0
                )
        )
        .shadow(
            color: Color.black.opacity(isSelected ? 0.22 : 0.12),
            radius: isSelected ? 14 : 9,
            y: isSelected ? 8 : 5
        )
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

private struct AppTileView: View {
    let app: AppSwitchCandidate
    let isSelected: Bool
    let size: CGFloat
    let icon: NSImage?

    var body: some View {
        let cornerRadius = max(1, min(16, size * 0.18))
        let iconSize = max(1, min(56, size * 0.58))
        let fallbackFontSize = max(1, min(28, size * 0.32))
        let fallbackDotSize = max(1, size * 0.38)

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
            } else {
                if size >= 11 {
                    Text(app.displayName.prefix(1).uppercased())
                        .font(.system(size: fallbackFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: fallbackDotSize, height: fallbackDotSize)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
