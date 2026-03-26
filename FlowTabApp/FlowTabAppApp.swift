import SwiftUI
import AppKit
import ApplicationServices
import FlowTabCore

enum AppPreferenceKeys {
    static let showShortcutHint = "showShortcutHint"
    static let hasPromptedAccessibilityPermission = "hasPromptedAccessibilityPermission"
    static let hotkeyPrimaryModifier = "hotkeyPrimaryModifier"
    static let hotkeyMainKey = "hotkeyMainKey"
    static let hotkeyQuitKey = "hotkeyQuitKey"
    static let windowLayerAutoEnterDelay = "windowLayerAutoEnterDelay"
    static let autoRestoreMinimizedWindowOnSwitch = "autoRestoreMinimizedWindowOnSwitch"
    static let hideMinimizedAppsFromAppLayer = "hideMinimizedAppsFromAppLayer"
    static let enableVerboseDiagnostics = "enableVerboseDiagnostics"
    static let themeMode = "themeMode"
}

extension Notification.Name {
    static let flowTabReRegisterHotkeys = Notification.Name("FlowTab.ReRegisterHotkeys")
}

@MainActor
final class SystemThemeState: ObservableObject {
    static let shared = SystemThemeState()

    @Published private(set) var colorScheme: ColorScheme = .light

    private var appearanceObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?

    private init() {
        refreshColorScheme()

        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshColorScheme()
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshColorScheme()
        }
    }

    deinit {
        if let appearanceObserver {
            DistributedNotificationCenter.default.removeObserver(appearanceObserver)
        }
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
    }

    private func refreshColorScheme() {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let nextColorScheme: ColorScheme = isDark ? .dark : .light
        if colorScheme != nextColorScheme {
            colorScheme = nextColorScheme
        }
    }
}

enum ThemePreferencesStore {
    static let defaultMode: ThemeMode = .followSystem

    static func resolve(rawValue: String) -> ThemeMode {
        ThemeMode(rawValue: rawValue) ?? defaultMode
    }
}

enum WindowLayerPreferencesStore {
    static let defaultAutoEnterDelay: Double = 0.35
    static let minAutoEnterDelay: Double = 0.10
    static let maxAutoEnterDelay: Double = 1.20
    static let autoEnterDelayStep: Double = 0.05

    static func loadAutoEnterDelay(userDefaults: UserDefaults = .standard) -> TimeInterval {
        guard userDefaults.object(forKey: AppPreferenceKeys.windowLayerAutoEnterDelay) != nil else {
            return defaultAutoEnterDelay
        }
        return normalizedAutoEnterDelay(
            userDefaults.double(forKey: AppPreferenceKeys.windowLayerAutoEnterDelay)
        )
    }

    static func normalizedAutoEnterDelay(_ rawValue: Double) -> Double {
        guard rawValue.isFinite else { return defaultAutoEnterDelay }
        let clamped = min(max(rawValue, minAutoEnterDelay), maxAutoEnterDelay)
        let stepCount = ((clamped - minAutoEnterDelay) / autoEnterDelayStep).rounded()
        let quantized = minAutoEnterDelay + stepCount * autoEnterDelayStep
        return (quantized * 100).rounded() / 100
    }
}

enum SwitcherBehaviorPreferencesStore {
    static let defaultAutoRestoreMinimizedWindowOnSwitch = false
    static let defaultHideMinimizedAppsFromAppLayer = false

    static func loadAutoRestoreMinimizedWindowOnSwitch(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.autoRestoreMinimizedWindowOnSwitch) != nil else {
            return defaultAutoRestoreMinimizedWindowOnSwitch
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.autoRestoreMinimizedWindowOnSwitch)
    }

    static func loadHideMinimizedAppsFromAppLayer(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.hideMinimizedAppsFromAppLayer) != nil else {
            return defaultHideMinimizedAppsFromAppLayer
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.hideMinimizedAppsFromAppLayer)
    }

    static func loadSwitcherPreferences(userDefaults: UserDefaults = .standard) -> SwitcherPreferences {
        var preferences = SwitcherPreferences.default
        preferences.autoRestoreMinimizedWindowOnSwitch = loadAutoRestoreMinimizedWindowOnSwitch(
            userDefaults: userDefaults
        )
        return preferences
    }
}

extension ThemeMode {
    var displayName: String {
        switch self {
        case .followSystem:
            return "跟随系统"
        case .light:
            return "纯白（白天）"
        case .dark:
            return "纯黑（黑色）"
        }
    }

    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .followSystem:
            return systemColorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum HomeTab: Hashable {
    case home
    case logs
    case settings
}

@MainActor
final class HomeTabState: ObservableObject {
    static let shared = HomeTabState()
    @Published var selectedTab: HomeTab = .home

    private init() {}
}

enum AppWindowCoordinator {
    static func openHome() {
        Task { @MainActor in
            if HomeTabState.shared.selectedTab != .home {
                HomeTabState.shared.selectedTab = .home
            }
            activateMainWindowOrOpenHomeScene()
        }
    }

    static func openLogs() {
        Task { @MainActor in
            if HomeTabState.shared.selectedTab != .logs {
                HomeTabState.shared.selectedTab = .logs
            }
            activateMainWindowOrOpenHomeScene()
        }
    }

    static func openSettings() {
        Task { @MainActor in
            if HomeTabState.shared.selectedTab != .settings {
                HomeTabState.shared.selectedTab = .settings
            }
            activateMainWindowOrOpenHomeScene()
        }
    }

    @MainActor
    private static func activateMainWindowOrOpenHomeScene() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

@main
struct FlowTabAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("FlowTab") {
            HomeRootView()
        }
        .defaultSize(width: 960, height: 720)

        Settings {
            HomeRootView()
                .frame(minWidth: 960, minHeight: 720)
        }

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    AppWindowCoordinator.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("日志") {
                Button("打开日志") {
                    AppWindowCoordinator.openLogs()
                }
            }

            CommandMenu("设置") {
                Button("打开设置") {
                    AppWindowCoordinator.openSettings()
                }
                Button("打开应用首页") {
                    AppWindowCoordinator.openHome()
                }
            }
        }
    }
}

private struct HomeRootView: View {
    @ObservedObject private var tabState = HomeTabState.shared
    @ObservedObject private var systemTheme = SystemThemeState.shared
    @AppStorage(AppPreferenceKeys.themeMode)
    private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue

    private var themeMode: ThemeMode {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
    }

    private var dividerColor: Color {
        resolvedColorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    private var resolvedColorScheme: ColorScheme {
        themeMode.resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(selectedTab: $tabState.selectedTab)

            Divider()
                .overlay(dividerColor)

            Group {
                switch tabState.selectedTab {
                case .home:
                    HomeLandingView()
                case .logs:
                    AppSettingsView(page: .logs)
                case .settings:
                    AppSettingsView(page: .settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(resolvedColorScheme)
        .animation(.none, value: resolvedColorScheme)
    }
}

private struct HomeSidebar: View {
    @Binding var selectedTab: HomeTab
    @ObservedObject private var systemTheme = SystemThemeState.shared
    @AppStorage(AppPreferenceKeys.themeMode)
    private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue
    private let navIconColumnWidth: CGFloat = 26
    private let navItemSpacing: CGFloat = 18

    private var colorScheme: ColorScheme {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
            .resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    private var sidebarBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.11)
            : Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    private var selectedItemBackgroundColor: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.38)
            : Color(red: 0.76, green: 0.83, blue: 0.95)
    }

    private var normalItemForegroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.90) : Color.primary.opacity(0.90)
    }

    private var selectedItemForegroundColor: Color {
        colorScheme == .dark ? Color.white : Color.black.opacity(0.86)
    }

    private let items: [(tab: HomeTab, title: String, icon: String)] = [
        (.home, "首页", "house.fill"),
        (.logs, "日志", "text.alignleft"),
        (.settings, "设置", "gearshape")
    ]

    var body: some View {
        ZStack {
            sidebarBackgroundColor

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FlowTab")
                            .font(.system(size: 21, weight: .bold))
                            .lineLimit(1)

                        Text("工作台")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.tab) { item in
                        sidebarButton(
                            tab: item.tab,
                            title: item.title,
                            icon: item.icon,
                            isSelected: item.tab == selectedTab
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
        }
        .frame(width: 220)
    }

    @ViewBuilder
    private func sidebarButton(
        tab: HomeTab,
        title: String,
        icon: String,
        isSelected: Bool
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: navItemSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: navIconColumnWidth)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(4)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? selectedItemForegroundColor : normalItemForegroundColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? selectedItemBackgroundColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

private struct HomeLandingView: View {
    @ObservedObject private var diagnostics = RuntimeDiagnostics.shared
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
    @State private var snapshot = RuntimeSnapshot(apps: [], contextsByID: [:])
    @State private var selectedAppID: String?

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: hotkeyPrimaryModifierRaw,
            mainKeyRaw: hotkeyMainKeyRaw,
            quitKeyRaw: hotkeyQuitKeyRaw
        )
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            VStack(alignment: .leading, spacing: 14) {
                header
                statusCard

                HStack(alignment: .top, spacing: 12) {
                    appLayerCard
                    windowLayerCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            while !Task.isCancelled {
                refreshSnapshot()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FlowTab")
                    .font(.system(size: 22, weight: .semibold))

                Text("\(hotkeyConfiguration.mainShortcutText) 快速切换，\(hotkeyConfiguration.quitShortcutText) 结束所选应用")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("重新注册快捷键") {
                NotificationCenter.default.post(name: .flowTabReRegisterHotkeys, object: nil)
                RuntimeLog.info("HotKey", "manual re-register requested")
                refreshSnapshot()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeStatusRow(label: "状态", value: statusLine, emphasizes: hasFailure)
            HomeStatusRow(label: "最近动作", value: lastActionLine, emphasizes: false)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var appLayerCard: some View {
        HomeSectionCard(title: "应用层", subtitle: "当前可切换应用") {
            if snapshot.apps.isEmpty {
                HomeLayerRowView(
                    title: "无可切换应用",
                    subtitle: "先触发一次 \(hotkeyConfiguration.mainShortcutText)",
                    trailing: "0w",
                    isSelected: false
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(snapshot.apps, id: \.id) { app in
                            Button {
                                selectedAppID = app.id
                            } label: {
                                HomeLayerRowView(
                                    title: app.displayName,
                                    subtitle: app.id,
                                    trailing: "\(app.windows.count)w",
                                    isSelected: app.id == currentSelectedAppID
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 500)
            }
        }
    }

    private var windowLayerCard: some View {
        let activeApp = snapshot.apps.first(where: { $0.id == currentSelectedAppID }) ?? snapshot.apps.first
        return HomeSectionCard(
            title: "窗口层",
            subtitle: activeApp.map { "\($0.displayName) 的窗口" } ?? "当前应用窗口"
        ) {
            if let activeApp, !activeApp.windows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(activeApp.windows.enumerated()), id: \.element.id) { index, window in
                            HomeLayerRowView(
                                title: windowTitle(window.title, index: index),
                                subtitle: "",
                                trailing: windowIdentifier(window.id),
                                isSelected: index == 0
                            )
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 500)
            } else if activeApp != nil {
                HomeLayerRowView(
                    title: "当前应用无可切换窗口",
                    subtitle: "请确认辅助功能权限已授权",
                    trailing: "0w",
                    isSelected: false
                )
            } else {
                HomeLayerRowView(
                    title: "暂无窗口数据",
                    subtitle: "等待快照更新",
                    trailing: "--",
                    isSelected: false
                )
            }
        }
    }

    private var currentSelectedAppID: String? {
        if let selectedAppID, snapshot.apps.contains(where: { $0.id == selectedAppID }) {
            return selectedAppID
        }
        return snapshot.apps.first?.id
    }

    private var hasFailure: Bool {
        diagnostics.entries.last(where: { $0.message.localizedCaseInsensitiveContains("failed") }) != nil
    }

    private var statusLine: String {
        if let failed = diagnostics.entries.last(where: { $0.message.localizedCaseInsensitiveContains("failed") }) {
            return failed.message
        }
        return "运行正常"
    }

    private var lastActionLine: String {
        guard let last = diagnostics.entries.last else {
            return "等待触发 \(hotkeyConfiguration.mainShortcutText)"
        }
        return "[\(last.category)] \(last.message)"
    }

    private func windowTitle(_ title: String, index: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Window #\(index + 1)"
        }
        return trimmed
    }

    private func windowIdentifier(_ rawID: String) -> String {
        rawID.replacingOccurrences(of: "ax:", with: "").replacingOccurrences(of: ":", with: "-")
    }

    private func refreshSnapshot() {
        snapshot = RuntimeSnapshotProvider().snapshot()
        syncSelectedApp()
    }

    private func syncSelectedApp() {
        guard !snapshot.apps.isEmpty else {
            selectedAppID = nil
            return
        }
        if let selectedAppID, snapshot.apps.contains(where: { $0.id == selectedAppID }) {
            return
        }
        selectedAppID = snapshot.apps.first?.id
    }
}

private struct HomeBackdropView: View {
    @ObservedObject private var systemTheme = SystemThemeState.shared
    @AppStorage(AppPreferenceKeys.themeMode)
    private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue

    private var colorScheme: ColorScheme {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
            .resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    var body: some View {
        (colorScheme == .dark ? Color.black : Color.white)
            .ignoresSafeArea()
    }
}

private struct HomeSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct HomeStatusRow: View {
    let label: String
    let value: String
    let emphasizes: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: emphasizes ? .semibold : .regular))
                .foregroundStyle(emphasizes ? .red : .primary)
                .lineLimit(1)
        }
    }
}

private struct HomeLayerRowView: View {
    let title: String
    let subtitle: String
    let trailing: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(trailing)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
        )
    }
}

private enum SettingsPage {
    case logs
    case settings
}

private struct AppSettingsView: View {
    let page: SettingsPage

    @AppStorage(AppPreferenceKeys.showShortcutHint) private var showShortcutHint = true
    @AppStorage(AppPreferenceKeys.enableVerboseDiagnostics) private var enableVerboseDiagnostics = false
    @AppStorage(AppPreferenceKeys.themeMode) private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue
    @AppStorage(AppPreferenceKeys.autoRestoreMinimizedWindowOnSwitch)
    private var autoRestoreMinimizedWindowOnSwitch =
        SwitcherBehaviorPreferencesStore.defaultAutoRestoreMinimizedWindowOnSwitch
    @AppStorage(AppPreferenceKeys.hideMinimizedAppsFromAppLayer)
    private var hideMinimizedAppsFromAppLayer =
        SwitcherBehaviorPreferencesStore.defaultHideMinimizedAppsFromAppLayer
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
    @AppStorage(AppPreferenceKeys.windowLayerAutoEnterDelay)
    private var windowLayerAutoEnterDelayRaw = WindowLayerPreferencesStore.defaultAutoEnterDelay
    @ObservedObject private var diagnostics = RuntimeDiagnostics.shared
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var accessibilityPermissionPollTask: Task<Void, Never>?
    @State private var screenCapturePollTask: Task<Void, Never>?
    @State private var windowLayerAutoEnterDelayText = ""
    @FocusState private var isWindowLayerDelayFieldFocused: Bool

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    private var bundlePath: String {
        Bundle.main.bundlePath
    }

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: hotkeyPrimaryModifierRaw,
            mainKeyRaw: hotkeyMainKeyRaw,
            quitKeyRaw: hotkeyQuitKeyRaw
        )
    }

    private var windowLayerAutoEnterDelay: Double {
        WindowLayerPreferencesStore.normalizedAutoEnterDelay(windowLayerAutoEnterDelayRaw)
    }

    private var diagnosticsEntriesForDisplay: [RuntimeDiagnostics.Entry] {
        Array(diagnostics.entries.suffix(300))
    }

    private var pageTitle: String {
        switch page {
        case .logs:
            return "日志"
        case .settings:
            return "设置"
        }
    }

    private var pageSubtitle: String {
        switch page {
        case .logs:
            return "运行日志查看与清理"
        case .settings:
            return "基础显示设置、快捷键与权限"
        }
    }

    private var themeModeCapsuleSelector: some View {
        let modes = ThemeMode.allCases
        return HStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element.rawValue) { index, mode in
                let isSelected = themeModeRaw == mode.rawValue
                Button {
                    themeModeRaw = mode.rawValue
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                if index < modes.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pageTitle)
                            .font(.system(size: 22, weight: .semibold))
                        Text(pageSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if page == .settings {
                        HomeSectionCard(title: "外观", subtitle: "显示与主题") {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("显示快捷键提示", isOn: $showShortcutHint)
                                    .toggleStyle(.switch)
                                    .font(.system(size: 13))

                                HStack(spacing: 10) {
                                    Text("主题模式")
                                        .font(.system(size: 13))
                                    Spacer()
                                    themeModeCapsuleSelector
                                }
                            }
                        }

                        HomeSectionCard(title: "窗口行为", subtitle: "窗口层进入与最小化处理") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Text("窗口层自动进入延迟")
                                        .font(.system(size: 13))
                                    Spacer()
                                    HStack(spacing: 8) {
                                        TextField("0.35", text: $windowLayerAutoEnterDelayText)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12, design: .monospaced))
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 80)
                                            .focused($isWindowLayerDelayFieldFocused)
                                            .onChange(of: windowLayerAutoEnterDelayText) { newValue in
                                                applyWindowLayerAutoEnterDelayText(newValue)
                                            }
                                            .onSubmit {
                                                commitWindowLayerAutoEnterDelayText()
                                            }
                                        Text("秒")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Toggle("切换到最小化窗口时自动恢复打开", isOn: $autoRestoreMinimizedWindowOnSwitch)
                                    .toggleStyle(.switch)
                                    .font(.system(size: 13))

                                Toggle("应用层隐藏仅最小化应用", isOn: $hideMinimizedAppsFromAppLayer)
                                    .toggleStyle(.switch)
                                    .font(.system(size: 13))

                                Text("说明：该过滤依赖辅助功能权限。未授权时无法判断最小化状态，不会过滤应用层。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HomeSectionCard(title: "快捷键", subtitle: "主切换与结束应用按键") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Text("主修饰键")
                                        .font(.system(size: 13))
                                    Spacer()
                                    Picker("主修饰键", selection: $hotkeyPrimaryModifierRaw) {
                                        ForEach(SwitcherPrimaryModifier.allCases) { modifier in
                                            Text(modifier.displayName).tag(modifier.rawValue)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 160)
                                }

                                HStack(spacing: 10) {
                                    Text("主切换按键")
                                        .font(.system(size: 13))
                                    Spacer()
                                    Picker("主切换按键", selection: $hotkeyMainKeyRaw) {
                                        ForEach(SwitcherHotkeyKey.allCases) { key in
                                            Text(key.displayName).tag(key.rawValue)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 160)
                                }

                                HStack(spacing: 10) {
                                    Text("结束应用按键")
                                        .font(.system(size: 13))
                                    Spacer()
                                    Picker("结束应用按键", selection: $hotkeyQuitKeyRaw) {
                                        ForEach(SwitcherHotkeyKey.allCases) { key in
                                            Text(key.displayName).tag(key.rawValue)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 160)
                                }

                                Text(
                                    "当前：\(hotkeyConfiguration.mainShortcutText)"
                                        + "（反向：\(hotkeyConfiguration.backwardShortcutText)）"
                                        + "，结束应用：\(hotkeyConfiguration.quitShortcutText)"
                                )
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            }
                        }

                        HomeSectionCard(title: "权限", subtitle: "辅助功能与屏幕录制") {
                            VStack(alignment: .leading, spacing: 10) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 8) {
                                        permissionStatusBadge(
                                            text: accessibilityTrusted ? "辅助功能权限：已授权" : "辅助功能权限：未授权",
                                            isGranted: accessibilityTrusted
                                        )
                                        permissionStatusBadge(
                                            text: screenCaptureTrusted ? "屏幕录制权限：已授权" : "屏幕录制权限：未授权",
                                            isGranted: screenCaptureTrusted
                                        )
                                        Spacer(minLength: 0)
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        permissionStatusBadge(
                                            text: accessibilityTrusted ? "辅助功能权限：已授权" : "辅助功能权限：未授权",
                                            isGranted: accessibilityTrusted
                                        )
                                        permissionStatusBadge(
                                            text: screenCaptureTrusted ? "屏幕录制权限：已授权" : "屏幕录制权限：未授权",
                                            isGranted: screenCaptureTrusted
                                        )
                                    }
                                }

                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 8) {
                                        requestAccessibilityPermissionButton
                                        requestScreenCapturePermissionButton
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        requestAccessibilityPermissionButton
                                        requestScreenCapturePermissionButton
                                    }
                                }

                                if !accessibilityTrusted {
                                    Text("提示：授权后请完全退出并重启 FlowTabApp，权限状态才会稳定刷新。")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                }

                                if !screenCaptureTrusted {
                                    Text("提示：未授权屏幕录制时，窗口层将只显示兜底预览，无法显示真实窗口画面。")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    if page == .logs {
                        HomeSectionCard(title: "日志", subtitle: "仅日志相关信息") {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("启用详细运行日志（高频，可能影响性能）", isOn: $enableVerboseDiagnostics)
                                    .toggleStyle(.switch)
                                    .font(.system(size: 12))
                                Text("本地日志目录：\(RuntimeDiagnostics.logsDirectoryPath)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)

                                clearLogsButton

                                ScrollView {
                                    Group {
                                        if diagnosticsEntriesForDisplay.isEmpty {
                                            Text("暂无日志。触发 \(hotkeyConfiguration.mainShortcutText) 后再回来看。")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        } else {
                                            LazyVStack(alignment: .leading, spacing: 2) {
                                                ForEach(diagnosticsEntriesForDisplay) { entry in
                                                    Text(entry.displayLine)
                                                        .font(.system(size: 11, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }
                                            }
                                            .textSelection(.enabled)
                                        }
                                    }
                                    .padding(8)
                                }
                                .frame(minHeight: 240, maxHeight: 320)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            enforceThemeModeConsistency()
            enforceHotkeyConsistency()
            enforceWindowLayerPreferencesConsistency()
            syncWindowLayerAutoEnterDelayText()
            refreshAccessibilityStatus()
            refreshScreenCaptureStatus()
        }
        .onChange(of: themeModeRaw) { _ in
            enforceThemeModeConsistency()
        }
        .onChange(of: hotkeyPrimaryModifierRaw) { _ in
            enforceHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: hotkeyMainKeyRaw) { _ in
            enforceHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: hotkeyQuitKeyRaw) { _ in
            enforceHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: isWindowLayerDelayFieldFocused) { isFocused in
            guard !isFocused else { return }
            commitWindowLayerAutoEnterDelayText()
        }
        .onChange(of: windowLayerAutoEnterDelayRaw) { _ in
            enforceWindowLayerPreferencesConsistency()
            if !isWindowLayerDelayFieldFocused {
                syncWindowLayerAutoEnterDelayText()
            }
        }
        .onDisappear {
            accessibilityPermissionPollTask?.cancel()
            screenCapturePollTask?.cancel()
        }
    }

    private var requestAccessibilityPermissionButton: some View {
        Button("请求辅助功能权限") {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            accessibilityPermissionPollTask?.cancel()
            let trusted = AXIsProcessTrustedWithOptions(options)
            RuntimeLog.info(
                "Permission",
                "prompt requested immediateTrusted=\(trusted) bundle=\(bundleIdentifier) path=\(bundlePath)"
            )
            refreshAccessibilityStatus()
            if !trusted {
                startAccessibilityPermissionPolling()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var requestScreenCapturePermissionButton: some View {
        Button("请求屏幕录制权限") {
            screenCapturePollTask?.cancel()
            let trusted = ScreenCapturePermissionChecker.requestScreenCapturePermission()
            RuntimeLog.info(
                "Preview",
                "screenCapture prompt requested immediateTrusted=\(trusted) bundle=\(bundleIdentifier) path=\(bundlePath)"
            )
            refreshScreenCaptureStatus()
            if !trusted {
                startScreenCapturePermissionPolling()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var clearLogsButton: some View {
        Button("清空日志") {
            diagnostics.clear()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func permissionStatusBadge(text: String, isGranted: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isGranted ? Color.green.opacity(0.14) : Color.orange.opacity(0.16))
            )
            .foregroundStyle(isGranted ? .green : .orange)
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    private func refreshScreenCaptureStatus() {
        screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    }

    private func enforceHotkeyConsistency() {
        let resolved = hotkeyConfiguration
        if hotkeyQuitKeyRaw != resolved.quitKey.rawValue {
            hotkeyQuitKeyRaw = resolved.quitKey.rawValue
        }
    }

    private func enforceThemeModeConsistency() {
        let resolved = ThemePreferencesStore.resolve(rawValue: themeModeRaw)
        if themeModeRaw != resolved.rawValue {
            themeModeRaw = resolved.rawValue
        }
    }

    private func enforceWindowLayerPreferencesConsistency() {
        let resolved = WindowLayerPreferencesStore.normalizedAutoEnterDelay(
            windowLayerAutoEnterDelayRaw
        )
        if abs(windowLayerAutoEnterDelayRaw - resolved) > 0.0001 {
            windowLayerAutoEnterDelayRaw = resolved
        }
    }

    private func syncWindowLayerAutoEnterDelayText() {
        let formatted = String(format: "%.2f", windowLayerAutoEnterDelay)
        if windowLayerAutoEnterDelayText != formatted {
            windowLayerAutoEnterDelayText = formatted
        }
    }

    private func applyWindowLayerAutoEnterDelayText(_ rawText: String) {
        let sanitized = sanitizeWindowLayerAutoEnterDelayText(rawText)
        if sanitized != rawText {
            windowLayerAutoEnterDelayText = sanitized
            return
        }
        guard !sanitized.isEmpty else { return }
        guard sanitized != "." else { return }
        guard let parsedValue = Double(sanitized) else { return }
        let normalizedValue = WindowLayerPreferencesStore.normalizedAutoEnterDelay(parsedValue)
        if abs(windowLayerAutoEnterDelayRaw - normalizedValue) > 0.0001 {
            windowLayerAutoEnterDelayRaw = normalizedValue
        }
    }

    private func commitWindowLayerAutoEnterDelayText() {
        let sanitized = sanitizeWindowLayerAutoEnterDelayText(windowLayerAutoEnterDelayText)
        if windowLayerAutoEnterDelayText != sanitized {
            windowLayerAutoEnterDelayText = sanitized
        }
        if let parsedValue = Double(sanitized) {
            windowLayerAutoEnterDelayRaw = WindowLayerPreferencesStore.normalizedAutoEnterDelay(
                parsedValue
            )
        }
        syncWindowLayerAutoEnterDelayText()
    }

    private func sanitizeWindowLayerAutoEnterDelayText(_ rawText: String) -> String {
        var sanitized = ""
        var hasDecimalSeparator = false
        var fractionalDigitCount = 0

        for character in rawText {
            if character.isNumber {
                if hasDecimalSeparator {
                    guard fractionalDigitCount < 2 else { continue }
                    fractionalDigitCount += 1
                }
                sanitized.append(character)
                continue
            }
            if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                if sanitized.isEmpty {
                    sanitized = "0"
                }
                sanitized.append(".")
            }
        }

        return sanitized
    }

    private func notifyHotkeyConfigChanged() {
        RuntimeLog.info(
            "HotKey",
            "updated main=\(hotkeyConfiguration.mainShortcutText) backward=\(hotkeyConfiguration.backwardShortcutText) quit=\(hotkeyConfiguration.quitShortcutText)"
        )
        NotificationCenter.default.post(name: .flowTabReRegisterHotkeys, object: nil)
    }

    private func startAccessibilityPermissionPolling() {
        accessibilityPermissionPollTask = Task { @MainActor in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                refreshAccessibilityStatus()
                if accessibilityTrusted {
                    RuntimeLog.info(
                        "Permission",
                        "trusted=true after prompt bundle=\(bundleIdentifier) path=\(bundlePath)"
                    )
                    accessibilityPermissionPollTask = nil
                    return
                }
            }
            RuntimeLog.info(
                "Permission",
                "still untrusted after waiting 20s bundle=\(bundleIdentifier) path=\(bundlePath)"
            )
            accessibilityPermissionPollTask = nil
        }
    }

    private func startScreenCapturePermissionPolling() {
        screenCapturePollTask = Task { @MainActor in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                refreshScreenCaptureStatus()
                if screenCaptureTrusted {
                    RuntimeLog.info(
                        "Preview",
                        "screenCapture trusted=true after prompt bundle=\(bundleIdentifier) path=\(bundlePath)"
                    )
                    screenCapturePollTask = nil
                    return
                }
            }
            RuntimeLog.info(
                "Preview",
                "screenCapture still untrusted after waiting 20s bundle=\(bundleIdentifier) path=\(bundlePath)"
            )
            screenCapturePollTask = nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: SwitcherPanelController?
    private var hotkeyMonitor: OptionTabHotkeyMonitor?
    private var inAppWindowHotkeyMonitor: OptionTabHotkeyMonitor?
    private var statusItem: NSStatusItem?
    private var hotkeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = SwitcherPanelController()
        self.panelController = panelController

        setupHotkeyMonitor()
        setupInAppWindowHotkeyMonitor()
        installHotkeyObserver()

        installStatusItem()
        requestAccessibilityPermissionIfNeeded()
        AppWindowCoordinator.openHome()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        guard !UserDefaults.standard.bool(forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission)
        else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        UserDefaults.standard.set(true, forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
            self.hotkeyObserver = nil
        }
        hotkeyMonitor?.stop()
        inAppWindowHotkeyMonitor?.stop()
    }

    private func setupHotkeyMonitor() {
        hotkeyMonitor?.stop()

        let hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()
        let monitor = OptionTabHotkeyMonitor(configuration: hotkeyConfiguration)
        monitor.onHotkeyPressed = { [weak panelController] isBackward in
            panelController?.handleGlobalHotkey(isBackward: isBackward)
            RuntimeLog.info(
                "HotKey",
                isBackward ? "HotKey Backward" : "HotKey Forward"
            )
        }
        monitor.onHotkeyReleased = { [weak panelController] isBackward in
            panelController?.handleGlobalHotkeyReleased()
            RuntimeLog.info(
                "HotKey",
                isBackward ? "HotKey Backward Released" : "HotKey Forward Released"
            )
        }
        RuntimeLog.info(
            "HotKey",
            "register main=\(hotkeyConfiguration.mainShortcutText) backward=\(hotkeyConfiguration.backwardShortcutText) quit=\(hotkeyConfiguration.quitShortcutText)"
        )
        hotkeyMonitor = monitor
    }

    private func setupInAppWindowHotkeyMonitor() {
        inAppWindowHotkeyMonitor?.stop()

        let configuredHotkey = SwitcherHotkeyPreferencesStore.load()
        if configuredHotkey.primaryModifier == .control, configuredHotkey.mainKey == .tab {
            RuntimeLog.info("HotKey", "skip register in-app window hotkey due conflict with main shortcut")
            inAppWindowHotkeyMonitor = nil
            return
        }

        let inAppConfiguration = SwitcherHotkeyConfiguration(
            primaryModifier: .control,
            mainKey: .tab,
            quitKey: .q
        )
        let monitor = OptionTabHotkeyMonitor(
            configuration: inAppConfiguration,
            signature: 0x4654574E, // "FTWN"
            forwardHotkeyID: 101,
            backwardHotkeyID: 102
        )
        monitor.onHotkeyPressed = { [weak panelController] isBackward in
            panelController?.handleInAppWindowHotkey(isBackward: isBackward)
            RuntimeLog.info(
                "HotKey",
                isBackward ? "InApp Window Backward" : "InApp Window Forward"
            )
        }
        monitor.onHotkeyReleased = { [weak panelController] _ in
            panelController?.handleInAppWindowHotkeyReleased()
            RuntimeLog.info("HotKey", "InApp Window Released")
        }
        RuntimeLog.info(
            "HotKey",
            "register in-app main=\(inAppConfiguration.mainShortcutText) backward=\(inAppConfiguration.backwardShortcutText)"
        )
        inAppWindowHotkeyMonitor = monitor
    }

    private func installHotkeyObserver() {
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .flowTabReRegisterHotkeys,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.setupHotkeyMonitor()
                self?.setupInAppWindowHotkeyMonitor()
            }
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "FlowTab"

        let menu = NSMenu()

        let openHomeItem = NSMenuItem(
            title: "打开应用首页",
            action: #selector(openHomeFromMenu),
            keyEquivalent: ""
        )
        openHomeItem.target = self
        menu.addItem(openHomeItem)

        let openLogsItem = NSMenuItem(
            title: "日志",
            action: #selector(openLogsFromMenu),
            keyEquivalent: ""
        )
        openLogsItem.target = self
        menu.addItem(openLogsItem)

        let openSettingsItem = NSMenuItem(
            title: "设置",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ""
        )
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 FlowTab",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc
    private func openSettingsFromMenu() {
        AppWindowCoordinator.openSettings()
    }

    @objc
    private func openLogsFromMenu() {
        AppWindowCoordinator.openLogs()
    }

    @objc
    private func openHomeFromMenu() {
        AppWindowCoordinator.openHome()
    }

    @objc
    private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class RuntimeDiagnostics: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let message: String
        let displayLine: String
    }

    static let shared = RuntimeDiagnostics()
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    @Published private(set) var entries: [Entry] = []
    private let maxEntries = 200
    private let flushIntervalNs: UInt64 = 50_000_000
    private let immediateFlushThreshold = 120
    private var pendingEntries: [Entry] = []
    private var flushTask: Task<Void, Never>?
    private let fileStore = RuntimeLogFileStore.shared

    private init() {}

    static func formattedTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static var logsDirectoryPath: String {
        RuntimeLogFileStore.shared.logsDirectoryPath
    }

    func log(category: String, message: String) {
        let timestamp = Date()
        let entry = Entry(
            timestamp: timestamp,
            category: category,
            message: message,
            displayLine: "[\(Self.formattedTimestamp(timestamp))] [\(category)] \(message)"
        )
        pendingEntries.append(entry)
        fileStore.append(entry.displayLine)

        if pendingEntries.count >= immediateFlushThreshold {
            flushPendingEntries()
            return
        }
        scheduleFlushIfNeeded()
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.flushIntervalNs)
            guard !Task.isCancelled else { return }
            self.flushTask = nil
            self.flushPendingEntries()
        }
    }

    private func flushPendingEntries() {
        guard !pendingEntries.isEmpty else { return }
        entries.append(contentsOf: pendingEntries)
        pendingEntries.removeAll(keepingCapacity: true)

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        flushTask?.cancel()
        flushTask = nil
        pendingEntries.removeAll(keepingCapacity: false)
        entries.removeAll()
        fileStore.clear()
    }
}

final class RuntimeLogFileStore {
    static let shared = RuntimeLogFileStore()

    private let queue = DispatchQueue(label: "FlowTab.RuntimeLogFileStore", qos: .utility)
    private let fileManager = FileManager.default
    private let maxFileSizeBytes = 1_000_000
    private let maxArchiveFiles = 4
    private let flushDelay: TimeInterval = 0.05
    private let immediateFlushThreshold = 120
    private let logsDirectoryURL: URL
    private let activeLogURL: URL
    private var pendingLines: [String] = []
    private var flushWorkItem: DispatchWorkItem?

    var logsDirectoryPath: String {
        logsDirectoryURL.path
    }

    private init() {
        let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallbackURL
        logsDirectoryURL = baseURL.appendingPathComponent("FlowTabApp/logs", isDirectory: true)
        activeLogURL = logsDirectoryURL.appendingPathComponent("runtime.log", isDirectory: false)
    }

    func append(_ line: String) {
        queue.async {
            self.pendingLines.append(line)
            if self.pendingLines.count >= self.immediateFlushThreshold {
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.flushLocked()
                return
            }
            self.scheduleFlushLocked()
        }
    }

    func clear() {
        queue.async {
            self.flushWorkItem?.cancel()
            self.flushWorkItem = nil
            self.pendingLines.removeAll(keepingCapacity: false)
            self.clearFilesLocked()
        }
    }

    private func scheduleFlushLocked() {
        guard flushWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.flushWorkItem = nil
            self.flushLocked()
        }
        flushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + flushDelay, execute: workItem)
    }

    private func flushLocked() {
        guard !pendingLines.isEmpty else { return }
        let block = pendingLines.joined(separator: "\n") + "\n"
        pendingLines.removeAll(keepingCapacity: true)

        do {
            try ensureLogsDirectoryLocked()
            try rotateIfNeededLocked(appendingByteCount: block.utf8.count)
            try appendToFileLocked(block)
        } catch {}
    }

    private func ensureLogsDirectoryLocked() throws {
        if fileManager.fileExists(atPath: logsDirectoryURL.path) {
            return
        }
        try fileManager.createDirectory(
            at: logsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func appendToFileLocked(_ block: String) throws {
        if !fileManager.fileExists(atPath: activeLogURL.path) {
            try block.write(to: activeLogURL, atomically: true, encoding: .utf8)
            return
        }

        let handle = try FileHandle(forWritingTo: activeLogURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(block.utf8))
    }

    private func rotateIfNeededLocked(appendingByteCount: Int) throws {
        let currentSize = fileSizeLocked(for: activeLogURL)
        if currentSize + appendingByteCount <= maxFileSizeBytes {
            return
        }

        let oldestURL = archiveLogURL(index: maxArchiveFiles)
        if fileManager.fileExists(atPath: oldestURL.path) {
            try fileManager.removeItem(at: oldestURL)
        }

        if maxArchiveFiles > 1 {
            for index in stride(from: maxArchiveFiles - 1, through: 1, by: -1) {
                let sourceURL = archiveLogURL(index: index)
                let destinationURL = archiveLogURL(index: index + 1)
                if fileManager.fileExists(atPath: sourceURL.path) {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
            }
        }

        if fileManager.fileExists(atPath: activeLogURL.path) {
            try fileManager.moveItem(at: activeLogURL, to: archiveLogURL(index: 1))
        }
    }

    private func archiveLogURL(index: Int) -> URL {
        logsDirectoryURL.appendingPathComponent("runtime.\(index).log", isDirectory: false)
    }

    private func fileSizeLocked(for url: URL) -> Int {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.intValue
    }

    private func clearFilesLocked() {
        if fileManager.fileExists(atPath: activeLogURL.path) {
            try? fileManager.removeItem(at: activeLogURL)
        }
        for index in 1...maxArchiveFiles {
            let archiveURL = archiveLogURL(index: index)
            if fileManager.fileExists(atPath: archiveURL.path) {
                try? fileManager.removeItem(at: archiveURL)
            }
        }
    }
}

enum RuntimeLog {
    private static let noisyCategories: Set<String> = [
        "InputTrace",
        "AX",
        "Snapshot",
        "HotKey",
        "Session",
        "AutoEnter",
        "Manual"
    ]

    private static var isVerboseEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKeys.enableVerboseDiagnostics)
    }

    private static func shouldRecord(_ category: String) -> Bool {
        if noisyCategories.contains(category) {
            return isVerboseEnabled
        }
        return true
    }

    static func info(_ category: String, _ message: @autoclosure @escaping () -> String) {
        guard shouldRecord(category) else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                RuntimeDiagnostics.shared.log(category: category, message: message())
            }
            return
        }
        Task { @MainActor in
            RuntimeDiagnostics.shared.log(category: category, message: message())
        }
    }
}
