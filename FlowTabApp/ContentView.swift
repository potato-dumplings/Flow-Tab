import Carbon
import Foundation

final class OptionTabHotkeyMonitor {
    var onHotkeyPressed: ((Bool) -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]

    private let signature: OSType = 0x46544142 // "FTAB"
    private let forwardHotkeyID: UInt32 = 1
    private let backwardHotkeyID: UInt32 = 2

    init() {
        installHandler()
        registerHotkeys()
    }

    deinit {
        stop()
    }

    func stop() {
        for hotkeyRef in hotkeyRefs.values {
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let monitor = Unmanaged<OptionTabHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                return monitor.handleHotkeyEvent(event)
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
        }
    }

    private func registerHotkeys() {
        registerHotkey(id: forwardHotkeyID, modifiers: UInt32(optionKey))
        registerHotkey(id: backwardHotkeyID, modifiers: UInt32(optionKey | shiftKey))
    }

    private func registerHotkey(id: UInt32, modifiers: UInt32) {
        let hotkeyID = EventHotKeyID(signature: signature, id: id)
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(kVK_Tab),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr, let hotkeyRef {
            hotkeyRefs[id] = hotkeyRef
        }
    }

    private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr, hotkeyID.signature == signature else {
            return noErr
        }

        switch hotkeyID.id {
        case forwardHotkeyID:
            onHotkeyPressed?(false)
        case backwardHotkeyID:
            onHotkeyPressed?(true)
        default:
            break
        }
        return noErr
    }
}
import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

struct RuntimeSnapshot {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
}

struct RuntimeAppContext {
    let appID: String
    let runningApp: NSRunningApplication
    let windowsByID: [String: RuntimeWindowContext]
}

struct RuntimeWindowContext {
    let id: String
    let title: String
    let isMinimized: Bool
}

@MainActor
final class RuntimeSnapshotProvider {
    private struct WindowListEntry {
        let windowID: CGWindowID
        let title: String
        let isMinimized: Bool
    }

    func snapshot() -> RuntimeSnapshot {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && !$0.isTerminated
                && $0.processIdentifier != currentPID
        }

        guard !runningApps.isEmpty else {
            return RuntimeSnapshot(apps: [], contextsByID: [:])
        }

        let windowData = collectWindowData()
        let now = Date.timeIntervalSinceReferenceDate

        var rows: [(candidate: AppSwitchCandidate, context: RuntimeAppContext)] = []
        rows.reserveCapacity(runningApps.count)

        for (index, app) in runningApps.enumerated() {
            let pid = app.processIdentifier
            let appID = app.bundleIdentifier ?? "pid:\(pid)"
            let displayName = app.localizedName ?? appID

            let windows = windowData.windowsByPID[pid] ?? []
            let windowCandidates = windows.enumerated().map { entryIndex, entry in
                WindowCandidate(
                    id: String(entry.windowID),
                    title: entry.title,
                    isMinimized: entry.isMinimized,
                    lastActiveAt: now - Double(entryIndex)
                )
            }

            let rank = windowData.rankByPID[pid] ?? (10_000 + index)
            let candidate = AppSwitchCandidate(
                id: appID,
                displayName: displayName,
                groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
                lastActiveAt: now - Double(rank),
                windows: windowCandidates
            )

            let windowContexts = Dictionary(
                uniqueKeysWithValues: windows.map {
                    let id = String($0.windowID)
                    return (
                        id,
                        RuntimeWindowContext(
                            id: id,
                            title: $0.title,
                            isMinimized: $0.isMinimized
                        )
                    )
                }
            )
            let context = RuntimeAppContext(
                appID: appID,
                runningApp: app,
                windowsByID: windowContexts
            )
            rows.append((candidate, context))
        }

        rows.sort { lhs, rhs in
            if lhs.candidate.lastActiveAt == rhs.candidate.lastActiveAt {
                return lhs.candidate.displayName.localizedCaseInsensitiveCompare(
                    rhs.candidate.displayName
                ) == .orderedAscending
            }
            return lhs.candidate.lastActiveAt > rhs.candidate.lastActiveAt
        }

        return RuntimeSnapshot(
            apps: rows.map(\.candidate),
            contextsByID: Dictionary(uniqueKeysWithValues: rows.map { ($0.context.appID, $0.context) })
        )
    }

    private func collectWindowData() -> (
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return ([:], [:])
        }

        var windowsByPID: [pid_t: [WindowListEntry]] = [:]
        var rankByPID: [pid_t: Int] = [:]

        for (rank, item) in rawList.enumerated() {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? UInt32 else { continue }

            let title = Self.windowTitle(from: item)
            guard !title.isEmpty else { continue }
            let isOnScreen = (item[kCGWindowIsOnscreen as String] as? Int) == 1

            if rankByPID[ownerPID] == nil {
                rankByPID[ownerPID] = rank
            }

            windowsByPID[ownerPID, default: []].append(
                WindowListEntry(windowID: windowNumber, title: title, isMinimized: !isOnScreen)
            )
        }

        return (windowsByPID, rankByPID)
    }

    private static func windowTitle(from windowInfo: [String: Any]) -> String {
        let rawTitle = (windowInfo[kCGWindowName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawTitle, !rawTitle.isEmpty {
            return rawTitle
        }

        let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ownerName ?? ""
    }

    private static func groupID(for bundleIdentifier: String?, fallbackName: String) -> String {
        guard let bundleIdentifier else {
            return String(fallbackName.prefix(1)).lowercased()
        }

        let components = bundleIdentifier.split(separator: ".")
        if components.count >= 2 {
            return String(components[1])
        }
        if let first = components.first {
            return String(first)
        }
        return "apps"
    }
}

@MainActor
final class RuntimeActivator {
    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext]) {
        switch target {
        case .app(let appID):
            activateApp(appID: appID, contextsByID: contextsByID)
        case .window(let appID, let windowID, let restoreIfMinimized):
            activateWindow(
                appID: appID,
                windowID: windowID,
                restoreIfMinimized: restoreIfMinimized,
                contextsByID: contextsByID
            )
        }
    }

    private func activateApp(appID: String, contextsByID: [String: RuntimeAppContext]) {
        guard let context = contextsByID[appID] else { return }
        context.runningApp.activate(options: [.activateAllWindows])
    }

    private func activateWindow(
        appID: String,
        windowID: String,
        restoreIfMinimized: Bool,
        contextsByID: [String: RuntimeAppContext]
    ) {
        guard let context = contextsByID[appID] else { return }
        context.runningApp.activate(options: [.activateAllWindows])
        guard let windowContext = context.windowsByID[windowID] else { return }
        focusWindow(
            withTitle: windowContext.title,
            restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized,
            in: context.runningApp
        )
    }

    private func focusWindow(
        withTitle targetTitle: String,
        restoreIfMinimized: Bool,
        in app: NSRunningApplication
    ) {
        guard AXIsProcessTrusted() else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
                == .success,
            let windows = windowsValue as? [AXUIElement]
        else {
            return
        }

        for window in windows {
            guard let title = windowTitle(for: window), title == targetTitle else { continue }
            if restoreIfMinimized {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return
        }
    }

    private func windowTitle(for window: AXUIElement) -> String? {
        var titleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                == .success,
            let title = (titleValue as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return nil
        }
        return title
    }
}

final class AppIconProvider {
    private var cache: [String: NSImage] = [:]

    func icon(for app: AppSwitchCandidate, context: RuntimeAppContext?) -> NSImage? {
        if let cached = cache[app.id] {
            return cached
        }

        if let runtimeIcon = context?.runningApp.icon {
            cache[app.id] = runtimeIcon
            return runtimeIcon
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[app.id] = icon
        return icon
    }
}
import AppKit
import SwiftUI
import FlowTabCore

@MainActor
final class SwitcherPanelController {
    private let model = LiveSwitcherModel()
    private let panel: NSPanel

    private var keyDownMonitor: Any?
    private var flagsChangedMonitor: Any?

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
        guard !panel.isVisible else { return }
        let direction: CycleDirection = isBackward ? .backward : .forward
        show(direction: direction)
    }

    private func show(direction: CycleDirection) {
        guard model.startSession(triggerDirection: direction) else {
            NSSound.beep()
            return
        }

        updatePanelSize()
        installEventMonitors()

        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
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
        let width = min(max(480, CGFloat(model.appCount) * 102 + 180), 1320)
        panel.setContentSize(NSSize(width: width, height: 290))
    }

    private func installEventMonitors() {
        removeEventMonitors()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handleKeyDown(event) ? nil : event
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return nil
        }
    }

    private func removeEventMonitors() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let flagsChangedMonitor {
            NSEvent.removeMonitor(flagsChangedMonitor)
            self.flagsChangedMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 48:
            model.handle(event.modifierFlags.contains(.shift) ? .tabBackward : .tabForward)
            return true
        case 123:
            model.handle(.leftArrow)
            return true
        case 124:
            model.handle(.rightArrow)
            return true
        case 125:
            model.handle(.downArrow)
            return true
        case 126:
            model.handle(.upArrow)
            return true
        case 36, 76:
            finishSelection()
            return true
        case 53:
            cancelSelection()
            return true
        default:
            return false
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.contains(.option) {
            finishSelection()
        }
    }
}

@MainActor
final class LiveSwitcherModel: ObservableObject {
    @Published private(set) var session: SwitcherSession?

    private let snapshotProvider = RuntimeSnapshotProvider()
    private let activator = RuntimeActivator()
    private let preferences: SwitcherPreferences
    private let iconProvider = AppIconProvider()

    private var runtimeContextsByID: [String: RuntimeAppContext] = [:]
    private var rememberedWindowIDByAppID: [String: String] = [:]

    init(preferences: SwitcherPreferences = .default) {
        self.preferences = preferences
    }

    var appCount: Int {
        session?.apps.count ?? 0
    }

    var modeText: String {
        guard let session else { return "" }
        switch session.mode {
        case .appCycle:
            return "应用层"
        case .groupCycle:
            return "分组层"
        case .windowCycle:
            return "窗口层"
        }
    }

    var selectionText: String {
        guard let session else { return "" }
        if let selectedWindow = session.selectedWindow {
            return "当前选择：\(session.selectedApp.displayName) · \(selectedWindow.title)"
        }
        return "当前选择：\(session.selectedApp.displayName)"
    }

    func selectedWindowID() -> String? {
        session?.selectedWindow?.id
    }

    func icon(for app: AppSwitchCandidate) -> NSImage? {
        iconProvider.icon(for: app, context: runtimeContextsByID[app.id])
    }

    func startSession(triggerDirection: CycleDirection) -> Bool {
        let snapshot = snapshotProvider.snapshot()
        guard !snapshot.apps.isEmpty else {
            session = nil
            runtimeContextsByID = [:]
            return false
        }

        runtimeContextsByID = snapshot.contextsByID
        session = SwitcherSession(
            apps: snapshot.apps,
            preferences: preferences,
            triggerDirection: triggerDirection,
            rememberedWindowIDByAppID: rememberedWindowIDByAppID
        )
        return true
    }

    func handle(_ keyInput: KeyInput) {
        guard var session else { return }
        session.handle(keyInput)
        self.session = session
    }

    func commitSelection() {
        guard var session else { return }
        let target = session.commitSelection()
        rememberedWindowIDByAppID = session.rememberedWindowIDByAppID
        self.session = nil

        guard let target else {
            runtimeContextsByID = [:]
            return
        }
        activator.activate(target: target, contextsByID: runtimeContextsByID)
        runtimeContextsByID = [:]
    }

    func cancelSelection() {
        session = nil
        runtimeContextsByID = [:]
    }
}

private struct SwitcherPanelRootView: View {
    @ObservedObject var model: LiveSwitcherModel

    var body: some View {
        ZStack {
            if let session = model.session {
                CommandTabOverlay(
                    session: session,
                    modeText: model.modeText,
                    selectionText: model.selectionText,
                    selectedWindowID: model.selectedWindowID(),
                    iconForApp: { app in
                        model.icon(for: app)
                    }
                )
                .padding(26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

private struct CommandTabOverlay: View {
    let session: SwitcherSession
    let modeText: String
    let selectionText: String
    let selectedWindowID: String?
    let iconForApp: (AppSwitchCandidate) -> NSImage?

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ForEach(Array(session.apps.enumerated()), id: \.element.id) { index, app in
                    AppTileView(
                        app: app,
                        isSelected: index == session.selectedAppIndex,
                        icon: iconForApp(app)
                    )
                }
            }

            Text(session.selectedApp.displayName)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(modeText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.white.opacity(0.14), in: Capsule())

            if case .windowCycle(let appID) = session.mode,
               let app = session.apps.first(where: { $0.id == appID }),
               !app.windows.isEmpty {
                HStack(spacing: 8) {
                    ForEach(app.windows, id: \.id) { window in
                        let isSelected = window.id == selectedWindowID
                        Text(window.title)
                            .lineLimit(1)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? Color.white : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                    }
                }
            }

            Text(selectionText)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.78))

            Text("Tab / Shift+Tab 切换，↑ 分组，↓ 窗口，松开 Option 确认")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 28, y: 10)
    }
}

private struct AppTileView: View {
    let app: AppSwitchCandidate
    let isSelected: Bool
    let icon: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.2 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isSelected ? Color.white.opacity(0.55) : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 1.4 : 1
                        )
                )

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
            } else {
                Text(app.displayName.prefix(1).uppercased())
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: 80, height: 80)
        .scaleEffect(isSelected ? 1.05 : 0.97)
        .opacity(isSelected ? 1 : 0.76)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}
