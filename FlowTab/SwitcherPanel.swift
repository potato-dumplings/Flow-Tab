import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

private final class SwitcherOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

enum SwitcherPanelWindowConfiguration {
    enum PresentationBehaviorMode {
        case allSpaces
        case activeSpaceMove
    }

    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let level: NSWindow.Level = .statusBar
    static let fallbackPresentationLevel = NSWindow.Level(
        rawValue: Int(CGShieldingWindowLevel()) + 1
    )
    // Keep the proven panel presentation behavior and only add the explicit
    // cross-application fullscreen-space eligibility we were missing.
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle,
        .stationary,
        .canJoinAllApplications
    ]

    static func presentationLevel(
        frontmostWindowIsFullScreen: Bool,
        requiresFallbackElevation: Bool = false
    ) -> NSWindow.Level {
        guard frontmostWindowIsFullScreen || requiresFallbackElevation else { return level }
        return fallbackPresentationLevel
    }

    static func presentationCollectionBehavior(
        mode: PresentationBehaviorMode = .allSpaces
    ) -> NSWindow.CollectionBehavior {
        switch mode {
        case .allSpaces:
            return collectionBehavior
        case .activeSpaceMove:
            var behavior = collectionBehavior
            behavior.remove(.canJoinAllSpaces)
            behavior.insert(.moveToActiveSpace)
            return behavior
        }
    }
}

private enum FrontmostWindowInspector {
    private static let fullScreenAttribute = "AXFullScreen" as CFString
    private static let titleAttribute = kAXTitleAttribute as CFString

    struct Inspection {
        let axTrusted: Bool
        let appName: String
        let pid: pid_t?
        let focusedWindowAvailable: Bool
        let focusedWindowTitle: String?
        let fullScreenDetected: Bool
        let failureReason: String?
    }

    static func inspect() -> Inspection {
        guard AccessibilityPermissionChecker.isTrusted() else {
            return Inspection(
                axTrusted: false,
                appName: "unavailable",
                pid: nil,
                focusedWindowAvailable: false,
                focusedWindowTitle: nil,
                fullScreenDetected: false,
                failureReason: "ax_not_trusted"
            )
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return Inspection(
                axTrusted: true,
                appName: "unavailable",
                pid: nil,
                focusedWindowAvailable: false,
                focusedWindowTitle: nil,
                fullScreenDetected: false,
                failureReason: "frontmost_app_unavailable"
            )
        }

        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &focusedWindowValue
            ) == .success,
            let focusedWindowValue
        else {
            return Inspection(
                axTrusted: true,
                appName: appName,
                pid: app.processIdentifier,
                focusedWindowAvailable: false,
                focusedWindowTitle: nil,
                fullScreenDetected: false,
                failureReason: "focused_window_unavailable"
            )
        }
        let focusedWindow = focusedWindowValue as! AXUIElement

        var titleValue: CFTypeRef?
        let focusedWindowTitle: String?
        if
            AXUIElementCopyAttributeValue(
                focusedWindow,
                titleAttribute,
                &titleValue
            ) == .success,
            let title = titleValue as? String,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            focusedWindowTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            focusedWindowTitle = nil
        }

        var fullScreenValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                focusedWindow,
                fullScreenAttribute,
                &fullScreenValue
            ) == .success,
            let number = fullScreenValue as? NSNumber
        else {
            return Inspection(
                axTrusted: true,
                appName: appName,
                pid: app.processIdentifier,
                focusedWindowAvailable: true,
                focusedWindowTitle: focusedWindowTitle,
                fullScreenDetected: false,
                failureReason: "fullscreen_attribute_unavailable"
            )
        }
        return Inspection(
            axTrusted: true,
            appName: appName,
            pid: app.processIdentifier,
            focusedWindowAvailable: true,
            focusedWindowTitle: focusedWindowTitle,
            fullScreenDetected: number.boolValue,
            failureReason: nil
        )
    }

    static func frontmostWindowIsFullScreen() -> Bool {
        inspect().fullScreenDetected
    }
}

@MainActor
final class SwitcherPanelController {
    private enum HotkeySessionKind {
        case globalAppSwitcher
        case inAppWindowSwitcher
    }

    private let model: LiveSwitcherModel
    private let panel: NSPanel

    private var keyDownMonitor: Any?
    private var localFlagsChangedMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var globalFlagsChangedMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var appDidResignActiveObserver: NSObjectProtocol?
    private var activeSpaceDidChangeObserver: NSObjectProtocol?
    private var workspaceDidTerminateApplicationObserver: NSObjectProtocol?
    private var panelOcclusionObserver: NSObjectProtocol?
    private var panelDidResignKeyObserver: NSObjectProtocol?
    private var suppressHotkeyReplayUntilRelease = false
    private var suppressHotkeyReplayTask: Task<Void, Never>?
    private var pendingModifierReleaseConfirmationTask: Task<Void, Never>?
    private var panelPresentationRecoveryTask: Task<Void, Never>?
    private var delayedWindowLayerTimer: Timer?
    private var lastCommittedTabAdvanceTimestamp: TimeInterval?
    private var ignoreHotkeyPressesUntil: TimeInterval = 0
    private var ignoreActiveSpaceChangesUntil: TimeInterval = 0
    private var suppressApplicationActivationUntil: TimeInterval = 0
    private var windowLayerPresentationDelay: TimeInterval {
        windowLayerPresentationDelayOverride ?? WindowLayerPreferencesStore.loadAutoEnterDelay()
    }
    private let modifierReleaseConfirmationSampleIntervalNs: UInt64 = 25_000_000
    private let modifierReleaseConfirmationSampleCount: Int = 2
    private let postFinishHotkeyIgnoreWindow: TimeInterval = 0.02
    private let activeSpaceChangeIgnoreWindow: TimeInterval = 0.35
    private let activeSpaceMigrationActivationSuppressionWindow: TimeInterval = 0.5
    private let initialPresentationRecoveryAttemptDelaysNs: [UInt64] = [50_000_000, 150_000_000]
    private let interruptionPresentationRecoveryAttemptDelaysNs: [UInt64] = [
        0,
        50_000_000,
        150_000_000,
        300_000_000
    ]
    private let panelPresentationRecoveryReorderDelayNs: UInt64 = 10_000_000
    private let autoEnterWindowLayerEnabled = true
    private let tabAdvanceMinimumInterval: TimeInterval = 0.016
    private let panelScreenMargin: CGFloat = 80
    private let windowOnlyOverlayScreenMargin: CGFloat = 20
    private let appLayerMinimumWidth: CGFloat = 440
    private let overlayHorizontalInset: CGFloat = 64
    private let appLayerStaticHeight: CGFloat = 56
    private let appLayerSearchHeaderExtraHeight: CGFloat = 68
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
    private let searchResultRowHeight: CGFloat = 40
    private let searchResultVisibleRowLimit: Int = 8
    private let searchHeaderHeight: CGFloat = 62
    private var activeHotkeySessionKind: HotkeySessionKind?
    private var activePresentationScreen: NSScreen?
    private var terminateSelectedAppTask: Task<Void, Never>?

    var panelVisibilityOverride: Bool?
    var panelOcclusionStateOverride: NSWindow.OcclusionState?
    var appIsActiveOverride: Bool?
    var globalPrimaryModifierPressedOverride: Bool?
    var inAppPrimaryModifierPressedOverride: Bool?
    var globalMainKeyPressedOverride: Bool?
    var inAppMainKeyPressedOverride: Bool?
    var panelContainsPointOverride: ((NSPoint) -> Bool)?
    var windowLayerPresentationDelayOverride: TimeInterval?
    var hideNonPanelWindowsOverride: (() -> Void)?
    var activateApplicationIgnoringOtherAppsOverride: (() -> Void)?

    private var searchFeatureEnabled: Bool {
        SearchInteractionPreferencesStore.loadIsEnabled()
    }

    private var isPanelPresented: Bool {
        panelVisibilityOverride ?? panel.isVisible
    }

    private var isPanelVisibleToUser: Bool {
        guard isPanelPresented else { return false }
        if panelVisibilityOverride != nil, panelOcclusionStateOverride == nil {
            return true
        }
        return resolvedPanelOcclusionState.contains(.visible)
    }

    private var resolvedPanelOcclusionState: NSWindow.OcclusionState {
        panelOcclusionStateOverride ?? panel.occlusionState
    }

    private var isAppCurrentlyActive: Bool {
        appIsActiveOverride ?? NSApp.isActive
    }

    private var hasActivePresentationSession: Bool {
        activeHotkeySessionKind != nil && model.session != nil
    }

    init() {
        model = LiveSwitcherModel()
        panel = SwitcherOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 290),
            styleMask: SwitcherPanelWindowConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.identifier = NSUserInterfaceItemIdentifier(AppWindowCoordinator.switcherPanelWindowIdentifier)
        panel.level = SwitcherPanelWindowConfiguration.level
        panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior()
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        let hostingView = NSHostingView(rootView: SwitcherPanelRootView(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        model.onSearchStateChanged = { [weak self] in
            guard let self else { return }
            guard self.isPanelPresented else { return }
            self.updatePanelSize()
        }
        model.onSessionLayoutChanged = { [weak self] in
            guard let self else { return }
            guard self.isPanelPresented else { return }
            guard self.model.session != nil else {
                self.endPresentationSession()
                return
            }
            self.updatePanelSize()
        }

        appDidResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationDidResignActive()
            }
        }
        activeSpaceDidChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActiveSpaceDidChange()
            }
        }
        workspaceDidTerminateApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }
            let appID = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                self?.model.handleApplicationTerminated(appID: appID, pid: pid)
            }
        }
        panelOcclusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePanelOcclusionStateDidChange()
            }
        }
        panelDidResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePanelDidResignKey()
            }
        }
    }

    var modelForTesting: LiveSwitcherModel {
        model
    }

    @discardableResult
    func handleKeyDownForTesting(_ event: NSEvent) -> Bool {
        handleKeyDown(event)
    }

    @discardableResult
    func beginGlobalHotkeySessionForTesting(
        triggerDirection: CycleDirection = .forward
    ) -> Bool {
        guard model.startSession(triggerDirection: triggerDirection) else { return false }
        activeHotkeySessionKind = .globalAppSwitcher
        lastCommittedTabAdvanceTimestamp = nil
        panelVisibilityOverride = true
        updatePanelPresentationLevel(trigger: "testing_global_show")
        return true
    }

    @discardableResult
    func beginInAppWindowHotkeySessionForTesting(
        triggerDirection: CycleDirection = .forward
    ) -> Bool {
        guard model.startFocusedAppWindowSession(triggerDirection: triggerDirection) else { return false }
        activeHotkeySessionKind = .inAppWindowSwitcher
        lastCommittedTabAdvanceTimestamp = nil
        panelVisibilityOverride = true
        updatePanelPresentationLevel(trigger: "testing_in_app_show")
        return true
    }

    @discardableResult
    func presentGlobalHotkeySessionForTesting(
        triggerDirection: CycleDirection = .forward
    ) -> Bool {
        show(direction: triggerDirection)
        return model.session != nil
    }

    func updatePanelSizeForTesting(visibleFrame: CGRect) {
        updatePanelSize(forVisibleFrame: visibleFrame)
    }

    var panelContentSizeForTesting: NSSize {
        panel.contentRect(forFrameRect: panel.frame).size
    }

    func cancelSelectionForTesting() {
        cancelSelection()
    }

    func handleFlagsChangedForTesting(_ event: NSEvent) {
        handleFlagsChanged(event)
    }

    func handleGlobalMouseDownForTesting(location: NSPoint) {
        handleGlobalMouseDown(at: location)
    }

    func handleApplicationDidResignActiveForTesting() {
        handleApplicationDidResignActive()
    }

    func handleActiveSpaceDidChangeForTesting() {
        handleActiveSpaceDidChange()
    }

    func handlePanelOcclusionStateDidChangeForTesting() {
        handlePanelOcclusionStateDidChange()
    }

    func handlePanelDidResignKeyForTesting() {
        handlePanelDidResignKey()
    }

    func scheduleDelayedWindowLayerEntryForTesting() {
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    var suppressHotkeyReplayUntilReleaseForTesting: Bool {
        suppressHotkeyReplayUntilRelease
    }

    deinit {
        suppressHotkeyReplayTask?.cancel()
        suppressHotkeyReplayTask = nil
        panelPresentationRecoveryTask?.cancel()
        panelPresentationRecoveryTask = nil
        terminateSelectedAppTask?.cancel()
        terminateSelectedAppTask = nil
        if let appDidResignActiveObserver {
            NotificationCenter.default.removeObserver(appDidResignActiveObserver)
        }
        if let activeSpaceDidChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceDidChangeObserver)
        }
        if let workspaceDidTerminateApplicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceDidTerminateApplicationObserver)
        }
        if let panelOcclusionObserver {
            NotificationCenter.default.removeObserver(panelOcclusionObserver)
        }
        if let panelDidResignKeyObserver {
            NotificationCenter.default.removeObserver(panelDidResignKeyObserver)
        }
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

    private func logSearchTrace(_ message: String) {
        RuntimeDiagnostics.shared.log(level: .info, category: "SearchTrace", message: message)
    }

    private func panelFirstResponderDebugName() -> String {
        guard let firstResponder = panel.firstResponder else { return "nil" }
        return String(describing: type(of: firstResponder))
    }

    private func searchTraceStateSummary() -> String {
        let now = ProcessInfo.processInfo.systemUptime
        let activeSpaceIgnoreMs = max(0, (ignoreActiveSpaceChangesUntil - now) * 1_000)
        return "panelVisible=\(isPanelPresented ? 1 : 0) panelKey=\(panel.isKeyWindow ? 1 : 0) appActive=\(isAppCurrentlyActive ? 1 : 0) searchActive=\(model.isSearchActive ? 1 : 0) inputFocused=\(model.isSearchInputFocused ? 1 : 0) marked=\(model.hasMarkedSearchText ? 1 : 0) firstResponder=\(panelFirstResponderDebugName()) activeSpaceIgnoreMs=\(formatMilliseconds(activeSpaceIgnoreMs))"
    }

    private func beginIgnoringActiveSpaceChanges(trigger: String) {
        ignoreActiveSpaceChangesUntil = ProcessInfo.processInfo.systemUptime + activeSpaceChangeIgnoreWindow
        logSearchTrace(
            "activeSpaceIgnore trigger=\(trigger) durationMs=\(formatMilliseconds(activeSpaceChangeIgnoreWindow * 1_000)) \(searchTraceStateSummary())"
        )
    }

    private func shouldIgnoreActiveSpaceDidChange() -> Bool {
        ProcessInfo.processInfo.systemUptime < ignoreActiveSpaceChangesUntil
    }

    private func schedulePanelVisibilityRecovery(
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

    private func performPanelVisibilityRecoveryAttempt(
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

    private func activateApplicationForPanelPresentationIfNeeded() {
        guard !isAppCurrentlyActive else { return }
        guard ProcessInfo.processInfo.systemUptime >= suppressApplicationActivationUntil else { return }
        if let activateApplicationIgnoringOtherAppsOverride {
            activateApplicationIgnoringOtherAppsOverride()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(
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
        if suppressHotkeyReplayUntilRelease {
            logInputTrace(
                "hotkeyPressed dir=\(directionText) dropped=awaitingHotkeyRelease nowMs=\(formatMilliseconds(nowMs))"
            )
            return
        }
        if isPanelPresented {
            guard activeHotkeySessionKind == .globalAppSwitcher else { return }
            guard !model.isSearchActive else {
                logInputTrace(
                    "hotkeyPressed dir=\(directionText) panelVisible=1 action=ignoredSearchMode nowMs=\(formatMilliseconds(nowMs))"
                )
                return
            }
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
        guard isPanelPresented else { return }
        guard activeHotkeySessionKind == .globalAppSwitcher else { return }
        guard !model.isSearchActive else { return }
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
        if suppressHotkeyReplayUntilRelease {
            logInputTrace(
                "inAppHotkeyPressed dir=\(directionText) dropped=awaitingHotkeyRelease nowMs=\(formatMilliseconds(nowMs))"
            )
            return
        }
        if isPanelPresented {
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
        guard isPanelPresented else { return }
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

    private func showInAppWindowSwitcher(direction: CycleDirection) {
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

    private func updatePanelPresentationLevel(
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

    private func centerPanelOnActiveScreen(preferredScreen: NSScreen? = nil) {
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

    private func resolveActivePresentationScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }
        return panel.screen
            ?? activePresentationScreen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func resolveSizingScreen(preferredScreen: NSScreen? = nil) -> NSScreen? {
        preferredScreen
            ?? activePresentationScreen
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func hideNonPanelWindowsIfNeeded() {
        guard !isAppCurrentlyActive else { return }
        hideNonPanelWindows()
    }

    private func hideNonPanelWindows() {
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

    private func endPresentationSession() {
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

    private func finishSelection() {
        guard isPanelPresented || hasActivePresentationSession else { return }
        endPresentationSession()
        ignoreHotkeyPressesUntil = ProcessInfo.processInfo.systemUptime + postFinishHotkeyIgnoreWindow
        logInputTrace(
            "finishSelection nowMs=\(formatMilliseconds(monotonicMilliseconds())) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
        )
        model.commitSelection()
    }

    private func cancelSelection() {
        guard isPanelPresented || hasActivePresentationSession else { return }
        endPresentationSession()
        ignoreHotkeyPressesUntil = ProcessInfo.processInfo.systemUptime + postFinishHotkeyIgnoreWindow
        logInputTrace(
            "cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds())) ignoreUntilMs=\(formatMilliseconds(ignoreHotkeyPressesUntil * 1_000))"
        )
        model.cancelSelection()
    }

    private func updatePanelSize(for preferredScreen: NSScreen? = nil) {
        let visibleFrame = resolveSizingScreen(preferredScreen: preferredScreen)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        updatePanelSize(forVisibleFrame: visibleFrame)
    }

    private func updatePanelSize(forVisibleFrame visibleFrame: CGRect) {
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

    private func preferredAppStripWidth(appCount: Int, maxTileSize: CGFloat) -> CGFloat {
        let count = max(appCount, 1)
        let spacing = count > 1 ? maxAppTileSpacing : 0
        let stripWidth =
            CGFloat(count) * maxTileSize
            + CGFloat(max(count - 1, 0)) * spacing
        return max(appLayerMinimumWidth, stripWidth + overlayHorizontalInset)
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

    private func advance(_ keyInput: KeyInput) {
        guard !model.isSearchActive else {
            logInputTrace(
                "advance key=\(keyInput.debugName) dropped=searchActive nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
            return
        }
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

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalKeyDown(event)
            }
        }

        globalFlagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalMouseDown(event)
            }
        }
    }

    private func removeEventMonitors() {
        terminateSelectedAppTask?.cancel()
        terminateSelectedAppTask = nil
        model.clearTerminateSelectedAppAnimation()
        cancelPendingModifierReleaseConfirmation()
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let localFlagsChangedMonitor {
            NSEvent.removeMonitor(localFlagsChangedMonitor)
            self.localFlagsChangedMonitor = nil
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
        if let delayedWindowLayerTimer {
            delayedWindowLayerTimer.invalidate()
            self.delayedWindowLayerTimer = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if model.isSearchActive {
            return handleSearchModeKeyDown(event)
        }

        switch event.keyCode {
        case 49:
            return true
        case 36, 76:
            if !enterSearchModeIfPossible() {
                finishSelection()
            }
            return true
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
            if !enterSearchModeIfPossible() {
                advance(.upArrow)
            }
            return true
        case 53:
            if model.shouldClearSearchOnEscape {
                _ = model.handleSearchEscape()
                updatePanelSize()
            } else {
                cancelSelection()
            }
            return true
        default:
            if isTerminateSelectedAppShortcut(event) {
                terminateSelectedApp()
                return true
            }
            return false
        }
    }

    @discardableResult
    private func enterSearchModeIfPossible() -> Bool {
        logSearchTrace("enterSearchMode action=attempt \(searchTraceStateSummary())")
        guard searchFeatureEnabled else {
            logSearchTrace("enterSearchMode action=ignored reason=featureDisabled \(searchTraceStateSummary())")
            return false
        }
        guard model.enterSearchMode() else {
            logSearchTrace("enterSearchMode action=ignored reason=modelRejected \(searchTraceStateSummary())")
            return false
        }
        cancelPendingModifierReleaseConfirmation()
        updatePanelSize()
        RuntimeLog.info("Session", "enter search mode")
        logSearchTrace("enterSearchMode action=entered \(searchTraceStateSummary())")
        return true
    }

    private func handleSearchModeKeyDown(_ event: NSEvent) -> Bool {
        let isComposingMarkedText = model.hasMarkedSearchText
        switch event.keyCode {
        case 48:
            guard !isComposingMarkedText else { return false }
            if model.toggleSearchScope() {
                updatePanelSize()
            }
            return true
        case 125:
            guard !isComposingMarkedText else { return false }
            _ = model.stepSearchSelectionDown()
            return true
        case 126:
            guard !isComposingMarkedText else { return false }
            _ = model.stepSearchSelectionUp()
            return true
        case 123:
            guard !isComposingMarkedText else { return false }
            guard !model.isSearchInputFocused else { return false }
            _ = model.moveSearchSelection(by: -1)
            return true
        case 124:
            guard !isComposingMarkedText else { return false }
            guard !model.isSearchInputFocused else { return false }
            _ = model.moveSearchSelection(by: +1)
            return true
        case 36, 76:
            guard !isComposingMarkedText else { return false }
            guard model.applySelectedSearchResultToSession() else {
                NSSound.beep()
                return true
            }
            finishSelection()
            return true
        case 53:
            guard !isComposingMarkedText else { return false }
            if !model.isSearchInputFocused {
                if model.focusSearchInput() {
                    updatePanelSize()
                }
                return true
            }
            if model.handleSearchEscape() != .ignored {
                updatePanelSize()
            }
            return true
        case 51:
            if model.searchViewState.query.isEmpty {
                return true
            }
            return false
        default:
            return false
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isPrimaryEvent = isPrimaryModifierFlagsEvent(event)
        guard isPrimaryEvent else { return }
        guard isPanelPresented else { return }
        guard !model.isSearchActive else { return }
        logInputTrace(
            "flagsChanged keyCode=\(event.keyCode) action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        scheduleModifierReleaseConfirmation(trigger: "flags_changed")
    }

    private func handleGlobalMouseDown(_ event: NSEvent) {
        handleGlobalMouseDown(at: event.locationInWindow)
    }

    private func handleGlobalMouseDown(at location: NSPoint) {
        guard isPanelPresented else { return }
        guard model.isSearchActive else { return }
        let isInsidePanel = panelContainsPointOverride?(location) ?? panel.frame.contains(location)
        guard !isInsidePanel else { return }
        logInputTrace(
            "globalMouseDownOutsidePanel action=cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        cancelSelection()
    }

    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard isPanelPresented else { return }
        guard !isAppCurrentlyActive else { return }
        guard event.keyCode == 53 else { return }
        logInputTrace(
            "globalEscWhileAppInactive action=cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        cancelSelection()
    }

    private func handleApplicationDidResignActive() {
        guard isPanelPresented else { return }
        logSearchTrace("systemInterruption trigger=applicationDidResignActive \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "applicationDidResignActive")
    }

    private func handleActiveSpaceDidChange() {
        guard isPanelPresented else { return }
        if shouldIgnoreActiveSpaceDidChange() {
            logSearchTrace("systemInterruption trigger=activeSpaceDidChange action=ignored reason=graceWindow \(searchTraceStateSummary())")
            return
        }
        guard let sessionKind = activeHotkeySessionKind else {
            cancelSelectionForSystemInterruption(trigger: "activeSpaceDidChange")
            return
        }
        let shouldKeepSessionVisible = model.isSearchActive
            || isPrimaryModifierPressedInHardwareState(for: sessionKind)
        guard shouldKeepSessionVisible else {
            logSearchTrace(
                "systemInterruption trigger=activeSpaceDidChange action=cancel reason=modifierReleased \(searchTraceStateSummary())"
            )
            cancelSelectionForSystemInterruption(trigger: "activeSpaceDidChange")
            return
        }
        logSearchTrace(
            "systemInterruption trigger=activeSpaceDidChange action=migrate reason=spaceChanged \(searchTraceStateSummary())"
        )
        suppressApplicationActivationUntil = ProcessInfo.processInfo.systemUptime
            + activeSpaceMigrationActivationSuppressionWindow
        schedulePanelVisibilityRecovery(
            trigger: "activeSpaceDidChange",
            attemptDelaysNanoseconds: interruptionPresentationRecoveryAttemptDelaysNs,
            cancelSessionOnFailure: true,
            activateApplicationIfNeeded: false
        )
    }

    private func handlePanelOcclusionStateDidChange() {
        guard isPanelPresented else { return }
        guard !resolvedPanelOcclusionState.contains(.visible) else { return }
        logSearchTrace("systemInterruption trigger=panelOccluded \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "panelOccluded")
    }

    private func handlePanelDidResignKey() {
        guard isPanelPresented else { return }
        guard !isAppCurrentlyActive else { return }
        logSearchTrace("systemInterruption trigger=panelDidResignKey \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "panelDidResignKey")
    }

    private func handleRecoverableSystemInterruption(trigger: String) {
        guard let sessionKind = activeHotkeySessionKind else {
            cancelSelectionForSystemInterruption(trigger: trigger)
            return
        }
        let shouldKeepSessionVisible = model.isSearchActive
            || isPrimaryModifierPressedInHardwareState(for: sessionKind)
        guard shouldKeepSessionVisible else {
            logSearchTrace(
                "systemInterruption trigger=\(trigger) action=cancel reason=modifierReleased \(searchTraceStateSummary())"
            )
            cancelSelectionForSystemInterruption(trigger: trigger)
            return
        }
        logSearchTrace(
            "systemInterruption trigger=\(trigger) action=recover \(searchTraceStateSummary())"
        )
        schedulePanelVisibilityRecovery(
            trigger: trigger,
            attemptDelaysNanoseconds: interruptionPresentationRecoveryAttemptDelaysNs,
            cancelSessionOnFailure: true
        )
    }

    private func cancelSelectionForSystemInterruption(trigger: String) {
        guard isPanelPresented || hasActivePresentationSession else { return }
        let sessionKind = activeHotkeySessionKind
        logSearchTrace("cancelSelectionForSystemInterruption trigger=\(trigger) action=begin \(searchTraceStateSummary())")
        logInputTrace(
            "\(trigger) action=cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        cancelSelection()
        logSearchTrace("cancelSelectionForSystemInterruption trigger=\(trigger) action=finished \(searchTraceStateSummary())")
        if let sessionKind {
            beginHotkeyReplaySuppressionUntilRelease(for: sessionKind, trigger: trigger)
        }
    }

    private func beginHotkeyReplaySuppressionUntilRelease(
        for sessionKind: HotkeySessionKind,
        trigger: String
    ) {
        suppressHotkeyReplayTask?.cancel()
        suppressHotkeyReplayUntilRelease = true
        logInputTrace(
            "hotkeyReplaySuppression start trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        suppressHotkeyReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while true {
                try? await Task.sleep(nanoseconds: self.modifierReleaseConfirmationSampleIntervalNs)
                guard !Task.isCancelled else { return }
                let modifierPressed = self.isPrimaryModifierPressedInHardwareState(for: sessionKind)
                let mainKeyPressed = self.isSessionMainKeyPressedInHardwareState(for: sessionKind)
                if modifierPressed || mainKeyPressed {
                    continue
                }
                self.suppressHotkeyReplayUntilRelease = false
                self.suppressHotkeyReplayTask = nil
                self.logInputTrace(
                    "hotkeyReplaySuppression end trigger=\(trigger) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                return
            }
        }
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
                guard self.isPanelPresented else {
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=panelHidden nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.pendingModifierReleaseConfirmationTask = nil
                    return
                }
                guard !self.model.isSearchActive else {
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=searchActive nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.logSearchTrace(
                        "releaseConfirm trigger=\(trigger) action=stop reason=searchActive \(self.searchTraceStateSummary())"
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
                self.logSearchTrace(
                    "releaseConfirm trigger=\(trigger) action=confirmed \(self.searchTraceStateSummary())"
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
        isPrimaryModifierPressedInHardwareState(for: activeHotkeySessionKind ?? .globalAppSwitcher)
    }

    private func isPrimaryModifierPressedInHardwareState(for sessionKind: HotkeySessionKind) -> Bool {
        switch sessionKind {
        case .globalAppSwitcher:
            if let globalPrimaryModifierPressedOverride {
                return globalPrimaryModifierPressedOverride
            }
        case .inAppWindowSwitcher:
            if let inAppPrimaryModifierPressedOverride {
                return inAppPrimaryModifierPressedOverride
            }
        }

        switch primaryModifier(for: sessionKind) {
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

    private func isSessionMainKeyPressedInHardwareState(for sessionKind: HotkeySessionKind) -> Bool {
        switch sessionKind {
        case .globalAppSwitcher:
            if let globalMainKeyPressedOverride {
                return globalMainKeyPressedOverride
            }
        case .inAppWindowSwitcher:
            if let inAppMainKeyPressedOverride {
                return inAppMainKeyPressedOverride
            }
        }

        let keyCode: CGKeyCode
        switch sessionKind {
        case .globalAppSwitcher:
            keyCode = CGKeyCode(SwitcherHotkeyPreferencesStore.load().mainKey.keyCode)
        case .inAppWindowSwitcher:
            keyCode = CGKeyCode(InAppWindowHotkeyPreferencesStore.load().mainKey.keyCode)
        }
        return CGEventSource.keyState(.combinedSessionState, key: keyCode)
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
        guard !model.isSearchActive else {
            RuntimeLog.info("AutoEnter", "skip searchActive")
            return
        }

        guard isPanelPresented else {
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
                guard self.isPanelPresented else { return }
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
        guard terminateSelectedAppTask == nil else { return }
        let shouldAnimatePress = model.prepareTerminateSelectedAppAnimation()

        terminateSelectedAppTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.terminateSelectedAppTask = nil
            }

            if shouldAnimatePress {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled else { return }
            }

            switch self.model.terminateSelectedApp() {
            case .notHandled:
                self.model.clearTerminateSelectedAppAnimation()
                RuntimeLog.info("Session", "terminate selected app ignored")
                NSSound.beep()
            case .updatedSession:
                RuntimeLog.info("Session", "terminate selected app \(self.model.debugSelectionSummary())")
                self.updatePanelSize()
                self.scheduleDelayedWindowLayerEntryIfNeeded()
            case .sessionEnded:
                self.model.clearTerminateSelectedAppAnimation()
                RuntimeLog.info("Session", "terminate selected app ended session")
                self.endPresentationSession()
            }
        }
    }

    private func activePrimaryModifier() -> SwitcherPrimaryModifier {
        primaryModifier(for: activeHotkeySessionKind ?? .globalAppSwitcher)
    }

    private func primaryModifier(for sessionKind: HotkeySessionKind) -> SwitcherPrimaryModifier {
        if sessionKind == .inAppWindowSwitcher {
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

    private struct PendingTerminateRequest: Equatable {
        let appID: String
        let pid: pid_t
        let preferredSelectedAppID: String?

        func matches(appID: String, pid: pid_t) -> Bool {
            self.pid == pid || self.appID == appID
        }
    }

    @Published private(set) var session: SwitcherSession? {
        didSet {
            guard let session else {
                sessionAppsByID = [:]
                return
            }
            guard searchViewState.isActive else {
                return
            }
            sessionAppsByID = Dictionary(uniqueKeysWithValues: session.apps.map { ($0.id, $0) })
        }
    }
    @Published private(set) var appGridTileSize: CGFloat = 68
    @Published private(set) var appGridSpacing: CGFloat = 10
    @Published private(set) var previewSectionHeight: CGFloat = 220
    @Published private(set) var overlayStyle: SwitcherOverlayStyle = .appAndWindow
    @Published private(set) var searchViewState: SwitcherSearchViewState = .inactive
    @Published private(set) var terminatingAppID: String?

    private let snapshotProvider = RuntimeSnapshotProvider()
    private let activator = RuntimeActivator()
    private let iconProvider = AppIconProvider()
    private let searchCoordinator = SwitcherSearchCoordinator()
    private let previewImageCache = BoundedImageCache(
        countLimit: 64,
        totalCostLimit: 160 * 1_024 * 1_024
    )

    var onSearchStateChanged: (() -> Void)?
    var onSessionLayoutChanged: (() -> Void)?
    var snapshotProviderOverride: (() -> RuntimeSnapshot)?
    var frontmostApplicationOverride: (() -> NSRunningApplication?)?
    var activationOverride: ((ActivationTarget, [String: RuntimeAppContext]) -> Void)?
    var terminateRequestOverride: ((String) -> (sent: Bool, pid: pid_t))?
    var isProcessRunningOverride: ((pid_t) -> Bool)?
    var previewCaptureOverride: ((
        CGWindowID?,
        pid_t,
        String?,
        Bool
    ) -> (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?)?)?
    var terminateRefreshPollIntervalNs: UInt64 = 60_000_000
    var terminateRefreshTimeoutNs: UInt64 = 1_800_000_000

    private var sessionAppsByID: [String: AppSwitchCandidate] = [:]
    private var runtimeContextsByID: [String: RuntimeAppContext] = [:]
    private var rememberedWindowIDByAppID: [String: String] = [:]
    private var previewCaptureAttemptedKeys: Set<String> = []
    private var autoEnterSuppressedAppID: String?
    private var titleBarStyleInferenceEnabled = false
    private var searchInputHasMarkedText = false
    private var pendingSearchComputationTask: Task<Void, Never>?
    private var pendingTerminateRefreshTask: Task<Void, Never>?
    private var pendingTerminateRequest: PendingTerminateRequest?
    private var searchComputationRevision: UInt64 = 0
    private var searchDebounceNanoseconds: UInt64 = 20_000_000

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

    var isSearchActive: Bool {
        searchViewState.isActive
    }

    var isSearchInputFocused: Bool {
        searchViewState.isInputFocused
    }

    var hasMarkedSearchText: Bool {
        searchInputHasMarkedText
    }

    var searchScope: SwitcherSearchScope {
        searchViewState.scope
    }

    var searchResultCount: Int {
        searchViewState.results.count
    }

    var shouldClearSearchOnEscape: Bool {
        searchViewState.isInputFocused && !searchViewState.query.isEmpty
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
        let previewCacheKey = "\(appID)#\(window.id)"
        if let cached = previewImageCache.image(forKey: previewCacheKey) {
            return (
                image: cached,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }

        if previewCaptureAttemptedKeys.contains(previewCacheKey) {
            return (
                image: nil,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }
        previewCaptureAttemptedKeys.insert(previewCacheKey)

        RuntimeLog.info(
            "Preview",
            "attempt appID=\(appID) pid=\(appContext.runningApp.processIdentifier) windowID=\(window.id) mappedCG=\(windowContext.cgWindowID.map(String.init) ?? "nil") title=\(windowContext.title)"
        )
        guard
            let capture = {
                if let previewCaptureOverride {
                    return previewCaptureOverride(
                        windowContext.cgWindowID,
                        appContext.runningApp.processIdentifier,
                        windowContext.title,
                        titleBarStyleInferenceEnabled
                    )
                }
                return RuntimeWindowPreviewProvider.captureWindowPreview(
                    preferredWindowID: windowContext.cgWindowID,
                    ownerPID: appContext.runningApp.processIdentifier,
                    preferredTitle: windowContext.title,
                    inferTitleBarStyle: titleBarStyleInferenceEnabled
                )
            }()
        else {
            RuntimeLog.info("Preview", "attempt failed appID=\(appID) windowID=\(window.id)")
            return (
                image: nil,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }

        windowContext.cgWindowID = capture.resolvedWindowID
        windowContext.inferredTitleBarStyle = capture.titleBarStyle
        previewImageCache.insert(capture.image, forKey: previewCacheKey)
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

    func windowPreviewSnapshotForTesting() -> [(
        id: String,
        title: String,
        hasImage: Bool,
        titleBarStyle: WindowTitleBarStyleGuess?,
        isSelected: Bool
    )] {
        windowPreviewItems().map {
            (
                id: $0.id,
                title: $0.title,
                hasImage: $0.image != nil,
                titleBarStyle: $0.titleBarStyle,
                isSelected: $0.isSelected
            )
        }
    }

    var selectedApp: AppSwitchCandidate? {
        session?.selectedApp
    }

    var canAutoEnterWindowLayer: Bool {
        guard let session else { return false }
        guard !searchViewState.isActive else { return false }
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

    fileprivate func searchAppItems() -> [SearchAppResultItem] {
        guard session != nil else { return [] }
        guard searchViewState.isActive, searchViewState.scope == .app else { return [] }

        let showsSelection = !searchViewState.isInputFocused
        return searchViewState.results.enumerated().compactMap { index, result in
            guard case .app(let appID) = result.kind else { return nil }
            guard let app = sessionAppsByID[appID] else { return nil }
            return SearchAppResultItem(
                id: result.id,
                app: app,
                isSelected: showsSelection && index == searchViewState.selectedResultIndex
            )
        }
    }

    fileprivate func searchWindowItems() -> [SearchWindowResultItem] {
        guard session != nil else { return [] }
        guard searchViewState.isActive, searchViewState.scope == .window else { return [] }

        let showsSelection = !searchViewState.isInputFocused
        var iconByAppID: [String: NSImage] = [:]
        var missingIconAppIDs: Set<String> = []
        return searchViewState.results.enumerated().compactMap { index, result in
            guard case .window(let appID, _) = result.kind else { return nil }
            let app = sessionAppsByID[appID]
            let appName = app?.displayName ?? result.secondaryText ?? ""
            let resolvedIcon: NSImage?
            if let cached = iconByAppID[appID] {
                resolvedIcon = cached
            } else if missingIconAppIDs.contains(appID) {
                resolvedIcon = nil
            } else {
                let fetched = app.flatMap { icon(for: $0) }
                if let fetched {
                    iconByAppID[appID] = fetched
                } else {
                    missingIconAppIDs.insert(appID)
                }
                resolvedIcon = fetched
            }
            return SearchWindowResultItem(
                id: result.id,
                title: result.primaryText,
                appName: appName,
                icon: resolvedIcon,
                isSelected: showsSelection && index == searchViewState.selectedResultIndex
            )
        }
    }

    @discardableResult
    func enterSearchMode() -> Bool {
        guard SearchInteractionPreferencesStore.loadIsEnabled() else { return false }
        guard overlayStyle == .appAndWindow else { return false }
        guard let session, case .appCycle = session.mode else { return false }
        cancelPendingSearchComputation()
        sessionAppsByID = Dictionary(uniqueKeysWithValues: session.apps.map { ($0.id, $0) })
        searchCoordinator.rebuildIndex(with: session.apps)
        let defaultScope = SearchInteractionPreferencesStore.loadDefaultScope()
        let changed = searchCoordinator.activate(defaultScope: defaultScope)
        publishSearchStateIfNeeded()
        RuntimeDiagnostics.shared.log(
            level: .info,
            category: "SearchModel",
            message: "enterSearchMode changed=\(changed ? 1 : 0) scope=\(defaultScope.rawValue) appCount=\(session.apps.count) inputFocused=\(searchViewState.isInputFocused ? 1 : 0)"
        )
        return changed
    }

    @discardableResult
    func toggleSearchScope() -> Bool {
        cancelPendingSearchComputation()
        let changed = searchCoordinator.toggleScopeWithoutRebuild()
        guard changed else { return false }
        publishSearchStateIfNeeded()
        scheduleSearchComputation(resetSelection: true, debounced: false)
        return true
    }

    @discardableResult
    func focusSearchResults() -> Bool {
        let changed = searchCoordinator.focusResults()
        publishSearchStateIfNeeded()
        return changed
    }

    @discardableResult
    func focusSearchInput() -> Bool {
        let changed = searchCoordinator.focusInput()
        publishSearchStateIfNeeded()
        return changed
    }

    @discardableResult
    func moveSearchSelection(by delta: Int) -> Bool {
        let changed = searchCoordinator.moveSelection(by: delta)
        publishSearchStateIfNeeded()
        return changed
    }

    @discardableResult
    func stepSearchSelectionDown() -> Bool {
        if searchViewState.isInputFocused {
            return focusSearchResults()
        }
        return moveSearchSelection(by: +1)
    }

    @discardableResult
    func stepSearchSelectionUp() -> Bool {
        guard !searchViewState.isInputFocused else { return false }
        if searchViewState.selectedResultIndex == 0 {
            return focusSearchInput()
        }
        return moveSearchSelection(by: -1)
    }

    @discardableResult
    func moveSearchQueryCursor(by delta: Int) -> Bool {
        let changed = searchCoordinator.moveQueryCursor(by: delta)
        publishSearchStateIfNeeded()
        return changed
    }

    func synchronizeSearchInput(query: String, cursorPosition: Int) {
        guard searchViewState.isActive else { return }
        let previousQuery = searchCoordinator.state.query
        let changed = searchCoordinator.replaceQueryWithoutRebuild(
            query,
            cursorPosition: cursorPosition
        )
        guard changed else { return }
        publishSearchStateIfNeeded()
        RuntimeDiagnostics.shared.log(
            level: .info,
            category: "SearchModel",
            message: "synchronizeSearchInput query=\(query.debugDescription) cursor=\(cursorPosition) previousQuery=\(previousQuery.debugDescription) active=\(searchViewState.isActive ? 1 : 0) inputFocused=\(searchViewState.isInputFocused ? 1 : 0)"
        )
        guard previousQuery != searchCoordinator.state.query else { return }
        scheduleSearchComputation(resetSelection: true, debounced: true)
    }

    func updateSearchInputMarkedTextState(_ hasMarkedText: Bool) {
        let nextValue = searchViewState.isActive ? hasMarkedText : false
        guard searchInputHasMarkedText != nextValue else { return }
        searchInputHasMarkedText = nextValue
        RuntimeDiagnostics.shared.log(
            level: .info,
            category: "SearchModel",
            message: "markedText changed=\(nextValue ? 1 : 0) active=\(searchViewState.isActive ? 1 : 0) inputFocused=\(searchViewState.isInputFocused ? 1 : 0) query=\(searchViewState.query.debugDescription)"
        )
    }

    @discardableResult
    func appendSearchQuery(_ value: String) -> Bool {
        let changed = searchCoordinator.appendQueryTextWithoutRebuild(value)
        guard changed else { return false }
        publishSearchStateIfNeeded()
        scheduleSearchComputation(resetSelection: true, debounced: true)
        return true
    }

    @discardableResult
    func deleteSearchQueryBackward() -> Bool {
        let changed = searchCoordinator.deleteBackwardInQueryWithoutRebuild()
        guard changed else { return false }
        publishSearchStateIfNeeded()
        scheduleSearchComputation(resetSelection: true, debounced: true)
        return true
    }

    func handleSearchEscape() -> SwitcherSearchEscapeAction {
        cancelPendingSearchComputation()
        let action = searchCoordinator.handleEscape()
        publishSearchStateIfNeeded()
        return action
    }

    @discardableResult
    func applySelectedSearchResultToSession() -> Bool {
        guard var session else { return false }
        guard let selected = searchViewState.selectedResult else { return false }

        switch selected.kind {
        case .app(let appID):
            guard session.selectApp(withID: appID) else { return false }
        case .window(let appID, let windowID):
            guard session.selectWindow(appID: appID, windowID: windowID) else { return false }
        }

        autoEnterSuppressedAppID = nil
        cancelPendingSearchComputation()
        self.session = session
        _ = searchCoordinator.exit()
        publishSearchStateIfNeeded()
        return true
    }

    func startSession(triggerDirection: CycleDirection) -> Bool {
        cancelPendingTerminateRefresh()
        clearTerminateSelectedAppAnimation()
        overlayStyle = .appAndWindow
        titleBarStyleInferenceEnabled = false
        return loadSnapshot(triggerDirection: triggerDirection, preferredSelectedAppID: nil)
    }

    func startFocusedAppWindowSession(triggerDirection: CycleDirection) -> Bool {
        cancelPendingTerminateRefresh()
        clearTerminateSelectedAppAnimation()
        overlayStyle = .windowOnly
        titleBarStyleInferenceEnabled = true
        guard let frontmostApp = resolveFrontmostApplication() else {
            resetSessionState()
            return false
        }

        let frontmostAppID = frontmostApp.bundleIdentifier
            ?? "pid:\(frontmostApp.processIdentifier)"
        let snapshot = makeSnapshot()
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
        previewImageCache.removeAll()
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
        searchCoordinator.rebuildIndex(with: rebuiltSession.apps)
        publishSearchStateIfNeeded()
        return true
    }

    func terminateSelectedApp() -> TerminateSelectedAppResult {
        guard let currentSession = session else { return .notHandled }

        let selectedApp = currentSession.selectedApp
        guard let terminateRequest = makeTerminateRequest(forAppID: selectedApp.id) else {
            return .notHandled
        }
        let preferredSelectedAppID = preferredAppIDAfterRemovingSelectedApp(from: currentSession)
        let terminatingPID = terminateRequest.pid
        let sent = terminateRequest.sent
        RuntimeLog.info(
            "Session",
            "terminate request app=\(selectedApp.displayName) appID=\(selectedApp.id) sent=\(sent)"
        )
        guard sent else { return .notHandled }

        let request = PendingTerminateRequest(
            appID: selectedApp.id,
            pid: terminatingPID,
            preferredSelectedAppID: preferredSelectedAppID
        )
        pendingTerminateRequest = request
        terminatingAppID = selectedApp.id
        schedulePostTerminateRefresh(for: request)
        return .updatedSession
    }

    private func schedulePostTerminateRefresh(for request: PendingTerminateRequest) {
        cancelPendingTerminateRefresh()
        let maxAttempts = max(1, Int(terminateRefreshTimeoutNs / terminateRefreshPollIntervalNs))
        pendingTerminateRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<maxAttempts {
                try? await Task.sleep(nanoseconds: self.terminateRefreshPollIntervalNs)
                guard !Task.isCancelled else { return }
                guard self.session != nil else { break }
                guard self.pendingTerminateRequest == request else { break }

                guard !self.isProcessRunning(request.pid) else { continue }
                self.refreshSessionAfterTerminatedApplication(
                    appID: request.appID,
                    pid: request.pid,
                    reason: "poll"
                )
                self.pendingTerminateRefreshTask = nil
                return
            }

            guard self.pendingTerminateRequest == request else {
                self.pendingTerminateRefreshTask = nil
                return
            }
            if !self.isProcessRunning(request.pid) {
                self.refreshSessionAfterTerminatedApplication(
                    appID: request.appID,
                    pid: request.pid,
                    reason: "poll_timeout_final_check"
                )
                self.pendingTerminateRefreshTask = nil
                return
            }
            RuntimeLog.info(
                "Session",
                "terminate post-refresh timeout appID=\(request.appID) pid=\(request.pid)"
            )
            self.pendingTerminateRequest = nil
            if self.terminatingAppID == request.appID {
                self.terminatingAppID = nil
            }
            self.pendingTerminateRefreshTask = nil
        }
    }

    private func loadSnapshot(
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?,
        animateAppStripUpdate _: Bool = false,
        preserveSearchState: Bool = false
    ) -> Bool {
        let previousSearchState = preserveSearchState ? searchViewState : .inactive
        cancelPendingSearchComputation()
        let snapshot = makeSnapshot()
        guard !snapshot.apps.isEmpty else {
            resetSessionState()
            return false
        }

        runtimeContextsByID = snapshot.contextsByID
        previewImageCache.removeAll()
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
        if
            let pendingTerminateRequest,
            !rebuiltSession.apps.contains(where: { $0.id == pendingTerminateRequest.appID })
        {
            self.pendingTerminateRequest = nil
            if terminatingAppID == pendingTerminateRequest.appID {
                self.terminatingAppID = nil
            }
        }
        if let terminatingAppID, !rebuiltSession.apps.contains(where: { $0.id == terminatingAppID }) {
            self.terminatingAppID = nil
        }
        searchCoordinator.rebuildIndex(with: rebuiltSession.apps)
        restoreSearchStateAfterSnapshotRefreshIfNeeded(previousSearchState)
        publishSearchStateIfNeeded()
        return true
    }

    private func restoreSearchStateAfterSnapshotRefreshIfNeeded(
        _ previousState: SwitcherSearchViewState
    ) {
        guard previousState.isActive else { return }
        guard searchCoordinator.activate(defaultScope: previousState.scope) else { return }
        if !previousState.query.isEmpty {
            _ = searchCoordinator.replaceQueryWithoutRebuild(
                previousState.query,
                cursorPosition: previousState.queryCursorPosition
            )
        }
        if !previousState.isInputFocused {
            _ = searchCoordinator.focusResults()
        }
        scheduleSearchComputation(resetSelection: true, debounced: false)
    }

    func handleWorkspaceApplicationDidTerminate(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }
        let appID = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        handleApplicationTerminated(appID: appID, pid: app.processIdentifier)
    }

    func handleApplicationTerminated(appID: String, pid: pid_t) {
        refreshSessionAfterTerminatedApplication(appID: appID, pid: pid, reason: "workspace_notification")
    }

    private func refreshSessionAfterTerminatedApplication(appID: String, pid: pid_t, reason: String) {
        guard session != nil else { return }

        let pendingRequest = pendingTerminateRequest
        let matchesPending = pendingRequest?.matches(appID: appID, pid: pid) == true
        let appPresentInSessionByID = session?.apps.contains(where: { $0.id == appID }) == true
        let appPresentInSessionByPID = runtimeContextsByID.values.contains {
            $0.runningApp.processIdentifier == pid
        }
        guard matchesPending || appPresentInSessionByID || appPresentInSessionByPID else {
            return
        }

        if matchesPending {
            pendingTerminateRequest = nil
        }
        let refreshed = loadSnapshot(
            triggerDirection: .forward,
            preferredSelectedAppID: pendingRequest?.preferredSelectedAppID,
            animateAppStripUpdate: true,
            preserveSearchState: searchViewState.isActive
        )
        RuntimeLog.info(
            "Session",
            "terminate post-refresh reason=\(reason) appID=\(appID) pid=\(pid) refreshed=\(refreshed)"
        )
        if matchesPending, let pendingRequest, terminatingAppID == pendingRequest.appID {
            terminatingAppID = nil
        }
        onSessionLayoutChanged?()
    }

    private func preferredAppIDAfterRemovingSelectedApp(from session: SwitcherSession) -> String? {
        guard session.apps.count > 1 else { return nil }
        let remainingAppIDs = session.apps.map(\.id).filter { $0 != session.selectedApp.id }
        guard !remainingAppIDs.isEmpty else { return nil }
        let preferredIndex = min(session.selectedAppIndex, remainingAppIDs.count - 1)
        return remainingAppIDs[preferredIndex]
    }

    func handle(_ keyInput: KeyInput) {
        guard !searchViewState.isActive else { return }
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

    func prepareTerminateSelectedAppAnimation() -> Bool {
        guard let session else { return false }
        terminatingAppID = session.selectedApp.id
        return true
    }

    func clearTerminateSelectedAppAnimation() {
        pendingTerminateRequest = nil
        terminatingAppID = nil
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
        cancelPendingTerminateRefresh()
        clearTerminateSelectedAppAnimation()
        cancelPendingSearchComputation()
        self.session = nil
        _ = searchCoordinator.exit()
        publishSearchStateIfNeeded()

        guard let target else {
            overlayStyle = .appAndWindow
            resetRuntimeState()
            return
        }
        if let activationOverride {
            activationOverride(target, runtimeContextsByID)
        } else {
            activator.activate(target: target, contextsByID: runtimeContextsByID)
        }
        overlayStyle = .appAndWindow
        resetRuntimeState()
    }

    func cancelSelection() {
        resetSessionState()
    }

    private func resetSessionState() {
        cancelPendingTerminateRefresh()
        cancelPendingSearchComputation()
        session = nil
        pendingTerminateRequest = nil
        terminatingAppID = nil
        overlayStyle = .appAndWindow
        searchCoordinator.rebuildIndex(with: [])
        publishSearchStateIfNeeded()
        resetRuntimeState()
    }

    private func resetRuntimeState() {
        runtimeContextsByID = [:]
        previewImageCache.removeAll()
        previewCaptureAttemptedKeys = []
        autoEnterSuppressedAppID = nil
        titleBarStyleInferenceEnabled = false
    }

    private func cancelPendingSearchComputation() {
        pendingSearchComputationTask?.cancel()
        pendingSearchComputationTask = nil
        searchComputationRevision &+= 1
    }

    private func cancelPendingTerminateRefresh() {
        pendingTerminateRefreshTask?.cancel()
        pendingTerminateRefreshTask = nil
    }

    private func makeSnapshot() -> RuntimeSnapshot {
        if let snapshotProviderOverride {
            return snapshotProviderOverride()
        }
        return snapshotProvider.snapshot()
    }

    private func resolveFrontmostApplication() -> NSRunningApplication? {
        if let frontmostApplicationOverride {
            return frontmostApplicationOverride()
        }
        return NSWorkspace.shared.frontmostApplication
    }

    private func makeTerminateRequest(forAppID appID: String) -> (sent: Bool, pid: pid_t)? {
        if let terminateRequestOverride {
            return terminateRequestOverride(appID)
        }
        guard let context = runtimeContextsByID[appID] else { return nil }
        return (
            sent: context.runningApp.terminate(),
            pid: context.runningApp.processIdentifier
        )
    }

    private func isProcessRunning(_ pid: pid_t) -> Bool {
        if let isProcessRunningOverride {
            return isProcessRunningOverride(pid)
        }
        return NSRunningApplication(processIdentifier: pid) != nil
    }

    private func scheduleSearchComputation(resetSelection: Bool, debounced: Bool) {
        guard searchViewState.isActive else { return }
        pendingSearchComputationTask?.cancel()
        searchComputationRevision &+= 1
        let revision = searchComputationRevision
        guard let input = searchCoordinator.makeComputationInput(resetSelection: resetSelection) else {
            return
        }
        let debounceDelay = debounced ? searchDebounceNanoseconds : 0

        pendingSearchComputationTask = Task { [weak self] in
            guard let self else { return }
            if debounceDelay > 0 {
                try? await Task.sleep(nanoseconds: debounceDelay)
            }
            guard !Task.isCancelled else { return }

            let startedAt = DispatchTime.now().uptimeNanoseconds
            let output = await Task.detached(priority: .userInitiated) {
                SwitcherSearchCoordinator.computeOutput(from: input)
            }.value
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt

            await MainActor.run {
                guard revision == self.searchComputationRevision else { return }
                self.pendingSearchComputationTask = nil
                if self.searchCoordinator.applyComputationOutput(output) {
                    self.publishSearchStateIfNeeded()
                    self.onSearchStateChanged?()
                }
                self.updateSearchDebounceWindow(lastComputationNanoseconds: elapsed)
            }
        }
    }

    private func updateSearchDebounceWindow(lastComputationNanoseconds: UInt64) {
        let elapsedMilliseconds = Double(lastComputationNanoseconds) / 1_000_000
        if elapsedMilliseconds > 16 {
            searchDebounceNanoseconds = 45_000_000
        } else if elapsedMilliseconds > 10 {
            searchDebounceNanoseconds = 35_000_000
        } else if elapsedMilliseconds > 6 {
            searchDebounceNanoseconds = 25_000_000
        } else {
            searchDebounceNanoseconds = 14_000_000
        }
    }

    private func publishSearchStateIfNeeded() {
        let newState = searchCoordinator.state
        if !newState.isActive {
            searchInputHasMarkedText = false
        }
        guard searchViewState != newState else { return }
        searchViewState = newState
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
    @AppStorage(AppPreferenceKeys.searchEnabled)
    private var searchEnabled = SearchInteractionPreferencesStore.defaultIsEnabled
    @AppStorage(AppPreferenceKeys.searchDefaultScope)
    private var searchDefaultScopeRaw = SearchInteractionPreferencesStore.defaultScope.rawValue
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue

    private var themeMode: ThemeMode {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
    }

    private var resolvedColorScheme: ColorScheme {
        themeMode.resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    private var searchDefaultScope: SwitcherSearchScope {
        SwitcherSearchScope(rawValue: searchDefaultScopeRaw) ?? SearchInteractionPreferencesStore.defaultScope
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
                    searchState: model.searchViewState,
                    searchAppItems: model.searchAppItems(),
                    searchWindowItems: model.searchWindowItems(),
                    onSearchInputChanged: { query, cursorPosition in
                        model.synchronizeSearchInput(query: query, cursorPosition: cursorPosition)
                    },
                    onSearchMarkedTextChanged: { hasMarkedText in
                        model.updateSearchInputMarkedTextState(hasMarkedText)
                    },
                    searchFeatureEnabled: searchEnabled,
                    searchDefaultScope: searchDefaultScope,
                    selectedApp: model.selectedApp,
                    terminatingAppID: model.terminatingAppID,
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
        .accessibilityIdentifier("flowtab.switcher.panel")
        .id(appLanguageRaw)
    }
}

private struct CommandTabOverlay: View {
    let session: SwitcherSession
    let overlayStyle: SwitcherOverlayStyle
    let isPreviewLayer: Bool
    let previewSectionHeight: CGFloat
    let windowPreviewItems: [WindowPreviewItem]
    let searchState: SwitcherSearchViewState
    let searchAppItems: [SearchAppResultItem]
    let searchWindowItems: [SearchWindowResultItem]
    let onSearchInputChanged: (String, Int) -> Void
    let onSearchMarkedTextChanged: (Bool) -> Void
    let searchFeatureEnabled: Bool
    let searchDefaultScope: SwitcherSearchScope
    let selectedApp: AppSwitchCandidate?
    let terminatingAppID: String?
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

    private var isSearchMode: Bool {
        searchState.isActive
    }

    private var showsSearchHeaderInStandardOverlay: Bool {
        searchFeatureEnabled && !isPreviewLayer
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

    private var selectedSearchResultID: String? {
        guard !searchState.results.isEmpty else { return nil }
        let index = min(max(searchState.selectedResultIndex, 0), searchState.results.count - 1)
        return searchState.results[index].id
    }

    private var searchHeaderHighlightItem: SearchHeaderHighlightItem? {
        guard isSearchMode else { return nil }
        switch searchState.scope {
        case .app:
            guard !searchAppItems.isEmpty else { return nil }
            let index = min(max(searchState.selectedResultIndex, 0), searchAppItems.count - 1)
            let item = searchAppItems[index]
            return SearchHeaderHighlightItem(
                title: item.app.displayName,
                icon: iconForApp(item.app)
            )
        case .window:
            guard !searchWindowItems.isEmpty else { return nil }
            let index = min(max(searchState.selectedResultIndex, 0), searchWindowItems.count - 1)
            let item = searchWindowItems[index]
            return SearchHeaderHighlightItem(
                title: item.appName,
                icon: item.icon
            )
        }
    }

    private func scrollToSelectedPreview(using proxy: ScrollViewProxy) {
        guard let selectedWindowPreviewID else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(selectedWindowPreviewID, anchor: .center)
        }
    }

    private func scrollToSelectedSearchResult(using proxy: ScrollViewProxy) {
        guard !searchState.isInputFocused else { return }
        guard let selectedSearchResultID else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(selectedSearchResultID, anchor: .center)
        }
    }

    @ViewBuilder
    private var standardOverlayBody: some View {
        let appIDs = session.apps.map(\.id)
        VStack(alignment: .leading, spacing: 12) {
            if showsSearchHeaderInStandardOverlay {
                SearchInputHeader(
                    query: "",
                    scope: searchDefaultScope,
                    isInputFocused: false,
                    hintText: AppStrings.text(.panelHintEnterToSearch)
                )
            }

            HStack(alignment: .center, spacing: appTileSpacing) {
                ForEach(Array(session.apps.enumerated()), id: \.element.id) { index, app in
                    AppTileView(
                        app: app,
                        isSelected: index == session.selectedAppIndex,
                        isTerminating: app.id == terminatingAppID,
                        size: appTileSize,
                        icon: iconForApp(app)
                    )
                    .transition(.appQuitRemoval)
                }
            }
            .animation(
                session.apps.count <= 16 ? .easeOut(duration: 0.14) : nil,
                value: appIDs
            )
            .frame(maxWidth: .infinity, alignment: .center)
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
    private var searchOverlayBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchPresentationHeader(
                query: searchState.query,
                cursorPosition: searchState.queryCursorPosition,
                scope: searchState.scope,
                isInputFocused: searchState.isInputFocused,
                highlightedItem: searchHeaderHighlightItem,
                isSearchActive: searchState.isActive,
                onSearchInputChanged: onSearchInputChanged,
                onSearchMarkedTextChanged: onSearchMarkedTextChanged
            )
            .accessibilityIdentifier("flowtab.switcher.search")

            if searchState.scope == .app {
                if searchAppItems.isEmpty {
                    SearchEmptyState(scope: .app)
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(searchAppItems) { item in
                                    SearchAppRow(
                                        item: item,
                                        icon: iconForApp(item.app)
                                    )
                                    .id(item.id)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .onAppear {
                            scrollToSelectedSearchResult(using: scrollProxy)
                        }
                        .onChange(of: selectedSearchResultID) { _ in
                            scrollToSelectedSearchResult(using: scrollProxy)
                        }
                        .onChange(of: searchState.isInputFocused) { _ in
                            scrollToSelectedSearchResult(using: scrollProxy)
                        }
                    }
                }
            } else {
                if searchWindowItems.isEmpty {
                    SearchEmptyState(scope: .window)
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(searchWindowItems) { item in
                                    SearchWindowRow(item: item)
                                        .id(item.id)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .onAppear {
                            scrollToSelectedSearchResult(using: scrollProxy)
                        }
                        .onChange(of: selectedSearchResultID) { _ in
                            scrollToSelectedSearchResult(using: scrollProxy)
                        }
                        .onChange(of: searchState.isInputFocused) { _ in
                            scrollToSelectedSearchResult(using: scrollProxy)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            let selectedAppIcon = selectedApp.flatMap(iconForApp)
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
                            appIcon: selectedAppIcon,
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
        } else if isSearchMode {
            searchOverlayBody
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

private struct SearchAppResultItem: Identifiable {
    let id: String
    let app: AppSwitchCandidate
    let isSelected: Bool
}

private struct SearchWindowResultItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let icon: NSImage?
    let isSelected: Bool
}

private struct SearchHeaderHighlightItem {
    let title: String
    let icon: NSImage?
}

private struct SearchSystemTextInputBridge: NSViewRepresentable {
    let query: String
    let cursorPosition: Int
    let isSearchActive: Bool
    let showsInsertionPoint: Bool
    let onInputChanged: (String, Int) -> Void
    let onMarkedTextChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onInputChanged: onInputChanged,
            onMarkedTextChanged: onMarkedTextChanged
        )
    }

    func makeNSView(context: Context) -> SearchSystemTextInputContainerView {
        let view = SearchSystemTextInputContainerView()
        view.textView.delegate = context.coordinator
        context.coordinator.attach(textView: view.textView)
        return view
    }

    func updateNSView(_ nsView: SearchSystemTextInputContainerView, context: Context) {
        context.coordinator.updateCallbacks(
            onInputChanged: onInputChanged,
            onMarkedTextChanged: onMarkedTextChanged
        )
        context.coordinator.synchronize(
            textView: nsView.textView,
            query: query,
            cursorPosition: cursorPosition,
            isSearchActive: isSearchActive,
            showsInsertionPoint: showsInsertionPoint
        )
    }

    static func dismantleNSView(
        _ nsView: SearchSystemTextInputContainerView,
        coordinator: Coordinator
    ) {
        coordinator.detach(textView: nsView.textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private struct InputSnapshot: Equatable {
            let query: String
            let cursorPosition: Int
        }

        private var onInputChanged: (String, Int) -> Void
        private var onMarkedTextChanged: (Bool) -> Void
        private var isApplyingViewState = false
        private weak var trackedTextView: NSTextView?
        private var lastPublishedInputSnapshot: InputSnapshot?
        private var lastPublishedMarkedTextState: Bool?

        init(
            onInputChanged: @escaping (String, Int) -> Void,
            onMarkedTextChanged: @escaping (Bool) -> Void
        ) {
            self.onInputChanged = onInputChanged
            self.onMarkedTextChanged = onMarkedTextChanged
        }

        func attach(textView: NSTextView) {
            trackedTextView = textView
        }

        func detach(textView: NSTextView) {
            guard trackedTextView === textView else { return }
            trackedTextView = nil
            onMarkedTextChanged(false)
        }

        func updateCallbacks(
            onInputChanged: @escaping (String, Int) -> Void,
            onMarkedTextChanged: @escaping (Bool) -> Void
        ) {
            self.onInputChanged = onInputChanged
            self.onMarkedTextChanged = onMarkedTextChanged
        }

        func synchronize(
            textView: NSTextView,
            query: String,
            cursorPosition: Int,
            isSearchActive: Bool,
            showsInsertionPoint: Bool
        ) {
            let resolvedCursorPosition = min(max(cursorPosition, 0), query.count)
            let selectedRange = NSRange(location: resolvedCursorPosition, length: 0)
            let shouldPreserveSelection = textView.string == query && textView.selectedRange().length > 0
            isApplyingViewState = true
            if textView.string != query {
                textView.string = query
            }
            if !shouldPreserveSelection, textView.selectedRange() != selectedRange {
                textView.setSelectedRange(selectedRange)
            }
            let insertionPointColor: NSColor = showsInsertionPoint ? .controlAccentColor : .clear
            if textView.insertionPointColor != insertionPointColor {
                textView.insertionPointColor = insertionPointColor
            }
            isApplyingViewState = false

            ensureCursorIsVisible(for: textView)
            synchronizeFirstResponder(for: textView, isSearchActive: isSearchActive)
            publishMarkedTextState(for: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard trackedTextView === textView else { return }
            guard !isApplyingViewState else {
                publishMarkedTextState(for: textView)
                return
            }
            ensureCursorIsVisible(for: textView)
            publishInputState(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard trackedTextView === textView else { return }
            guard !isApplyingViewState else {
                publishMarkedTextState(for: textView)
                return
            }
            ensureCursorIsVisible(for: textView)
            publishInputState(for: textView)
        }

        private func publishInputState(for textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else {
                publishMarkedTextState(for: textView)
                return
            }
            let snapshot = InputSnapshot(
                query: textView.string,
                cursorPosition: selectedRange.location
            )
            if lastPublishedInputSnapshot != snapshot {
                lastPublishedInputSnapshot = snapshot
                Self.logSearchInput(
                    "publishInputState query=\(snapshot.query.debugDescription) cursor=\(snapshot.cursorPosition) hasMarked=\(textView.hasMarkedText() ? 1 : 0)"
                )
            }
            onInputChanged(textView.string, selectedRange.location)
            publishMarkedTextState(for: textView)
        }

        private func publishMarkedTextState(for textView: NSTextView) {
            let hasMarkedText = textView.hasMarkedText()
            if lastPublishedMarkedTextState != hasMarkedText {
                lastPublishedMarkedTextState = hasMarkedText
                Self.logSearchInput(
                    "publishMarkedTextState hasMarked=\(hasMarkedText ? 1 : 0) query=\(textView.string.debugDescription)"
                )
            }
            onMarkedTextChanged(hasMarkedText)
        }

        private func ensureCursorIsVisible(for textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else { return }
            textView.scrollRangeToVisible(selectedRange)
        }

        private func synchronizeFirstResponder(for textView: NSTextView, isSearchActive: Bool) {
            if isSearchActive {
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    guard let window = textView.window else {
                        Self.logSearchInput("syncFirstResponder active=1 skipped=noWindow")
                        return
                    }
                    if window.firstResponder === textView {
                        Self.logSearchInput(
                            "syncFirstResponder active=1 skipped=alreadyFirstResponder windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0)"
                        )
                        return
                    }
                    let before = Self.responderName(window.firstResponder)
                    let didBecomeFirstResponder = window.makeFirstResponder(textView)
                    let after = Self.responderName(window.firstResponder)
                    Self.logSearchInput(
                        "syncFirstResponder active=1 result=\(didBecomeFirstResponder ? 1 : 0) windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0) before=\(before) after=\(after)"
                    )
                }
            } else {
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    guard let window = textView.window else {
                        Self.logSearchInput("syncFirstResponder active=0 skipped=noWindow")
                        return
                    }
                    guard window.firstResponder === textView else { return }
                    let before = Self.responderName(window.firstResponder)
                    let clearedFirstResponder = window.makeFirstResponder(nil)
                    let after = Self.responderName(window.firstResponder)
                    Self.logSearchInput(
                        "syncFirstResponder active=0 result=\(clearedFirstResponder ? 1 : 0) windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0) before=\(before) after=\(after)"
                    )
                }
            }
        }

        private static func logSearchInput(_ message: String) {
            RuntimeDiagnostics.shared.log(level: .info, category: "SearchInput", message: message)
        }

        private static func responderName(_ responder: NSResponder?) -> String {
            guard let responder else { return "nil" }
            return String(describing: type(of: responder))
        }
    }
}

private final class SearchSystemTextInputContainerView: NSView {
    let textView: SearchSystemTextView
    let scrollView: NSScrollView

    override init(frame frameRect: NSRect) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = true
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byClipping
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        textView = SearchSystemTextView(frame: .zero, textContainer: textContainer)
        scrollView = NSScrollView(frame: .zero)
        super.init(frame: frameRect)
        setAccessibilityIdentifier("flowtab.switcher.search.input")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none

        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.autoresizingMask = [.height]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = true

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.font = .systemFont(ofSize: 20, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.textContainerInset = .zero
        scrollView.documentView = textView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class SearchSystemTextView: NSTextView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

#if DEBUG
@MainActor
final class SearchSystemTextInputBridgeTestHarness {
    struct InputChange: Equatable {
        let query: String
        let cursorPosition: Int
    }

    private let containerView = SearchSystemTextInputContainerView()
    private let coordinator = SearchSystemTextInputBridge.Coordinator(
        onInputChanged: { _, _ in },
        onMarkedTextChanged: { _ in }
    )

    private(set) var inputChanges: [InputChange] = []
    private(set) var markedTextChanges: [Bool] = []

    init() {
        containerView.textView.delegate = coordinator
        coordinator.attach(textView: containerView.textView)
        coordinator.updateCallbacks(
            onInputChanged: { [weak self] query, cursorPosition in
                self?.inputChanges.append(
                    InputChange(query: query, cursorPosition: cursorPosition)
                )
            },
            onMarkedTextChanged: { [weak self] hasMarkedText in
                self?.markedTextChanges.append(hasMarkedText)
            }
        )
    }

    var textView: NSTextView {
        containerView.textView
    }

    var containerAccessibilityIdentifier: String? {
        containerView.accessibilityIdentifier()
    }

    var enclosingScrollView: NSScrollView? {
        containerView.textView.enclosingScrollView
    }

    func synchronize(
        query: String,
        cursorPosition: Int,
        isSearchActive: Bool = false,
        showsInsertionPoint: Bool = true
    ) {
        coordinator.synchronize(
            textView: containerView.textView,
            query: query,
            cursorPosition: cursorPosition,
            isSearchActive: isSearchActive,
            showsInsertionPoint: showsInsertionPoint
        )
    }

    func notifyTextDidChange(for textView: NSTextView? = nil) {
        let target = textView ?? containerView.textView
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: target))
    }

    func notifySelectionDidChange(for textView: NSTextView? = nil) {
        let target = textView ?? containerView.textView
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: target)
        )
    }

    func resetRecordedChanges() {
        inputChanges.removeAll()
        markedTextChanges.removeAll()
    }

    func detachTrackedTextView() {
        coordinator.detach(textView: containerView.textView)
    }
}
#endif

private struct SearchInputHeader: View {
    let query: String
    let scope: SwitcherSearchScope
    let isInputFocused: Bool
    let hintText: String
    @Environment(\.colorScheme) private var colorScheme

    init(
        query: String,
        scope: SwitcherSearchScope,
        isInputFocused: Bool,
        hintText: String
    ) {
        self.query = query
        self.scope = scope
        self.isInputFocused = isInputFocused
        self.hintText = hintText
    }

    private var queryText: String {
        if query.isEmpty && !isInputFocused {
            return AppStrings.text(.panelInputPlaceholder)
        }
        return query
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(queryText)
                    .foregroundStyle(query.isEmpty && !isInputFocused ? .secondary : .primary)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 8)

                Text(scope.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.08))
                    )
            }

            Text(hintText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(isInputFocused ? 0.95 : 0.78))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isInputFocused
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.78 : 0.58)
                        : Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10),
                    lineWidth: isInputFocused ? 1.6 : 1
                )
        )
    }
}

private struct SearchPresentationHeader: View {
    let query: String
    let cursorPosition: Int
    let scope: SwitcherSearchScope
    let isInputFocused: Bool
    let highlightedItem: SearchHeaderHighlightItem?
    let isSearchActive: Bool
    let onSearchInputChanged: (String, Int) -> Void
    let onSearchMarkedTextChanged: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let inputLineHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if query.isEmpty && !isInputFocused {
                    Text(AppStrings.text(.panelSearchLabel))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                SearchSystemTextInputBridge(
                    query: query,
                    cursorPosition: cursorPosition,
                    isSearchActive: isSearchActive,
                    showsInsertionPoint: isInputFocused,
                    onInputChanged: onSearchInputChanged,
                    onMarkedTextChanged: onSearchMarkedTextChanged
                )
                .opacity(query.isEmpty && !isInputFocused ? 0.01 : 1)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, minHeight: inputLineHeight, maxHeight: inputLineHeight, alignment: .leading)
            .clipped()

            if let highlightedItem {
                HStack(spacing: 8) {
                    Text("—")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(highlightedItem.title)
                        .lineLimit(1)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.30 : 0.20))
                )
            }

            Group {
                if let icon = highlightedItem?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.13))
                        .overlay(
                            Image(systemName: scope == .app ? "app.badge.fill" : "macwindow")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 3, y: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isInputFocused
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.76 : 0.54)
                        : Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10),
                    lineWidth: isInputFocused ? 1.6 : 1
                )
        )
    }
}

private struct SearchEmptyState: View {
    let scope: SwitcherSearchScope

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: scope == .app ? "app.badge" : "macwindow.on.rectangle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            Text(AppStrings.text(.panelNoResult))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct SearchAppRow: View {
    let item: SearchAppResultItem
    let icon: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.14))
                        .overlay(
                            Text(item.app.displayName.prefix(1).uppercased())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.app.displayName)
                .lineLimit(1)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(
                    item.isSelected
                        ? Color.primary
                        : Color.primary.opacity(0.92)
                )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    item.isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.16)
                        : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    item.isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.64 : 0.45)
                        : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    lineWidth: item.isSelected ? 1.4 : 1
                )
        )
        .accessibilityIdentifier("flowtab.switcher.search.app.\(item.app.id.flowTabAccessibilitySlug)")
    }
}

private struct SearchWindowRow: View {
    let item: SearchWindowResultItem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.14))
                        .overlay(
                            Image(systemName: "app")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(
                        item.isSelected
                            ? Color.primary
                            : Color.primary.opacity(0.92)
                    )
                Text(item.appName)
                    .lineLimit(1)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    item.isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.16)
                        : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    item.isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.64 : 0.45)
                        : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    lineWidth: item.isSelected ? 1.4 : 1
                )
        )
        .accessibilityIdentifier("flowtab.switcher.search.window.\(item.id.flowTabAccessibilitySlug)")
    }
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
    let appIcon: NSImage?
    let titleBarStyle: WindowTitleBarStyleGuess?
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let titleAreaHeight: CGFloat = 30
    private var previewAreaHeight: CGFloat {
        max(1, height - titleAreaHeight)
    }
    private var fallbackAppIconSize: CGFloat {
        max(42, min(96, min(width, previewAreaHeight) * 0.24))
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
                    if colorScheme == .dark {
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color.white
                    }
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fallbackAppIconSize, height: fallbackAppIconSize)
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 52, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
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
    }
}

private extension AnyTransition {
    static var appQuitRemoval: AnyTransition {
        let removal = AnyTransition.opacity
            .combined(with: .scale(scale: 0.72, anchor: .center))
        let insertion = AnyTransition.opacity
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

private struct AppTileView: View {
    let app: AppSwitchCandidate
    let isSelected: Bool
    let isTerminating: Bool
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
        .scaleEffect(isTerminating ? 0.96 : 1.0)
        .opacity(isTerminating ? 0.9 : 1.0)
        .saturation(isTerminating ? 0.88 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isTerminating)
    }
}
