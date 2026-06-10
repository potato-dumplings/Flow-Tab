import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

struct PanelVisibilityRecoveryPolicy: Equatable {
    var initialPresentationGraceWindow: TimeInterval
    var interruptionAttemptDelaysNanoseconds: [UInt64]
    var hardReorderDelayNanoseconds: UInt64

    static let `default` = PanelVisibilityRecoveryPolicy(
        initialPresentationGraceWindow: 0.35,
        interruptionAttemptDelaysNanoseconds: [
            0,
            50_000_000,
            150_000_000,
            300_000_000
        ],
        hardReorderDelayNanoseconds: 10_000_000
    )
}

struct ModifierReleaseConfirmationPolicy: Equatable {
    var sampleIntervalNanoseconds: UInt64
    var requiredReleasedSampleCount: Int
    var postFinishHotkeyIgnoreWindow: TimeInterval

    static let `default` = ModifierReleaseConfirmationPolicy(
        sampleIntervalNanoseconds: 25_000_000,
        requiredReleasedSampleCount: 2,
        postFinishHotkeyIgnoreWindow: 0.02
    )
}

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

@MainActor
final class SwitcherPanelController {
    enum HotkeySessionKind {
        case globalAppSwitcher
        case inAppWindowSwitcher
    }

    enum PanelVisibilityRecoveryMode: Equatable {
        case softReorder
        case hardReorder

        var debugName: String {
            switch self {
            case .softReorder:
                "softReorder"
            case .hardReorder:
                "hardReorder"
            }
        }
    }

    enum PanelVisibilityRecoveryState: Equatable {
        case idle
        case presenting(trigger: String, generation: Int)
        case visibleConfirmed(trigger: String, generation: Int, reason: String)
        case suspectedHidden(trigger: String, generation: Int)
        case recovering(
            trigger: String,
            generation: Int,
            attempt: Int,
            totalAttempts: Int,
            mode: PanelVisibilityRecoveryMode
        )
        case failed(trigger: String, generation: Int, reason: String)
    }

    enum ModifierReleaseCancellationReason: String, Equatable {
        case suppressedForTesting
        case explicitCancel
        case panelHidden
        case searchActive
        case sessionChanged
    }

    enum ModifierReleaseState: Equatable {
        case idle
        case pressed(generation: Int)
        case releaseObserved(trigger: String, generation: Int)
        case confirming(trigger: String, generation: Int, releasedSamples: Int)
        case confirmed(trigger: String, generation: Int)
        case replaySuppression(trigger: String, generation: Int, releasedSamples: Int)
        case replaySuppressionEnded(trigger: String, generation: Int)
        case canceled(reason: ModifierReleaseCancellationReason, generation: Int)
    }

    let model: LiveSwitcherModel
    let panel: SwitcherOverlayPanel

    var keyDownMonitor: Any?
    var localFlagsChangedMonitor: Any?
    var localMouseMovedMonitor: Any?
    var globalKeyDownMonitor: Any?
    var globalFlagsChangedMonitor: Any?
    var globalMouseDownMonitor: Any?
    var globalMouseMovedMonitor: Any?
    var appDidResignActiveObserver: NSObjectProtocol?
    var activeSpaceDidChangeObserver: NSObjectProtocol?
    var workspaceDidTerminateApplicationObserver: NSObjectProtocol?
    var panelOcclusionObserver: NSObjectProtocol?
    var panelDidResignKeyObserver: NSObjectProtocol?
    var suppressHotkeyReplayUntilRelease = false
    var suppressHotkeyReplayTask: Task<Void, Never>?
    var pendingModifierReleaseConfirmationTask: Task<Void, Never>?
    var modifierReleaseConfirmationGeneration = 0
    var modifierReleaseState: ModifierReleaseState = .idle
    var presentationSessionGeneration = 0
    var panelPresentationRecoveryTask: Task<Void, Never>?
    var panelPresentationRecoveryGeneration = 0
    var panelVisibilityRecoveryState: PanelVisibilityRecoveryState = .idle
    var lastPanelVisibilityRecoveryDiagnostic: PanelVisibilityRecoveryDiagnostic?
    var delayedWindowLayerTimer: Timer?
    var delayedWindowLayerDeadlineMs: Double?
    var delayedWindowLayerAppID: String?
    var lastCommittedTabAdvanceTimestamp: TimeInterval?
    var ignoreHotkeyPressesUntil: TimeInterval = 0
    var ignoreActiveSpaceChangesUntil: TimeInterval = 0
    var initialPresentationVisibilityGeneration = 0
    var initialPresentationVisibilityDeadline: TimeInterval = 0
    var initialPresentationVisibilityTrigger: String?
    var suppressApplicationActivationUntil: TimeInterval = 0
    var windowLayerPresentationDelay: TimeInterval {
        windowLayerPresentationDelayOverride ?? WindowLayerPreferencesStore.loadAutoEnterDelay()
    }
    let modifierReleaseConfirmationPolicy: ModifierReleaseConfirmationPolicy = .default
    var modifierReleaseConfirmationSampleIntervalNs: UInt64 {
        modifierReleaseConfirmationPolicy.sampleIntervalNanoseconds
    }
    var modifierReleaseConfirmationSampleCount: Int {
        modifierReleaseConfirmationPolicy.requiredReleasedSampleCount
    }
    var postFinishHotkeyIgnoreWindow: TimeInterval {
        modifierReleaseConfirmationPolicy.postFinishHotkeyIgnoreWindow
    }
    let activeSpaceChangeIgnoreWindow: TimeInterval = 0.35
    let terminateInterruptionProtectionWindow: TimeInterval = 5.0
    let postTerminateRefreshInterruptionProtectionWindow: TimeInterval = 0.5
    let panelVisibilityRecoveryPolicy: PanelVisibilityRecoveryPolicy = .default
    var initialPresentationVisibilityGraceWindow: TimeInterval {
        panelVisibilityRecoveryPolicy.initialPresentationGraceWindow
    }
    let activeSpaceMigrationActivationSuppressionWindow: TimeInterval = 0.5
    var interruptionPresentationRecoveryAttemptDelaysNs: [UInt64] {
        panelVisibilityRecoveryPolicy.interruptionAttemptDelaysNanoseconds
    }
    var panelPresentationRecoveryReorderDelayNs: UInt64 {
        panelVisibilityRecoveryPolicy.hardReorderDelayNanoseconds
    }
    let autoEnterWindowLayerEnabled = true
    let tabAdvanceMinimumInterval: TimeInterval = 0.016
    let panelScreenMargin: CGFloat = 80
    let windowOnlyOverlayScreenMargin: CGFloat = 20
    let appLayerMinimumWidth: CGFloat = 440
    let appLayerStaticHeight: CGFloat = 56
    let appLayerSearchHeaderExtraHeight: CGFloat = 68
    let standardPreviewSectionMinimumHeight: CGFloat = 130
    let standardPreviewSectionMaximumHeight: CGFloat = 220
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
    var terminateInterruptionProtectionUntil: TimeInterval = 0
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
    var pointerSelectionGate = SwitcherPointerSelectionGate()

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

    convenience init() {
        self.init(model: LiveSwitcherModel())
    }

    init(model: LiveSwitcherModel) {
        self.model = model
        panel = SwitcherOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 290),
            styleMask: SwitcherPanelWindowConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.sharingType = SwitcherPanelWindowConfiguration.sharingType
        panel.becomesKeyOnlyIfNeeded = false
        panel.identifier = NSUserInterfaceItemIdentifier(AppWindowCoordinator.switcherPanelWindowIdentifier)
        panel.level = SwitcherPanelWindowConfiguration.level
        panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior()
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        let hostingView = NSHostingView(
            rootView: SwitcherPanelRootView(
                model: model,
                pointerSelectionActions: SwitcherPointerSelectionActions(
                    selectApp: { [weak self] appID in
                        self?.selectSwitcherAppByPointer(appID: appID)
                    },
                    selectWindow: { [weak self] appID, windowID in
                        self?.selectSwitcherWindowByPointer(appID: appID, windowID: windowID)
                    },
                    selectSearchResult: { [weak self] resultID in
                        self?.selectSwitcherSearchResultByPointer(resultID: resultID)
                    },
                    commitApp: { [weak self] appID in
                        self?.commitSwitcherAppByPointerClick(appID: appID)
                    },
                    commitWindow: { [weak self] appID, windowID in
                        self?.commitSwitcherWindowByPointerClick(appID: appID, windowID: windowID)
                    },
                    commitSearchResult: { [weak self] resultID in
                        self?.commitSwitcherSearchResultByPointerClick(resultID: resultID)
                    }
                )
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        let contentView = SwitcherPanelContentView(hostingView: hostingView)
        panel.contentView = contentView
        model.onSearchStateChanged = { [weak self] in
            guard let self else { return }
            self.resetPointerSelectionGate()
            guard self.isPanelPresented else { return }
            self.updatePanelSize()
        }
        model.onSessionLayoutChanged = { [weak self] in
            guard let self else { return }
            self.syncPanelAccessibilityAnchors()
            self.resetPointerSelectionGate()
            guard self.isPanelPresented else { return }
            guard self.model.session != nil else {
                self.endPresentationSession()
                return
            }
            self.updatePanelSize()
            self.scheduleDelayedWindowLayerEntryIfNeeded(preservingDeadline: true)
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
                self?.handleWorkspaceApplicationTerminated(appID: appID, pid: pid)
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
        beginPresentationSession(kind: .globalAppSwitcher, trigger: "testing_global_show")
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
        beginPresentationSession(kind: .inAppWindowSwitcher, trigger: "testing_in_app_show")
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

    func handleWorkspaceApplicationTerminatedForTesting(appID: String, pid: pid_t) {
        handleWorkspaceApplicationTerminated(appID: appID, pid: pid)
    }

    func syncPanelAccessibilityAnchors() {
        let appStripHeaderOffset =
            searchFeatureEnabled && !model.isPreviewLayerMode && !model.isSearchActive
            ? appLayerSearchHeaderExtraHeight
            : 0
        panel.updateSwitcherAccessibilityApps(
            model.isSearchActive ? [] : model.session?.apps ?? [],
            tileSize: model.appGridTileSize,
            spacing: model.appGridSpacing,
            appStripHeaderOffset: appStripHeaderOffset
        )
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
        "flowtab.switcher.app.\(id.flowTabAccessibilityIdentifierComponent)"
    }

    static func window(id: String) -> String {
        "flowtab.switcher.window.\(id.flowTabAccessibilityIdentifierComponent)"
    }

    static func windowPreviewImage(id: String) -> String {
        "flowtab.switcher.window-preview-image.\(id.flowTabAccessibilityIdentifierComponent)"
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
