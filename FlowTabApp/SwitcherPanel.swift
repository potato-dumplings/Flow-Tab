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
