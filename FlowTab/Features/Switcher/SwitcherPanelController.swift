import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore


@MainActor
final class SwitcherPanelController {
    enum HotkeySessionKind {
        case globalAppSwitcher
        case inAppWindowSwitcher
    }

    let model: LiveSwitcherModel
    let panel: SwitcherOverlayPanel

    var keyDownMonitor: Any?
    var localFlagsChangedMonitor: Any?
    var globalKeyDownMonitor: Any?
    var globalFlagsChangedMonitor: Any?
    var globalMouseDownMonitor: Any?
    var appDidResignActiveObserver: NSObjectProtocol?
    var activeSpaceDidChangeObserver: NSObjectProtocol?
    var workspaceDidTerminateApplicationObserver: NSObjectProtocol?
    var panelOcclusionObserver: NSObjectProtocol?
    var panelDidResignKeyObserver: NSObjectProtocol?
    var suppressHotkeyReplayUntilRelease = false
    var suppressHotkeyReplayTask: Task<Void, Never>?
    var pendingModifierReleaseConfirmationTask: Task<Void, Never>?
    var panelPresentationRecoveryTask: Task<Void, Never>?
    var delayedWindowLayerTimer: Timer?
    var lastCommittedTabAdvanceTimestamp: TimeInterval?
    var ignoreHotkeyPressesUntil: TimeInterval = 0
    var ignoreActiveSpaceChangesUntil: TimeInterval = 0
    var suppressApplicationActivationUntil: TimeInterval = 0
    var windowLayerPresentationDelay: TimeInterval {
        windowLayerPresentationDelayOverride ?? WindowLayerPreferencesStore.loadAutoEnterDelay()
    }
    let modifierReleaseConfirmationSampleIntervalNs: UInt64 = 25_000_000
    let modifierReleaseConfirmationSampleCount: Int = 2
    let postFinishHotkeyIgnoreWindow: TimeInterval = 0.02
    let activeSpaceChangeIgnoreWindow: TimeInterval = 0.35
    let activeSpaceMigrationActivationSuppressionWindow: TimeInterval = 0.5
    let initialPresentationRecoveryAttemptDelaysNs: [UInt64] = [50_000_000, 150_000_000]
    let interruptionPresentationRecoveryAttemptDelaysNs: [UInt64] = [
        0,
        50_000_000,
        150_000_000,
        300_000_000
    ]
    let panelPresentationRecoveryReorderDelayNs: UInt64 = 10_000_000
    let autoEnterWindowLayerEnabled = true
    let tabAdvanceMinimumInterval: TimeInterval = 0.016
    let panelScreenMargin: CGFloat = 80
    let windowOnlyOverlayScreenMargin: CGFloat = 20
    let appLayerMinimumWidth: CGFloat = 440
    let appLayerStaticHeight: CGFloat = 56
    let appLayerSearchHeaderExtraHeight: CGFloat = 68
    let standardPreviewSectionMinimumHeight: CGFloat = 130
    let standardPreviewSectionMaximumHeight: CGFloat = 220
    let standardPreviewCardMinimumWidth: CGFloat = 120
    let standardPreviewCardMaximumWidth: CGFloat = 360
    let standardPreviewCardSpacing: CGFloat = 12
    let standardPreviewHeightRatio: CGFloat = 0.62
    let standardPreviewWidthAdjustment: CGFloat = 4
    let minimumPanelHeight: CGFloat = 140
    let previewLayerAppTileSize: CGFloat = 68
    let appLayerMaxAdaptiveTileSize: CGFloat = 90
    let maxAppTileSpacing: CGFloat = 10
    let minAppTileSize: CGFloat = 1
    var activeHotkeySessionKind: HotkeySessionKind?
    var activePresentationScreen: NSScreen?
    var terminateSelectedAppTask: Task<Void, Never>?
    var suppressModifierReleaseConfirmationForTesting = false

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
    var lastSearchLayoutSizingLogSummary: String?

    var searchFeatureEnabled: Bool {
        SearchInteractionPreferencesStore.loadIsEnabled()
    }

    var isPanelPresented: Bool {
        panelVisibilityOverride ?? panel.isVisible
    }

    var isPanelVisibleToUser: Bool {
        guard isPanelPresented else { return false }
        if panelVisibilityOverride != nil, panelOcclusionStateOverride == nil {
            return true
        }
        return resolvedPanelOcclusionState.contains(.visible)
    }

    var resolvedPanelOcclusionState: NSWindow.OcclusionState {
        panelOcclusionStateOverride ?? panel.occlusionState
    }

    var isAppCurrentlyActive: Bool {
        appIsActiveOverride ?? NSApp.isActive
    }

    var hasActivePresentationSession: Bool {
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
        let contentView = SwitcherPanelContentView(hostingView: hostingView)
        panel.contentView = contentView
        model.onSearchStateChanged = { [weak self] in
            guard let self else { return }
            guard self.isPanelPresented else { return }
            self.updatePanelSize()
        }
        model.onSessionLayoutChanged = { [weak self] in
            guard let self else { return }
            self.syncPanelAccessibilityAnchors()
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
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handleActiveSpaceDidChange()
                }
                return
            }
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

    @discardableResult
    func presentInAppWindowHotkeySessionForTesting(
        triggerDirection: CycleDirection = .forward
    ) -> Bool {
        showInAppWindowSwitcher(direction: triggerDirection)
        return model.session != nil
    }

    func setModifierReleaseConfirmationSuppressedForTesting(_ suppressed: Bool) {
        suppressModifierReleaseConfirmationForTesting = suppressed
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

    func syncPanelAccessibilityAnchors() {
        panel.updateSwitcherAccessibilityApps(model.session?.apps ?? [])
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
}

enum SwitcherAccessibilityIdentifiers {
    static let testingSummary = "flowtab.testing.switcher.summary"
    static let previousWindowPage = "flowtab.switcher.window-page.previous"
    static let nextWindowPage = "flowtab.switcher.window-page.next"

    static func app(id: String) -> String {
        "flowtab.switcher.app.\(id.flowTabAccessibilitySlug)"
    }

    static func window(id: String) -> String {
        "flowtab.switcher.window.\(id.flowTabAccessibilitySlug)"
    }
}

private final class SwitcherPanelContentView: NSView {
    private let hostingView: NSView

    init(hostingView: NSView) {
        self.hostingView = hostingView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }
}
