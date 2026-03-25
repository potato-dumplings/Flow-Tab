import AppKit
import SwiftUI
import FlowTabCore

@MainActor
final class SwitcherPanelController {
    private let model = LiveSwitcherModel()
    private let panel: NSPanel

    private var keyDownMonitor: Any?
    private var localFlagsChangedMonitor: Any?
    private var globalFlagsChangedMonitor: Any?
    private var optionReleaseTimer: Timer?
    private var delayedWindowLayerTimer: Timer?
    private let windowLayerPresentationDelay: TimeInterval = 0.22

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 290),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: SwitcherPanelRootView(model: model))
    }

    func handleGlobalHotkey(isBackward: Bool) {
        if panel.isVisible {
            // Main switch hotkey is registered globally, so repeated key presses should keep
            // advancing while the panel is visible.
            advance(isBackward ? .tabBackward : .tabForward)
            return
        }
        let direction: CycleDirection = isBackward ? .backward : .forward
        show(direction: direction)
    }

    private func show(direction: CycleDirection) {
        guard model.startSession(triggerDirection: direction) else {
            RuntimeLog.info("Session", "start failed: no apps")
            NSSound.beep()
            return
        }
        RuntimeLog.info("Session", "start direction=\(direction.debugName) \(self.model.debugSelectionSummary())")

        updatePanelSize()
        installEventMonitors()

        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    private func finishSelection() {
        guard panel.isVisible else { return }
        removeEventMonitors()
        panel.orderOut(nil)
        model.commitSelection()
    }

    private func cancelSelection() {
        guard panel.isVisible else { return }
        removeEventMonitors()
        panel.orderOut(nil)
        model.cancelSelection()
    }

    private func updatePanelSize() {
        let baseWidth = min(max(440, CGFloat(model.appCount) * 84 + 160), 1180)
        let width = model.isPreviewLayerMode ? max(820, baseWidth) : baseWidth
        let height: CGFloat = model.isPreviewLayerMode ? 520 : 240
        let targetSize = NSSize(width: width, height: height)
        if panel.contentRect(forFrameRect: panel.frame).size != targetSize {
            panel.setContentSize(targetSize)
        }
    }

    private func advance(_ keyInput: KeyInput) {
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

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishIfPrimaryModifierReleased()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        optionReleaseTimer = timer
    }

    private func removeEventMonitors() {
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
        if let optionReleaseTimer {
            optionReleaseTimer.invalidate()
            self.optionReleaseTimer = nil
        }
        if let delayedWindowLayerTimer {
            delayedWindowLayerTimer.invalidate()
            self.delayedWindowLayerTimer = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 48:
            if shouldSwallowLocalTabEvent(event) {
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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.contains(activePrimaryModifierFlag()) {
            finishSelection()
        }
    }

    private func finishIfPrimaryModifierReleased() {
        guard panel.isVisible else { return }
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.contains(activePrimaryModifierFlag()) {
            finishSelection()
        }
    }

    private func scheduleDelayedWindowLayerEntryIfNeeded() {
        if let delayedWindowLayerTimer {
            delayedWindowLayerTimer.invalidate()
            self.delayedWindowLayerTimer = nil
        }

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
        }
    }

    private func activePrimaryModifierFlag() -> NSEvent.ModifierFlags {
        SwitcherHotkeyPreferencesStore.load().primaryModifier.eventModifierFlag
    }

    private func shouldSwallowLocalTabEvent(_ event: NSEvent) -> Bool {
        let hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()
        guard hotkeyConfiguration.mainKey == .tab else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(hotkeyConfiguration.primaryModifier.eventModifierFlag) else { return false }

        switch hotkeyConfiguration.primaryModifier {
        case .option:
            return !flags.contains(.command) && !flags.contains(.control)
        case .control:
            return !flags.contains(.command) && !flags.contains(.option)
        case .command:
            return !flags.contains(.control) && !flags.contains(.option)
        }
    }

    private func isTerminateSelectedAppShortcut(_ event: NSEvent) -> Bool {
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

    private let snapshotProvider = RuntimeSnapshotProvider()
    private let activator = RuntimeActivator()
    private let preferences: SwitcherPreferences
    private let iconProvider = AppIconProvider()

    private var runtimeContextsByID: [String: RuntimeAppContext] = [:]
    private var rememberedWindowIDByAppID: [String: String] = [:]
    private var previewCaptureAttemptedKeys: Set<String> = []
    private var autoEnterSuppressedAppID: String?

    init(preferences: SwitcherPreferences = .default) {
        self.preferences = preferences
    }

    var appCount: Int {
        session?.apps.count ?? 0
    }

    var isPreviewLayerMode: Bool {
        guard let session else { return false }
        if case .windowCycle = session.mode {
            return true
        }
        return false
    }

    private func previewImage(for appID: String, window: WindowCandidate) -> NSImage? {
        guard var appContext = runtimeContextsByID[appID] else { return nil }
        guard var windowContext = appContext.windowsByID[window.id] else { return nil }
        if let cached = windowContext.previewImage {
            return cached
        }

        let attemptKey = "\(appID)#\(window.id)"
        if previewCaptureAttemptedKeys.contains(attemptKey) {
            return nil
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
                preferredTitle: windowContext.title
            )
        else {
            RuntimeLog.info("Preview", "attempt failed appID=\(appID) windowID=\(window.id)")
            return nil
        }

        windowContext.cgWindowID = capture.resolvedWindowID
        windowContext.previewImage = capture.image
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
            "attempt success appID=\(appID) windowID=\(window.id) resolvedCG=\(capture.resolvedWindowID)"
        )
        return capture.image
    }

    fileprivate func windowPreviewItems() -> [WindowPreviewItem] {
        guard let session else { return [] }
        guard case .windowCycle(let appID) = session.mode else { return [] }
        guard let app = session.apps.first(where: { $0.id == appID }) else { return [] }

        let selectedIndex = session.selectedWindowIndexByAppID[appID] ?? 0
        return app.windows.enumerated().map { index, window in
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return WindowPreviewItem(
                id: window.id,
                title: title.isEmpty ? app.displayName : title,
                image: previewImage(for: appID, window: window),
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
        loadSnapshot(triggerDirection: triggerDirection, preferredSelectedAppID: nil)
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
            session = nil
            runtimeContextsByID = [:]
            previewCaptureAttemptedKeys = []
            autoEnterSuppressedAppID = nil
            return false
        }

        runtimeContextsByID = snapshot.contextsByID
        previewCaptureAttemptedKeys = []
        autoEnterSuppressedAppID = nil
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
            runtimeContextsByID = [:]
            previewCaptureAttemptedKeys = []
            autoEnterSuppressedAppID = nil
            return
        }
        activator.activate(target: target, contextsByID: runtimeContextsByID)
        runtimeContextsByID = [:]
        previewCaptureAttemptedKeys = []
        autoEnterSuppressedAppID = nil
    }

    func cancelSelection() {
        session = nil
        runtimeContextsByID = [:]
        previewCaptureAttemptedKeys = []
        autoEnterSuppressedAppID = nil
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

private struct SwitcherPanelRootView: View {
    @ObservedObject var model: LiveSwitcherModel
    @AppStorage(AppPreferenceKeys.showShortcutHint) private var showShortcutHint = true

    var body: some View {
        ZStack {
            if let session = model.session {
                CommandTabOverlay(
                    session: session,
                    showShortcutHint: showShortcutHint,
                    isPreviewLayer: model.isPreviewLayerMode,
                    windowPreviewItems: model.windowPreviewItems(),
                    selectedApp: model.selectedApp,
                    iconForApp: { app in
                        model.icon(for: app)
                    }
                )
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

private struct CommandTabOverlay: View {
    let session: SwitcherSession
    let showShortcutHint: Bool
    let isPreviewLayer: Bool
    let windowPreviewItems: [WindowPreviewItem]
    let selectedApp: AppSwitchCandidate?
    let iconForApp: (AppSwitchCandidate) -> NSImage?
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue

    private var isFirstLayer: Bool {
        if case .appCycle = session.mode {
            return true
        }
        return false
    }

    private var appCycleSortedWindows: [WindowCandidate] {
        guard isFirstLayer else { return [] }
        let windows = session.selectedApp.windows
        guard windows.count > 1 else { return [] }
        return windows.sorted { lhs, rhs in
            if lhs.lastActiveAt == rhs.lastActiveAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.lastActiveAt > rhs.lastActiveAt
        }
    }

    private var modeText: String {
        switch session.mode {
        case .appCycle:
            return "应用层"
        case .groupCycle:
            return "分组层"
        case .windowCycle:
            return "窗口层"
        }
    }

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: hotkeyPrimaryModifierRaw,
            mainKeyRaw: hotkeyMainKeyRaw,
            quitKeyRaw: hotkeyQuitKeyRaw
        )
    }

    private func previewCardWidth(availableWidth: CGFloat, itemCount: Int) -> CGFloat {
        let count = max(itemCount, 1)
        let spacing: CGFloat = 12
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let rawWidth = (availableWidth - totalSpacing) / CGFloat(count)
        return max(120, min(360, rawWidth))
    }

    private func previewCardHeight(for cardWidth: CGFloat) -> CGFloat {
        max(130, min(220, cardWidth * 0.62))
    }

    private var appLayerWindowPillsHeight: CGFloat {
        28
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(Array(session.apps.enumerated()), id: \.element.id) { index, app in
                    AppTileView(
                        app: app,
                        isSelected: index == session.selectedAppIndex,
                        icon: iconForApp(app)
                    )
                }
            }

            if isFirstLayer {
                Group {
                    if !appCycleSortedWindows.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(appCycleSortedWindows.enumerated()), id: \.element.id) { index, window in
                                    let isTopCandidate = index == 0
                                    Text(window.title)
                                        .lineLimit(1)
                                        .font(.system(size: 11, weight: isTopCandidate ? .semibold : .regular))
                                        .foregroundStyle(isTopCandidate ? .primary : .secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(
                                            isTopCandidate
                                                ? Color.accentColor.opacity(0.16)
                                                : Color.primary.opacity(0.04),
                                            in: Capsule()
                                        )
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: 520, minHeight: appLayerWindowPillsHeight, maxHeight: appLayerWindowPillsHeight)
            }

            if isPreviewLayer {
                GeometryReader { proxy in
                    let cardWidth = previewCardWidth(
                        availableWidth: max(0, proxy.size.width - 4),
                        itemCount: windowPreviewItems.count
                    )
                    let cardHeight = previewCardHeight(for: cardWidth)

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
                            }
                        }
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: 220)
            }

            HStack(spacing: 8) {
                Text(modeText)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.16), in: Capsule())
                Text(session.selectedApp.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showShortcutHint {
                Text(
                    "Tab / Shift+Tab / ← / → 切换，↑ 分组（窗口层返回应用层）；"
                        + "\(hotkeyConfiguration.quitShortcutText) 结束当前应用；"
                        + "若刚从窗口层返回，本次需按 ↓ 才会再次进入窗口层，松开 \(hotkeyConfiguration.primaryModifier.displayName) 确认"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

private struct WindowPreviewItem: Identifiable {
    let id: String
    let title: String
    let image: NSImage?
    let isSelected: Bool
}

private struct WindowPreviewCard: View {
    let image: NSImage?
    let title: String
    let appIcon: NSImage?
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color(nsColor: .underPageBackgroundColor),
                        Color(nsColor: .windowBackgroundColor)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 84, height: 84)
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                }
            }

            Text(title)
                .lineLimit(1)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.16 : 0.12), radius: isSelected ? 12 : 10, y: 5)
        .scaleEffect(isSelected ? 1 : 0.97)
        .opacity(isSelected ? 1 : 0.92)
        .animation(.easeInOut(duration: 0.14), value: isSelected)
    }
}

private struct AppTileView: View {
    let app: AppSwitchCandidate
    let isSelected: Bool
    let icon: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                )

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
            } else {
                Text(app.displayName.prefix(1).uppercased())
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 68, height: 68)
        .scaleEffect(isSelected ? 1.02 : 0.98)
        .opacity(isSelected ? 1 : 0.88)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}
