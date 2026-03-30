import SwiftUI
import AppKit
import ApplicationServices
import FlowTabCore

enum AppPreferenceKeys {
    static let showShortcutHint = "showShortcutHint"
    static let showInCommandTab = "showInCommandTab"
    static let showPermissionReminder = "showPermissionReminder"
    static let hasPromptedAccessibilityPermission = "hasPromptedAccessibilityPermission"
    static let hotkeyPrimaryModifier = "hotkeyPrimaryModifier"
    static let hotkeyMainKey = "hotkeyMainKey"
    static let hotkeyQuitKey = "hotkeyQuitKey"
    static let inAppWindowHotkeyPrimaryModifier = "inAppWindowHotkeyPrimaryModifier"
    static let inAppWindowHotkeyMainKey = "inAppWindowHotkeyMainKey"
    static let windowLayerAutoEnterDelay = "windowLayerAutoEnterDelay"
    static let autoRestoreMinimizedWindowOnSwitch = "autoRestoreMinimizedWindowOnSwitch"
    static let hideMinimizedAppsFromAppLayer = "hideMinimizedAppsFromAppLayer"
    static let searchEnabled = "searchEnabled"
    static let searchDefaultScope = "searchDefaultScope"
    static let enableVerboseDiagnostics = "enableVerboseDiagnostics"
    static let runtimeLogLevel = "runtimeLogLevel"
    static let themeMode = "themeMode"
}

enum RuntimeLogLevel: String, CaseIterable, Comparable, Identifiable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var id: String { rawValue }

    var displayName: String {
        rawValue
    }

    private var priority: Int {
        switch self {
        case .debug:
            return 0
        case .info:
            return 1
        case .warning:
            return 2
        case .error:
            return 3
        }
    }

    static func < (lhs: RuntimeLogLevel, rhs: RuntimeLogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

enum RuntimeLogPreferencesStore {
    static let defaultLevel: RuntimeLogLevel = .error

    static func resolve(rawValue: String) -> RuntimeLogLevel {
        RuntimeLogLevel(rawValue: rawValue) ?? defaultLevel
    }

    static func loadMinimumLevel(userDefaults: UserDefaults = .standard) -> RuntimeLogLevel {
        let rawValue = userDefaults.string(forKey: AppPreferenceKeys.runtimeLogLevel) ?? defaultLevel.rawValue
        let resolved = resolve(rawValue: rawValue)
        if rawValue != resolved.rawValue {
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        }
        return resolved
    }
}

extension Notification.Name {
    static let flowTabReRegisterHotkeys = Notification.Name("FlowTab.ReRegisterHotkeys")
    static let flowTabAppVisibilityPreferenceChanged = Notification.Name(
        "FlowTab.AppVisibilityPreferenceChanged"
    )
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
            Task { @MainActor [weak self] in
                self?.refreshColorScheme()
            }
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshColorScheme()
            }
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

enum AppVisibilityPreferencesStore {
    static let defaultShowInCommandTab = true

    static func loadShowInCommandTab(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.showInCommandTab) != nil else {
            return defaultShowInCommandTab
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.showInCommandTab)
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

enum SearchInteractionPreferencesStore {
    static let defaultIsEnabled = true
    static let defaultScope: SwitcherSearchScope = .app

    static func loadIsEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.searchEnabled) != nil else {
            return defaultIsEnabled
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.searchEnabled)
    }

    static func loadDefaultScope(userDefaults: UserDefaults = .standard) -> SwitcherSearchScope {
        let rawValue = userDefaults.string(forKey: AppPreferenceKeys.searchDefaultScope) ?? defaultScope.rawValue
        let resolved = SwitcherSearchScope(rawValue: rawValue) ?? defaultScope
        if rawValue != resolved.rawValue {
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)
        }
        return resolved
    }
}

enum InAppWindowHotkeyPreferencesStore {
    static let defaultPrimaryModifier: SwitcherPrimaryModifier = .control
    static let defaultMainKey: SwitcherHotkeyKey = .tab

    static func load(userDefaults: UserDefaults = .standard) -> SwitcherHotkeyConfiguration {
        let primaryModifierRaw = userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier)
            ?? defaultPrimaryModifier.rawValue
        let mainKeyRaw = userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey)
            ?? defaultMainKey.rawValue

        let resolved = resolve(
            primaryModifierRaw: primaryModifierRaw,
            mainKeyRaw: mainKeyRaw
        )

        if primaryModifierRaw != resolved.primaryModifier.rawValue {
            userDefaults.set(
                resolved.primaryModifier.rawValue,
                forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier
            )
        }
        if mainKeyRaw != resolved.mainKey.rawValue {
            userDefaults.set(
                resolved.mainKey.rawValue,
                forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey
            )
        }

        return SwitcherHotkeyConfiguration(
            primaryModifier: resolved.primaryModifier,
            mainKey: resolved.mainKey,
            quitKey: .q
        )
    }

    static func resolve(
        primaryModifierRaw: String,
        mainKeyRaw: String
    ) -> (primaryModifier: SwitcherPrimaryModifier, mainKey: SwitcherHotkeyKey) {
        let primaryModifier = SwitcherPrimaryModifier(rawValue: primaryModifierRaw) ?? defaultPrimaryModifier
        let mainKey = SwitcherHotkeyKey(rawValue: mainKeyRaw) ?? defaultMainKey
        return (primaryModifier, mainKey)
    }
}

extension ThemeMode {
    var displayName: String {
        switch self {
        case .followSystem:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
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

@MainActor
private final class TabSwitchStressRunner {
    static let shared = TabSwitchStressRunner()

    private var task: Task<Void, Never>?

    private init() {}

    func startIfNeeded() {
        guard task == nil else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--flowtab-tab-stress") else { return }

        let durationSeconds = max(
            1,
            Double(argumentValue(after: "--flowtab-tab-stress-duration", in: arguments) ?? "") ?? 30
        )
        let intervalMilliseconds = max(
            1,
            Double(argumentValue(after: "--flowtab-tab-stress-interval-ms", in: arguments) ?? "") ?? 20
        )
        let sleepNanoseconds = UInt64(intervalMilliseconds * 1_000_000)
        let endTime = Date().addingTimeInterval(durationSeconds)

        task = Task { @MainActor in
            defer { self.task = nil }

            let cycle: [HomeTab] = [.home, .logs, .settings]
            var index = 0
            while Date() < endTime {
                HomeTabState.shared.selectedTab = cycle[index % cycle.count]
                index += 1
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            }
            NSApp.terminate(nil)
        }
    }

    private func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        return arguments[nextIndex]
    }
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
    static func activateMainWindowOrOpenHomeScene() {
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
    private let appWindowWidth: CGFloat = 1120
    private let appWindowHeight: CGFloat = 760

    init() {
        SystemAppMRUTracker.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup("FlowTab") {
            HomeRootView()
                .frame(minWidth: appWindowWidth, minHeight: appWindowHeight)
        }
        .defaultSize(width: appWindowWidth, height: appWindowHeight)

        Settings {
            HomeRootView()
                .frame(minWidth: appWindowWidth, minHeight: appWindowHeight)
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
                    HomeLandingView(isActive: true) {
                        tabState.selectedTab = .settings
                    }
                case .logs:
                    AppLogsView(isActive: true)
                case .settings:
                    AppSettingsView(isActive: true)
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

    private func sidebarButtonIdentifier(for tab: HomeTab) -> String {
        switch tab {
        case .home:
            return "flowtab.sidebar.tab.home"
        case .logs:
            return "flowtab.sidebar.tab.logs"
        case .settings:
            return "flowtab.sidebar.tab.settings"
        }
    }

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
        .accessibilityIdentifier(sidebarButtonIdentifier(for: tab))
    }
}

@MainActor
private struct HomeLandingView: View {
    private static let snapshotQueue = DispatchQueue(
        label: "FlowTab.HomeLandingSnapshotQueue",
        qos: .utility
    )
    private static var cachedAppSummaries: [RuntimeHomeAppSummary] = []
    private static var cachedWindowsByAppID: [String: [WindowCandidate]] = [:]
    private static var cachedSelectedAppID: String?
    private static var cachedAccessibilityTrusted = AXIsProcessTrusted()
    private static var cachedScreenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    private static var cachedRunningAppSignature: Set<String> = []

    let isActive: Bool
    let openSettings: () -> Void

    @AppStorage(AppPreferenceKeys.showPermissionReminder)
    private var showPermissionReminder = true
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var appSummaries: [RuntimeHomeAppSummary] = []
    @State private var windowsByAppID: [String: [WindowCandidate]] = [:]
    @State private var selectedAppID: String?
    @State private var appSummariesRefreshTask: Task<Void, Never>?
    @State private var selectedAppRefreshTask: Task<Void, Never>?
    @State private var appRefreshTasksByID: [String: Task<Void, Never>] = [:]
    @State private var permissionWatchTask: Task<Void, Never>?
    @State private var windowChangeMonitor = HomeWindowChangeMonitor()

    private let appRefreshDebounceDelayNs: UInt64 = 220_000_000
    private let selectedAppRefreshDebounceDelayNs: UInt64 = 120_000_000
    private let permissionPollIntervalNs: UInt64 = 1_000_000_000

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: hotkeyPrimaryModifierRaw,
            mainKeyRaw: hotkeyMainKeyRaw,
            quitKeyRaw: hotkeyQuitKeyRaw
        )
    }

    private var shouldShowPermissionGuide: Bool {
        showPermissionReminder && (!accessibilityTrusted || !screenCaptureTrusted)
    }

    private var permissionGuideMessage: String {
        if !accessibilityTrusted && !screenCaptureTrusted {
            return "请开启辅助功能和屏幕录制权限，部分功能才能正常使用。"
        }
        if !accessibilityTrusted {
            return "请开启辅助功能权限，应用切换与窗口功能才能正常使用。"
        }
        if !screenCaptureTrusted {
            return "请开启屏幕录制权限，窗口预览功能才能正常使用。"
        }
        return "权限已开启。"
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            VStack(alignment: .leading, spacing: 12) {
                if shouldShowPermissionGuide {
                    permissionGuideBanner
                }

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
        .onAppear {
            handleVisibilityChanged(isActive)
        }
        .onChange(of: isActive) { _, active in
            handleVisibilityChanged(active)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )) { _ in
            guard isActive else { return }
            scheduleAppSummariesRefresh(reason: "workspace_launch")
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )) { _ in
            guard isActive else { return }
            scheduleAppSummariesRefresh(reason: "workspace_terminate")
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            guard isActive else { return }
            refreshPermissionsIfNeeded(reason: "app_active")
            scheduleRefreshIfRunningAppsChanged(reason: "app_active")
        }
        .onDisappear {
            teardownActiveState()
        }
        .accessibilityIdentifier("flowtab.tab.home.content")
    }

    private var permissionGuideBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text(permissionGuideMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            FlowActionButton(title: "前往设置", tone: .blueDominant) {
                openSettings()
            }

            FlowActionButton(title: "不再提示", tone: .grayDominant) {
                showPermissionReminder = false
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var appLayerCard: some View {
        HomeSectionCard(title: "应用层", subtitle: "当前可切换应用") {
            if appSummaries.isEmpty {
                HomeLayerRowView(
                    title: "无可切换应用",
                    subtitle: "先触发一次 \(hotkeyConfiguration.mainShortcutText)",
                    trailing: "0w",
                    isSelected: false
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appSummaries) { app in
                            Button {
                                selectApp(app.appID)
                            } label: {
                                HomeLayerRowView(
                                    title: app.displayName,
                                    subtitle: app.appID,
                                    trailing: "\(app.windowCount)w",
                                    isSelected: app.appID == currentSelectedAppID
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
        let activeApp = appSummaries.first(where: { $0.appID == currentSelectedAppID }) ?? appSummaries.first
        let activeWindows = activeApp.flatMap { windowsByAppID[$0.appID] } ?? []

        return HomeSectionCard(
            title: "窗口层",
            subtitle: activeApp.map { "\($0.displayName) 的窗口" } ?? "当前应用窗口"
        ) {
            if let activeApp, windowsByAppID[activeApp.appID] == nil {
                HomeLayerRowView(
                    title: "窗口数据加载中",
                    subtitle: "正在读取 \(activeApp.displayName) 的窗口",
                    trailing: "--",
                    isSelected: false
                )
            } else if let activeApp, !activeWindows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(activeWindows.enumerated()), id: \.element.id) { index, window in
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
                    subtitle: "等待缓存更新",
                    trailing: "--",
                    isSelected: false
                )
            }
        }
    }

    private var currentSelectedAppID: String? {
        if let selectedAppID, appSummaries.contains(where: { $0.appID == selectedAppID }) {
            return selectedAppID
        }
        return appSummaries.first?.appID
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

    private func handleVisibilityChanged(_ active: Bool) {
        guard active else {
            teardownActiveState()
            return
        }

        restoreCachedStateIfNeeded()
        setupWindowMonitorIfNeeded()
        refreshPermissionsIfNeeded(reason: "appear")
        startPermissionWatcherIfNeeded()

        if appSummaries.isEmpty {
            scheduleAppSummariesRefresh(reason: "initial_load")
            return
        }

        scheduleRefreshIfRunningAppsChanged(reason: "appear")
        if let selectedAppID = currentSelectedAppID {
            scheduleSelectedAppRefresh(
                appID: selectedAppID,
                force: windowsByAppID[selectedAppID] == nil,
                reason: "ensure_selected_cache"
            )
        }
    }

    private func setupWindowMonitorIfNeeded() {
        guard accessibilityTrusted else {
            windowChangeMonitor.stop()
            return
        }

        windowChangeMonitor.onAppWindowChanged = { appID in
            scheduleSingleAppRefresh(appID: appID, reason: "ax_window_changed")
        }
        windowChangeMonitor.rebind(appSummaries)
    }

    private func restoreCachedStateIfNeeded() {
        if appSummaries.isEmpty {
            appSummaries = Self.cachedAppSummaries
        }
        if windowsByAppID.isEmpty {
            windowsByAppID = Self.cachedWindowsByAppID
        }
        if selectedAppID == nil {
            selectedAppID = Self.cachedSelectedAppID
        }
        accessibilityTrusted = Self.cachedAccessibilityTrusted
        screenCaptureTrusted = Self.cachedScreenCaptureTrusted
        syncSelectedApp()
    }

    private func startPermissionWatcherIfNeeded() {
        guard permissionWatchTask == nil else { return }
        permissionWatchTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: permissionPollIntervalNs)
                guard !Task.isCancelled else { return }
                refreshPermissionsIfNeeded(reason: "permission_poll")
            }
        }
    }

    private func refreshPermissionsIfNeeded(reason: String) {
        let newAccessibilityTrusted = AXIsProcessTrusted()
        let newScreenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
        let permissionChanged =
            newAccessibilityTrusted != accessibilityTrusted || newScreenCaptureTrusted != screenCaptureTrusted

        accessibilityTrusted = newAccessibilityTrusted
        screenCaptureTrusted = newScreenCaptureTrusted

        if permissionChanged {
            scheduleAppSummariesRefresh(reason: "permission_changed_\(reason)")
            if !newAccessibilityTrusted {
                windowChangeMonitor.stop()
            }
        }
        persistCache()
    }

    private func scheduleRefreshIfRunningAppsChanged(reason: String) {
        if currentRunningAppSignature() != Self.cachedRunningAppSignature {
            scheduleAppSummariesRefresh(reason: "running_apps_changed_\(reason)")
        }
    }

    private func currentRunningAppSignature() -> Set<String> {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let includeCurrentProcessInAppLayer = AppVisibilityPreferencesStore.loadShowInCommandTab()
        return Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated else { return nil }
            guard includeCurrentProcessInAppLayer || app.processIdentifier != currentPID else { return nil }
            let appID = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            return "\(appID)#\(app.processIdentifier)"
        })
    }

    private func selectApp(_ appID: String) {
        selectedAppID = appID
        persistCache()
        scheduleSelectedAppRefresh(
            appID: appID,
            force: windowsByAppID[appID] == nil,
            reason: "manual_select"
        )
    }

    private func scheduleAppSummariesRefresh(reason: String) {
        appSummariesRefreshTask?.cancel()
        appSummariesRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: appRefreshDebounceDelayNs)
            await refreshAppSummaries(reason: reason)
            appSummariesRefreshTask = nil
        }
    }

    private func refreshAppSummaries(reason: String) async {
        let summaries = await fetchHomeAppSummariesOnBackground()
        guard !Task.isCancelled else { return }

        appSummaries = summaries
        let validAppIDs = Set(summaries.map(\.appID))
        windowsByAppID = windowsByAppID.filter { validAppIDs.contains($0.key) }
        syncSelectedApp()
        setupWindowMonitorIfNeeded()
        persistCache(updateRunningSignature: true)

        if let selectedAppID = currentSelectedAppID {
            let summaryCount = summaries.first(where: { $0.appID == selectedAppID })?.windowCount
            let cachedCount = windowsByAppID[selectedAppID]?.count
            scheduleSelectedAppRefresh(
                appID: selectedAppID,
                force: summaryCount == nil || cachedCount != summaryCount,
                reason: "selected_after_\(reason)"
            )
        }
    }

    private func scheduleSelectedAppRefresh(appID: String, force: Bool, reason: String) {
        guard force || windowsByAppID[appID] == nil else { return }
        selectedAppRefreshTask?.cancel()
        selectedAppRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: selectedAppRefreshDebounceDelayNs)
            await refreshSingleAppCache(
                appID: appID,
                updateWindows: true,
                reason: reason
            )
            selectedAppRefreshTask = nil
        }
    }

    private func scheduleSingleAppRefresh(appID: String, reason: String) {
        appRefreshTasksByID[appID]?.cancel()
        appRefreshTasksByID[appID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: appRefreshDebounceDelayNs)
            let shouldUpdateWindows = appID == currentSelectedAppID || windowsByAppID[appID] != nil
            await refreshSingleAppCache(
                appID: appID,
                updateWindows: shouldUpdateWindows,
                reason: reason
            )
            appRefreshTasksByID[appID] = nil
        }
    }

    private func refreshSingleAppCache(
        appID: String,
        updateWindows: Bool,
        reason _: String
    ) async {
        guard !Task.isCancelled else { return }
        if updateWindows {
            let snapshot = await fetchHomeAppSnapshotOnBackground(appID: appID)
            guard !Task.isCancelled else { return }

            guard let snapshot else {
                appSummaries.removeAll { $0.appID == appID }
                windowsByAppID.removeValue(forKey: appID)
                syncSelectedApp()
                setupWindowMonitorIfNeeded()
                persistCache()
                if let selectedAppID = currentSelectedAppID, windowsByAppID[selectedAppID] == nil {
                    scheduleSelectedAppRefresh(
                        appID: selectedAppID,
                        force: true,
                        reason: "selected_after_remove"
                    )
                }
                return
            }

            if let existingIndex = appSummaries.firstIndex(where: { $0.appID == appID }) {
                appSummaries[existingIndex] = snapshot.summary
            } else {
                appSummaries.append(snapshot.summary)
            }
            windowsByAppID[appID] = snapshot.candidate.windows
        } else {
            let summary = await fetchHomeAppSummaryOnBackground(appID: appID)
            guard !Task.isCancelled else { return }
            guard let summary else {
                appSummaries.removeAll { $0.appID == appID }
                windowsByAppID.removeValue(forKey: appID)
                syncSelectedApp()
                setupWindowMonitorIfNeeded()
                persistCache()
                return
            }
            if let existingIndex = appSummaries.firstIndex(where: { $0.appID == appID }) {
                appSummaries[existingIndex] = summary
            } else {
                appSummaries.append(summary)
            }
        }

        appSummaries.sort { lhs, rhs in
            if lhs.lastActiveAt == rhs.lastActiveAt {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.lastActiveAt > rhs.lastActiveAt
        }
        syncSelectedApp()
        setupWindowMonitorIfNeeded()
        persistCache()
    }

    private func fetchHomeAppSummariesOnBackground() async -> [RuntimeHomeAppSummary] {
        await withCheckedContinuation { continuation in
            Self.snapshotQueue.async {
                continuation.resume(returning: RuntimeSnapshotProvider().homeAppSummaries())
            }
        }
    }

    private func fetchHomeAppSummaryOnBackground(appID: String) async -> RuntimeHomeAppSummary? {
        await withCheckedContinuation { continuation in
            Self.snapshotQueue.async {
                continuation.resume(returning: RuntimeSnapshotProvider().homeAppSummary(for: appID))
            }
        }
    }

    private func fetchHomeAppSnapshotOnBackground(appID: String) async -> RuntimeHomeAppSnapshot? {
        await withCheckedContinuation { continuation in
            Self.snapshotQueue.async {
                continuation.resume(returning: RuntimeSnapshotProvider().homeAppSnapshot(for: appID))
            }
        }
    }

    private func syncSelectedApp() {
        guard !appSummaries.isEmpty else {
            selectedAppID = nil
            return
        }
        if let selectedAppID, appSummaries.contains(where: { $0.appID == selectedAppID }) {
            return
        }
        selectedAppID = appSummaries.first?.appID
    }

    private func persistCache(updateRunningSignature: Bool = false) {
        Self.cachedAccessibilityTrusted = accessibilityTrusted
        Self.cachedScreenCaptureTrusted = screenCaptureTrusted
        Self.cachedAppSummaries = appSummaries
        Self.cachedWindowsByAppID = windowsByAppID
        Self.cachedSelectedAppID = selectedAppID
        if updateRunningSignature {
            Self.cachedRunningAppSignature = currentRunningAppSignature()
        }
    }

    private func teardownActiveState() {
        appSummariesRefreshTask?.cancel()
        appSummariesRefreshTask = nil
        selectedAppRefreshTask?.cancel()
        selectedAppRefreshTask = nil
        for task in appRefreshTasksByID.values {
            task.cancel()
        }
        appRefreshTasksByID.removeAll()
        permissionWatchTask?.cancel()
        permissionWatchTask = nil
        windowChangeMonitor.stop()
        persistCache()
    }
}

@MainActor
private final class HomeWindowChangeMonitor {
    private final class ObserverContext {
        weak var monitor: HomeWindowChangeMonitor?
        let appID: String

        init(monitor: HomeWindowChangeMonitor, appID: String) {
            self.monitor = monitor
            self.appID = appID
        }
    }

    var onAppWindowChanged: ((String) -> Void)?

    private var observersByPID: [pid_t: AXObserver] = [:]
    private var observerContextByPID: [pid_t: ObserverContext] = [:]
    private var appIDByPID: [pid_t: String] = [:]
    private var lastEventAtByAppID: [String: TimeInterval] = [:]
    private let eventThrottleInterval: TimeInterval = 0.16
    private let watchedNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString
    ]

    func rebind(_ appSummaries: [RuntimeHomeAppSummary]) {
        guard AXIsProcessTrusted() else {
            stop()
            return
        }

        let expectedByPID = Dictionary(uniqueKeysWithValues: appSummaries.map { ($0.pid, $0.appID) })

        for pid in Array(observersByPID.keys) {
            guard let expectedAppID = expectedByPID[pid], expectedAppID == appIDByPID[pid] else {
                removeObserver(pid: pid)
                continue
            }
        }

        for (pid, appID) in expectedByPID where observersByPID[pid] == nil {
            installObserver(pid: pid, appID: appID)
        }
    }

    func stop() {
        for pid in Array(observersByPID.keys) {
            removeObserver(pid: pid)
        }
        lastEventAtByAppID.removeAll()
    }

    private func installObserver(pid: pid_t, appID: String) {
        var observerRef: AXObserver?
        let result = AXObserverCreate(pid, Self.callback, &observerRef)
        guard result == .success, let observerRef else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let context = ObserverContext(monitor: self, appID: appID)
        let contextPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        for notification in watchedNotifications {
            let addResult = AXObserverAddNotification(
                observerRef,
                appElement,
                notification,
                contextPointer
            )
            if addResult == .notificationUnsupported {
                continue
            }
            guard addResult == .success || addResult == .notificationAlreadyRegistered else { continue }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observerRef),
            .defaultMode
        )
        observersByPID[pid] = observerRef
        observerContextByPID[pid] = context
        appIDByPID[pid] = appID
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observersByPID.removeValue(forKey: pid) else { return }

        let appElement = AXUIElementCreateApplication(pid)
        for notification in watchedNotifications {
            AXObserverRemoveNotification(observer, appElement, notification)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observerContextByPID.removeValue(forKey: pid)
        appIDByPID.removeValue(forKey: pid)
    }

    private func emitWindowChanged(for appID: String) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastTimestamp = lastEventAtByAppID[appID], now - lastTimestamp < eventThrottleInterval {
            return
        }
        lastEventAtByAppID[appID] = now
        onAppWindowChanged?(appID)
    }

    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            context.monitor?.emitWindowChanged(for: context.appID)
        }
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
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.13, green: 0.13, blue: 0.15).opacity(0.96)
        }
        return Color(red: 0.965, green: 0.97, blue: 0.978)
    }

    private var cardBorderColor: Color {
        if colorScheme == .dark {
            return Color.primary.opacity(0.1)
        }
        return Color.black.opacity(0.14)
    }

    private var cardShadowColor: Color {
        if colorScheme == .dark {
            return .clear
        }
        return Color.black.opacity(0.05)
    }

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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackgroundColor)
                .shadow(color: cardShadowColor, radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }
}

private enum FlowActionButtonTone: Equatable {
    case grayDominant
    case blueDominant
}

private struct FlowActionButton: View {
    let title: String
    let systemImage: String?
    let tone: FlowActionButtonTone
    let width: CGFloat?
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        tone: FlowActionButtonTone = .grayDominant,
        width: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.width = width
        self.action = action
    }

    private var foregroundColor: Color {
        tone == .blueDominant ? .white : .primary.opacity(0.78)
    }

    private var backgroundFill: LinearGradient {
        switch tone {
        case .grayDominant:
            return LinearGradient(
                stops: [
                    .init(color: Color.primary.opacity(0.12), location: 0.0),
                    .init(color: Color.primary.opacity(0.09), location: 0.75),
                    .init(color: Color.accentColor.opacity(0.26), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .blueDominant:
            return LinearGradient(
                stops: [
                    .init(color: Color.accentColor.opacity(0.94), location: 0.0),
                    .init(color: Color.accentColor.opacity(0.76), location: 0.75),
                    .init(color: Color.primary.opacity(0.18), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var borderFill: LinearGradient {
        switch tone {
        case .grayDominant:
            return LinearGradient(
                stops: [
                    .init(color: Color.primary.opacity(0.24), location: 0.0),
                    .init(color: Color.primary.opacity(0.19), location: 0.75),
                    .init(color: Color.accentColor.opacity(0.36), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .blueDominant:
            return LinearGradient(
                stops: [
                    .init(color: Color.accentColor.opacity(0.55), location: 0.0),
                    .init(color: Color.accentColor.opacity(0.44), location: 0.75),
                    .init(color: Color.primary.opacity(0.28), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var shadowColor: Color {
        tone == .blueDominant ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.08)
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .frame(width: width)
            .foregroundStyle(foregroundColor)
            .background(
                Capsule()
                    .fill(backgroundFill)
            )
            .overlay(
                Capsule()
                    .stroke(borderFill, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
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

private struct AppLogsView: View {
    let isActive: Bool

    @AppStorage(AppPreferenceKeys.enableVerboseDiagnostics) private var enableVerboseDiagnostics = false
    @AppStorage(AppPreferenceKeys.runtimeLogLevel)
    private var runtimeLogLevelRaw = RuntimeLogPreferencesStore.defaultLevel.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue

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

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("日志")
                            .font(.system(size: 22, weight: .semibold))
                        Text("运行日志查看与清理")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if isActive {
                        RuntimeLogsSection(
                            enableVerboseDiagnostics: $enableVerboseDiagnostics,
                            runtimeLogLevelRaw: $runtimeLogLevelRaw,
                            hotkeyShortcutText: hotkeyConfiguration.mainShortcutText
                        )
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("flowtab.tab.logs.content")
    }
}

private struct AppSettingsView: View {
    let isActive: Bool

    @AppStorage(AppPreferenceKeys.showShortcutHint) private var showShortcutHint = true
    @AppStorage(AppPreferenceKeys.showInCommandTab)
    private var showInCommandTab = AppVisibilityPreferencesStore.defaultShowInCommandTab
    @AppStorage(AppPreferenceKeys.showPermissionReminder) private var showPermissionReminder = true
    @AppStorage(AppPreferenceKeys.themeMode) private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue
    @AppStorage(AppPreferenceKeys.autoRestoreMinimizedWindowOnSwitch)
    private var autoRestoreMinimizedWindowOnSwitch =
        SwitcherBehaviorPreferencesStore.defaultAutoRestoreMinimizedWindowOnSwitch
    @AppStorage(AppPreferenceKeys.hideMinimizedAppsFromAppLayer)
    private var hideMinimizedAppsFromAppLayer =
        SwitcherBehaviorPreferencesStore.defaultHideMinimizedAppsFromAppLayer
    @AppStorage(AppPreferenceKeys.searchEnabled)
    private var searchEnabled = SearchInteractionPreferencesStore.defaultIsEnabled
    @AppStorage(AppPreferenceKeys.searchDefaultScope)
    private var searchDefaultScopeRaw = SearchInteractionPreferencesStore.defaultScope.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
    @AppStorage(CommandTabTakeoverController.takeoverMarkerKey)
    private var commandTabTakeoverActive = false
    @AppStorage(AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier)
    private var inAppWindowHotkeyPrimaryModifierRaw =
        InAppWindowHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.inAppWindowHotkeyMainKey)
    private var inAppWindowHotkeyMainKeyRaw = InAppWindowHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.windowLayerAutoEnterDelay)
    private var windowLayerAutoEnterDelayRaw = WindowLayerPreferencesStore.defaultAutoEnterDelay
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var accessibilityPermissionPollTask: Task<Void, Never>?
    @State private var screenCapturePollTask: Task<Void, Never>?
    @State private var windowLayerAutoEnterDelayText = ""
    @State private var didInitialize = false
    @FocusState private var isWindowLayerDelayFieldFocused: Bool
    private let permissionRequestButtonWidth: CGFloat = 166

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

    private var inAppWindowHotkeyConfiguration: SwitcherHotkeyConfiguration {
        let resolved = InAppWindowHotkeyPreferencesStore.resolve(
            primaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw,
            mainKeyRaw: inAppWindowHotkeyMainKeyRaw
        )
        return SwitcherHotkeyConfiguration(
            primaryModifier: resolved.primaryModifier,
            mainKey: resolved.mainKey,
            quitKey: .q
        )
    }

    private var inAppWindowPrimaryModifierOptions: [SwitcherPrimaryModifier] {
        SwitcherPrimaryModifier.allCases
    }

    private var mainUsesCommandTab: Bool {
        hotkeyConfiguration.primaryModifier == .command && hotkeyConfiguration.mainKey == .tab
    }

    private var inAppUsesCommandTab: Bool {
        inAppWindowHotkeyConfiguration.primaryModifier == .command
            && inAppWindowHotkeyConfiguration.mainKey == .tab
    }

    private var commandTabTakeoverStatusText: String {
        commandTabTakeoverActive
            ? "已接管系统 Command + Tab / Command + Shift + Tab，退出 FlowTab 后会自动恢复。"
            : "检测到 Command + Tab 组合：FlowTab 会自动尝试接管系统 Command + Tab / Command + Shift + Tab。"
    }

    @ViewBuilder
    private var commandTabTakeoverStatusView: some View {
        Text(commandTabTakeoverStatusText)
            .font(.system(size: 12))
            .foregroundStyle(commandTabTakeoverActive ? .green : .red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var windowLayerAutoEnterDelay: Double {
        WindowLayerPreferencesStore.normalizedAutoEnterDelay(windowLayerAutoEnterDelayRaw)
    }

    private var themeModeCapsuleSelector: some View {
        HStack(spacing: 4) {
            ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                let isSelected = themeModeRaw == mode.rawValue
                Button {
                    themeModeRaw = mode.rawValue
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
            }
        }
        .padding(2)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var settingsColumns: some View {
        HStack(alignment: .top, spacing: 12) {
            settingsLeftColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
            settingsRightColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var settingsLeftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            appearanceSettingsCard
            windowBehaviorSettingsCard
            permissionSettingsCard
        }
    }

    private var settingsRightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchSettingsCard
            hotkeySettingsCard
        }
    }

    @ViewBuilder
    private func settingsControlRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingsToggleRow(
        _ title: String,
        isOn: Binding<Bool>
    ) -> some View {
        settingsControlRow(title) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var appearanceSettingsCard: some View {
        HomeSectionCard(title: "外观", subtitle: "显示与主题") {
            VStack(alignment: .leading, spacing: 10) {
                settingsToggleRow("显示快捷键提示", isOn: $showShortcutHint)

                settingsToggleRow("显示应用窗口", isOn: $showInCommandTab)

                Text("关闭后 当前应用 将仅作为菜单栏辅助应用运行。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                settingsControlRow("主题模式") {
                    themeModeCapsuleSelector
                }
            }
        }
    }

    private var windowBehaviorSettingsCard: some View {
        HomeSectionCard(title: "窗口行为", subtitle: "窗口层进入与最小化处理") {
            VStack(alignment: .leading, spacing: 10) {
                settingsControlRow("窗口层自动进入延迟") {
                    HStack(spacing: 8) {
                        TextField("0.35", text: $windowLayerAutoEnterDelayText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($isWindowLayerDelayFieldFocused)
                            .onChange(of: windowLayerAutoEnterDelayText) { _, newValue in
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

                settingsToggleRow("切换到最小化窗口时自动恢复打开", isOn: $autoRestoreMinimizedWindowOnSwitch)

                settingsToggleRow("应用层隐藏仅最小化应用", isOn: $hideMinimizedAppsFromAppLayer)

                Text("说明：该过滤依赖辅助功能权限。未授权时无法判断最小化状态，不会过滤应用层。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hotkeySettingsCard: some View {
        HomeSectionCard(title: "快捷键", subtitle: "主切换与结束应用按键") {
            VStack(alignment: .leading, spacing: 10) {
                settingsControlRow("主修饰键") {
                    Picker("主修饰键", selection: $hotkeyPrimaryModifierRaw) {
                        ForEach(SwitcherPrimaryModifier.allCases) { modifier in
                            Text(modifier.displayName).tag(modifier.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }

                settingsControlRow("主切换按键") {
                    Picker("主切换按键", selection: $hotkeyMainKeyRaw) {
                        ForEach(SwitcherHotkeyKey.allCases) { key in
                            Text(key.displayName).tag(key.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }

                settingsControlRow("结束应用按键") {
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

                if mainUsesCommandTab {
                    commandTabTakeoverStatusView
                }

                Divider()
                    .padding(.vertical, 4)

                Group {
                    settingsControlRow("应用内窗口修饰键") {
                        Picker("应用内窗口修饰键", selection: $inAppWindowHotkeyPrimaryModifierRaw) {
                            ForEach(inAppWindowPrimaryModifierOptions) { modifier in
                                Text(modifier.displayName).tag(modifier.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160)
                    }

                    settingsControlRow("应用内窗口按键") {
                        Picker("应用内窗口按键", selection: $inAppWindowHotkeyMainKeyRaw) {
                            ForEach(SwitcherHotkeyKey.allCases) { key in
                                Text(key.displayName).tag(key.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160)
                    }
                }
                .disabled(!accessibilityTrusted)

                Text(
                    "应用内窗口：\(inAppWindowHotkeyConfiguration.mainShortcutText)"
                        + "（反向：\(inAppWindowHotkeyConfiguration.backwardShortcutText)）"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                if inAppUsesCommandTab {
                    commandTabTakeoverStatusView
                }
            }
        }
    }

    private var searchSettingsCard: some View {
        HomeSectionCard(title: "搜索", subtitle: "搜索开关、范围与交互说明") {
            VStack(alignment: .leading, spacing: 10) {
                settingsToggleRow("启用搜索功能", isOn: $searchEnabled)

                settingsControlRow("默认搜索范围") {
                    Picker("默认搜索范围", selection: $searchDefaultScopeRaw) {
                        ForEach(SwitcherSearchScope.allCases, id: \.rawValue) { scope in
                            Text(scope.label).tag(scope.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                .disabled(!searchEnabled)
                .opacity(searchEnabled ? 1 : 0.5)

                Text(searchEnabled ? "面板默认从应用层开始；按 Enter 或 ↑ 进入搜索。" : "已关闭搜索：面板仅显示应用层与窗口层。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionSettingsCard: some View {
        HomeSectionCard(title: "权限", subtitle: "辅助功能与屏幕录制") {
            VStack(alignment: .leading, spacing: 10) {
                settingsToggleRow("无权限时是否在在首页提示获取权限", isOn: $showPermissionReminder)

                permissionStatusActionRow(
                    text: accessibilityTrusted ? "辅助功能权限：已授权" : "辅助功能权限：未授权",
                    detail: "用于应用切换、应用内窗口切换和最小化窗口处理。",
                    isGranted: accessibilityTrusted
                ) {
                    requestAccessibilityPermissionButton
                }

                permissionStatusActionRow(
                    text: screenCaptureTrusted ? "屏幕录制权限：已授权" : "屏幕录制权限：未授权",
                    detail: "用于显示窗口真实预览画面；未授权时仅显示兜底信息。",
                    isGranted: screenCaptureTrusted
                ) {
                    requestScreenCapturePermissionButton
                }
            }
        }
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("设置")
                            .font(.system(size: 22, weight: .semibold))
                        Text("基础显示设置、快捷键与权限")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    settingsColumns
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            handleVisibilityChanged(isActive)
        }
        .onChange(of: isActive) { _, active in
            handleVisibilityChanged(active)
        }
        .onChange(of: themeModeRaw) {
            enforceThemeModeConsistency()
        }
        .onChange(of: showInCommandTab) {
            notifyAppVisibilityPreferenceChanged()
        }
        .onChange(of: hotkeyPrimaryModifierRaw) {
            enforceHotkeyConsistency()
            enforceInAppWindowHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: hotkeyMainKeyRaw) {
            enforceHotkeyConsistency()
            enforceInAppWindowHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: hotkeyQuitKeyRaw) {
            enforceHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: inAppWindowHotkeyPrimaryModifierRaw) {
            enforceInAppWindowHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: inAppWindowHotkeyMainKeyRaw) {
            enforceInAppWindowHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: isWindowLayerDelayFieldFocused) { _, isFocused in
            guard !isFocused else { return }
            commitWindowLayerAutoEnterDelayText()
        }
        .onChange(of: windowLayerAutoEnterDelayRaw) {
            enforceWindowLayerPreferencesConsistency()
            if !isWindowLayerDelayFieldFocused {
                syncWindowLayerAutoEnterDelayText()
            }
        }
        .onChange(of: searchDefaultScopeRaw) {
            enforceSearchPreferencesConsistency()
        }
        .onDisappear {
            cancelPermissionPolling()
        }
        .accessibilityIdentifier("flowtab.tab.settings.content")
    }

    private func handleVisibilityChanged(_ active: Bool) {
        guard active else {
            cancelPermissionPolling()
            return
        }
        if !didInitialize {
            enforceThemeModeConsistency()
            enforceHotkeyConsistency()
            enforceInAppWindowHotkeyConsistency()
            enforceWindowLayerPreferencesConsistency()
            enforceSearchPreferencesConsistency()
            syncWindowLayerAutoEnterDelayText()
            didInitialize = true
        }
        refreshAccessibilityStatus()
        refreshScreenCaptureStatus()
    }

    private func cancelPermissionPolling() {
        accessibilityPermissionPollTask?.cancel()
        accessibilityPermissionPollTask = nil
        screenCapturePollTask?.cancel()
        screenCapturePollTask = nil
    }

    private var requestAccessibilityPermissionButton: some View {
        let isGranted = accessibilityTrusted
        return FlowActionButton(
            title: isGranted ? "关闭辅助功能权限" : "请求辅助功能权限",
            systemImage: nil,
            tone: isGranted ? .blueDominant : .grayDominant,
            width: permissionRequestButtonWidth
        ) {
            if isGranted {
                openAccessibilityPrivacySettings()
            } else {
                requestAccessibilityPermission()
            }
        }
    }

    private var requestScreenCapturePermissionButton: some View {
        let isGranted = screenCaptureTrusted
        return FlowActionButton(
            title: isGranted ? "关闭屏幕录制权限" : "请求屏幕录制权限",
            systemImage: "display.badge.person.crop",
            tone: isGranted ? .blueDominant : .grayDominant,
            width: permissionRequestButtonWidth
        ) {
            if isGranted {
                openScreenCapturePrivacySettings()
            } else {
                requestScreenCapturePermission()
            }
        }
    }

    private func requestAccessibilityPermission() {
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

    private func requestScreenCapturePermission() {
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

    private func openAccessibilityPrivacySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    private func openScreenCapturePrivacySettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    private func openPrivacySettings(anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for rawURL in candidates {
            if let url = URL(string: rawURL), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @ViewBuilder
    private func permissionStatusActionRow<Button: View>(
        text: String,
        detail: String,
        isGranted: Bool,
        @ViewBuilder actionButton: () -> Button
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isGranted ? .green : .orange)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            actionButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    private func refreshScreenCaptureStatus() {
        screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    }

    private func enforceHotkeyConsistency() {
        let resolved = hotkeyConfiguration
        if hotkeyPrimaryModifierRaw != resolved.primaryModifier.rawValue {
            hotkeyPrimaryModifierRaw = resolved.primaryModifier.rawValue
        }
        if hotkeyMainKeyRaw != resolved.mainKey.rawValue {
            hotkeyMainKeyRaw = resolved.mainKey.rawValue
        }
        if hotkeyQuitKeyRaw != resolved.quitKey.rawValue {
            hotkeyQuitKeyRaw = resolved.quitKey.rawValue
        }
    }

    private func enforceInAppWindowHotkeyConsistency() {
        let resolved = InAppWindowHotkeyPreferencesStore.resolve(
            primaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw,
            mainKeyRaw: inAppWindowHotkeyMainKeyRaw
        )
        if inAppWindowHotkeyPrimaryModifierRaw != resolved.primaryModifier.rawValue {
            inAppWindowHotkeyPrimaryModifierRaw = resolved.primaryModifier.rawValue
        }
        if inAppWindowHotkeyMainKeyRaw != resolved.mainKey.rawValue {
            inAppWindowHotkeyMainKeyRaw = resolved.mainKey.rawValue
        }
    }

    private func enforceThemeModeConsistency() {
        let resolved = ThemePreferencesStore.resolve(rawValue: themeModeRaw)
        if themeModeRaw != resolved.rawValue {
            themeModeRaw = resolved.rawValue
        }
    }

    private func enforceSearchPreferencesConsistency() {
        let resolved = SearchInteractionPreferencesStore.loadDefaultScope()
        if searchDefaultScopeRaw != resolved.rawValue {
            searchDefaultScopeRaw = resolved.rawValue
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
            "updated main=\(hotkeyConfiguration.mainShortcutText) backward=\(hotkeyConfiguration.backwardShortcutText) quit=\(hotkeyConfiguration.quitShortcutText) inApp=\(inAppWindowHotkeyConfiguration.mainShortcutText) inAppBackward=\(inAppWindowHotkeyConfiguration.backwardShortcutText)"
        )
        NotificationCenter.default.post(name: .flowTabReRegisterHotkeys, object: nil)
    }

    private func notifyAppVisibilityPreferenceChanged() {
        RuntimeLog.info(
            "App",
            "showInCommandTab=\(showInCommandTab)"
        )
        NotificationCenter.default.post(name: .flowTabAppVisibilityPreferenceChanged, object: nil)
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
private final class RuntimeLogLinesViewModel: ObservableObject {
    @Published private(set) var lines: [String] = []

    private static var persistedClearSnapshot: RuntimeLogFileStore.ReadSnapshot?

    private let lineLimit = 300
    private let refreshIntervalNs: UInt64 = 1_000_000_000
    private var refreshTask: Task<Void, Never>?

    private var clearSnapshot: RuntimeLogFileStore.ReadSnapshot? {
        get { Self.persistedClearSnapshot }
        set { Self.persistedClearSnapshot = newValue }
    }

    func start(minimumLevel: RuntimeLogLevel) {
        stop()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.reload(minimumLevel: minimumLevel)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshIntervalNs)
                await self.reload(minimumLevel: minimumLevel)
            }
        }
    }

    func clearDisplayedOutput(minimumLevel: RuntimeLogLevel) {
        stop()
        lines = []
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await RuntimeDiagnostics.shared.makeReadSnapshot()
            guard !Task.isCancelled else { return }
            self.clearSnapshot = snapshot
            await self.reload(minimumLevel: minimumLevel)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshIntervalNs)
                await self.reload(minimumLevel: minimumLevel)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit {
        refreshTask?.cancel()
    }

    private func reload(minimumLevel: RuntimeLogLevel) async {
        let nextLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: lineLimit,
            minimumLevel: minimumLevel,
            since: clearSnapshot
        )
        guard !Task.isCancelled else { return }
        lines = nextLines
    }
}

private struct RuntimeLogsSection: View {
    @Binding var enableVerboseDiagnostics: Bool
    @Binding var runtimeLogLevelRaw: String
    let hotkeyShortcutText: String

    @StateObject private var logsViewModel = RuntimeLogLinesViewModel()

    private var selectedLogLevel: RuntimeLogLevel {
        RuntimeLogPreferencesStore.resolve(rawValue: runtimeLogLevelRaw)
    }

    private func synchronizeLogLevelIfNeeded() {
        let resolved = RuntimeLogPreferencesStore.resolve(rawValue: runtimeLogLevelRaw)
        if resolved.rawValue != runtimeLogLevelRaw {
            runtimeLogLevelRaw = resolved.rawValue
        }
    }

    private func openLogsDirectory() {
        let logsURL = URL(fileURLWithPath: RuntimeDiagnostics.logsDirectoryPath, isDirectory: true)
        _ = NSWorkspace.shared.open(logsURL)
    }

    private var logsActionButtonTint: Color {
        Color(.sRGB, red: 58 / 255, green: 128 / 255, blue: 247 / 255, opacity: 1)
    }

    private struct LogsActionButtonStyle: ButtonStyle {
        let tint: Color

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.85 : 1))
                )
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    var body: some View {
        HomeSectionCard(title: "日志", subtitle: "仅日志相关信息") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用详细运行日志（高频，可能影响性能）", isOn: $enableVerboseDiagnostics)
                    .toggleStyle(.switch)
                    .font(.system(size: 12))

                HStack(spacing: 10) {
                    Text("日志等级")
                        .font(.system(size: 12))
                    Picker("日志等级", selection: $runtimeLogLevelRaw) {
                        ForEach(RuntimeLogLevel.allCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                Text("本地日志目录：\(RuntimeDiagnostics.logsDirectoryPath)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button("打开目录") {
                        openLogsDirectory()
                    }
                    .buttonStyle(LogsActionButtonStyle(tint: logsActionButtonTint))

                    Button("清空日志") {
                        logsViewModel.clearDisplayedOutput(minimumLevel: selectedLogLevel)
                    }
                    .buttonStyle(LogsActionButtonStyle(tint: logsActionButtonTint))
                }

                ScrollView {
                    Group {
                        if logsViewModel.lines.isEmpty {
                            Text("暂无日志。触发 \(hotkeyShortcutText) 后再回来看。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(logsViewModel.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 320, maxHeight: 440)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
        .onAppear {
            synchronizeLogLevelIfNeeded()
            logsViewModel.start(minimumLevel: selectedLogLevel)
        }
        .onChange(of: runtimeLogLevelRaw) { _, newValue in
            let resolved = RuntimeLogPreferencesStore.resolve(rawValue: newValue)
            if newValue != resolved.rawValue {
                runtimeLogLevelRaw = resolved.rawValue
                return
            }
            logsViewModel.start(minimumLevel: resolved)
        }
        .onDisappear {
            logsViewModel.stop()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: SwitcherPanelController?
    private var hotkeyMonitor: OptionTabHotkeyMonitor?
    private var inAppWindowHotkeyMonitor: OptionTabHotkeyMonitor?
    private let commandTabTakeoverController = CommandTabTakeoverController()
    private var statusItem: NSStatusItem?
    private var hotkeyObserver: NSObjectProtocol?
    private var appVisibilityObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicyFromPreferences()

        let panelController = SwitcherPanelController()
        self.panelController = panelController

        setupHotkeyMonitor()
        setupInAppWindowHotkeyMonitor()
        installHotkeyObserver()
        installAppVisibilityObserver()

        installStatusItem()
        requestAccessibilityPermissionIfNeeded()
        AppWindowCoordinator.openHome()
        TabSwitchStressRunner.shared.startIfNeeded()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        let userDefaults = UserDefaults.standard
        let shouldPromptPermissionReminder = userDefaults.object(forKey: AppPreferenceKeys.showPermissionReminder) == nil
            ? true
            : userDefaults.bool(forKey: AppPreferenceKeys.showPermissionReminder)
        guard shouldPromptPermissionReminder else { return }
        guard !AXIsProcessTrusted() else { return }
        guard !userDefaults.bool(forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission)
        else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        userDefaults.set(true, forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
            self.hotkeyObserver = nil
        }
        if let appVisibilityObserver {
            NotificationCenter.default.removeObserver(appVisibilityObserver)
            self.appVisibilityObserver = nil
        }
        hotkeyMonitor?.stop()
        inAppWindowHotkeyMonitor?.stop()
        commandTabTakeoverController.restoreSystemShortcutsIfNeeded()
    }

    private func setupHotkeyMonitor() {
        hotkeyMonitor?.stop()

        var hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()
        let inAppHotkeyConfiguration = InAppWindowHotkeyPreferencesStore.load()
        let mainUsesCommandTab =
            hotkeyConfiguration.primaryModifier == .command && hotkeyConfiguration.mainKey == .tab
        let inAppUsesCommandTab =
            inAppHotkeyConfiguration.primaryModifier == .command && inAppHotkeyConfiguration.mainKey == .tab
        let takeoverReady = commandTabTakeoverController.reconcileIfNeeded(
            shouldTakeOver: mainUsesCommandTab || inAppUsesCommandTab
        )
        if mainUsesCommandTab, !takeoverReady {
            hotkeyConfiguration = SwitcherHotkeyConfiguration(
                primaryModifier: .option,
                mainKey: hotkeyConfiguration.mainKey,
                quitKey: hotkeyConfiguration.quitKey
            )
            RuntimeLog.info("HotKey", "fallback to Option+Tab because Command+Tab takeover failed")
        }

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

        let mainConfiguration = SwitcherHotkeyPreferencesStore.load()
        let inAppConfiguration = InAppWindowHotkeyPreferencesStore.load()
        if
            mainConfiguration.primaryModifier == inAppConfiguration.primaryModifier
                && mainConfiguration.mainKey == inAppConfiguration.mainKey
        {
            RuntimeLog.info("HotKey", "skip register in-app window hotkey due conflict with main shortcut")
            inAppWindowHotkeyMonitor = nil
            return
        }

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

    private func installAppVisibilityObserver() {
        if let appVisibilityObserver {
            NotificationCenter.default.removeObserver(appVisibilityObserver)
        }
        appVisibilityObserver = NotificationCenter.default.addObserver(
            forName: .flowTabAppVisibilityPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyActivationPolicyFromPreferences()
            }
        }
    }

    private func applyActivationPolicyFromPreferences() {
        let showInCommandTab = AppVisibilityPreferencesStore.loadShowInCommandTab()
        let targetPolicy: NSApplication.ActivationPolicy = showInCommandTab ? .regular : .accessory
        guard NSApp.activationPolicy() != targetPolicy else { return }

        NSApp.setActivationPolicy(targetPolicy)
        RuntimeLog.info(
            "App",
            "activationPolicy=\(showInCommandTab ? "regular" : "accessory")"
        )
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

final class RuntimeDiagnostics {
    static let shared = RuntimeDiagnostics()
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private let fileStore = RuntimeLogFileStore.shared

    private init() {}

    static func formattedTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static var logsDirectoryPath: String {
        RuntimeLogFileStore.shared.logsDirectoryPath
    }

    func log(level: RuntimeLogLevel, category: String, message: String) {
        let timestamp = Date()
        let displayLine = "[\(Self.formattedTimestamp(timestamp))] [\(level.rawValue)] [\(category)] \(message)"
        fileStore.append(displayLine)
    }

    func makeReadSnapshot() async -> RuntimeLogFileStore.ReadSnapshot {
        await fileStore.makeReadSnapshot()
    }

    func readRecentLines(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: RuntimeLogFileStore.ReadSnapshot? = nil
    ) async -> [String] {
        await fileStore.readRecentLines(limit: limit, minimumLevel: minimumLevel, since: snapshot)
    }

    func clear() {
        fileStore.clear()
    }
}

final class RuntimeLogFileStore {
    static let shared = RuntimeLogFileStore()

    struct ReadSnapshot {
        let fileSizesByPath: [String: Int]
    }

    private static let fileNameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
    private static let logFilePrefix: String = {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        let rawName = (displayName?.isEmpty == false ? displayName : bundleName) ?? "FlowTabApp"
        let sanitized = rawName
            .replacingOccurrences(
                of: #"[^A-Za-z0-9_-]"#,
                with: "_",
                options: .regularExpression
            )
        return "\(sanitized)_"
    }()
    private static let logFileExtension = ".log"

    private let queue = DispatchQueue(label: "FlowTab.RuntimeLogFileStore", qos: .utility)
    private let fileManager = FileManager.default
    private let maxFileSizeBytes = 1_000_000
    private let maxLogFiles = 5
    private let flushDelay: TimeInterval = 0.05
    private let immediateFlushThreshold = 120
    private let logsDirectoryURL: URL
    private var activeLogURL: URL?
    private var pendingLines: [String] = []
    private var flushWorkItem: DispatchWorkItem?

    var logsDirectoryPath: String {
        logsDirectoryURL.path
    }

    private init() {
        let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallbackURL
        logsDirectoryURL = baseURL.appendingPathComponent("FlowTabApp/logs", isDirectory: true)
        activeLogURL = nil
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

    func makeReadSnapshot() async -> ReadSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.flushLocked()
                continuation.resume(returning: self.makeReadSnapshotLocked())
            }
        }
    }

    func readRecentLines(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: ReadSnapshot? = nil
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async {
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.flushLocked()
                let lines: [String]
                if let snapshot {
                    lines = self.readRecentLinesSinceSnapshotLocked(
                        limit: limit,
                        minimumLevel: minimumLevel,
                        snapshot: snapshot
                    )
                } else {
                    lines = self.readRecentLinesLocked(limit: limit, minimumLevel: minimumLevel)
                }
                continuation.resume(returning: lines)
            }
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
            let targetLogURL = try targetLogURLLocked(appendingByteCount: block.utf8.count)
            try appendToFileLocked(block, to: targetLogURL)
            try enforceMaxLogFilesLocked()
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

    private func appendToFileLocked(_ block: String, to url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try block.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(block.utf8))
    }

    private func targetLogURLLocked(appendingByteCount: Int) throws -> URL {
        let currentURL = try ensureActiveLogFileLocked()
        let currentSize = fileSizeLocked(for: currentURL)
        if currentSize + appendingByteCount <= maxFileSizeBytes {
            return currentURL
        }
        return try createNewActiveLogFileLocked()
    }

    private func ensureActiveLogFileLocked() throws -> URL {
        if let activeLogURL, fileManager.fileExists(atPath: activeLogURL.path) {
            return activeLogURL
        }
        return try createNewActiveLogFileLocked()
    }

    private func createNewActiveLogFileLocked() throws -> URL {
        let timestamp = Self.fileNameTimestampFormatter.string(from: Date())
        var candidateName = "\(Self.logFilePrefix)\(timestamp)\(Self.logFileExtension)"
        var candidateURL = logsDirectoryURL.appendingPathComponent(candidateName, isDirectory: false)
        var suffix = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateName = "\(Self.logFilePrefix)\(timestamp)-\(suffix)\(Self.logFileExtension)"
            candidateURL = logsDirectoryURL.appendingPathComponent(candidateName, isDirectory: false)
            suffix += 1
        }

        try Data().write(to: candidateURL)
        activeLogURL = candidateURL
        return candidateURL
    }

    private func enforceMaxLogFilesLocked() throws {
        let fileURLs = orderedLogFileURLsOldestFirstLocked()
        var existingCount = fileURLs.count
        guard existingCount > maxLogFiles else { return }

        for url in fileURLs {
            if existingCount <= maxLogFiles {
                break
            }
            if url == activeLogURL {
                continue
            }
            try fileManager.removeItem(at: url)
            existingCount -= 1
        }
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
        for logURL in allManagedLogFileURLsLocked() {
            if fileManager.fileExists(atPath: logURL.path) {
                try? fileManager.removeItem(at: logURL)
            }
        }
        activeLogURL = nil
    }

    private func makeReadSnapshotLocked() -> ReadSnapshot {
        var fileSizesByPath: [String: Int] = [:]
        for url in allManagedLogFileURLsLocked() {
            fileSizesByPath[url.path] = fileSizeLocked(for: url)
        }
        return ReadSnapshot(fileSizesByPath: fileSizesByPath)
    }

    private func allManagedLogFileURLsLocked() -> [URL] {
        guard fileManager.fileExists(atPath: logsDirectoryURL.path) else { return [] }
        guard let urls = try? fileManager.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter { isManagedLogFileNameLocked($0.lastPathComponent) }
    }

    private func isManagedLogFileNameLocked(_ fileName: String) -> Bool {
        fileName.hasPrefix(Self.logFilePrefix) && fileName.hasSuffix(Self.logFileExtension)
    }

    private func orderedLogFileURLsOldestFirstLocked() -> [URL] {
        Array(orderedLogFileURLsNewestFirstLocked().reversed())
    }

    private func readRecentLinesLocked(limit: Int, minimumLevel: RuntimeLogLevel) -> [String] {
        guard limit > 0 else { return [] }

        var recentLinesNewestFirst: [String] = []
        let targetCount = limit * 2
        let tailBytesPerFile = min(maxFileSizeBytes, max(64_000, limit * 1_024))

        for url in orderedLogFileURLsNewestFirstLocked() {
            let fileTailLines = readTailLinesLocked(from: url, maximumBytes: tailBytesPerFile)
            guard !fileTailLines.isEmpty else { continue }

            for line in fileTailLines.reversed() {
                if parsedLogLevelLocked(from: line) >= minimumLevel {
                    recentLinesNewestFirst.append(line)
                }
                if recentLinesNewestFirst.count >= targetCount {
                    break
                }
            }

            if recentLinesNewestFirst.count >= targetCount {
                break
            }
        }

        let limitedNewestFirst = Array(recentLinesNewestFirst.prefix(limit))
        return Array(limitedNewestFirst.reversed())
    }

    private func readRecentLinesSinceSnapshotLocked(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        snapshot: ReadSnapshot
    ) -> [String] {
        guard limit > 0 else { return [] }

        var recentLinesNewestFirst: [String] = []
        let targetCount = limit * 2
        let tailBytesPerFile = min(maxFileSizeBytes, max(64_000, limit * 1_024))

        for url in orderedLogFileURLsNewestFirstLocked() {
            let currentSize = fileSizeLocked(for: url)
            guard currentSize > 0 else { continue }

            let originalStartOffset = min(snapshot.fileSizesByPath[url.path] ?? 0, currentSize)
            guard originalStartOffset < currentSize else { continue }

            let boundedStartOffset = max(originalStartOffset, currentSize - tailBytesPerFile)
            let shouldDropLeadingPartialLine = boundedStartOffset > originalStartOffset
            let appendedLines = readLinesLocked(
                from: url,
                startOffset: boundedStartOffset,
                dropLeadingPartialLine: shouldDropLeadingPartialLine
            )
            guard !appendedLines.isEmpty else { continue }

            for line in appendedLines.reversed() {
                if parsedLogLevelLocked(from: line) >= minimumLevel {
                    recentLinesNewestFirst.append(line)
                }
                if recentLinesNewestFirst.count >= targetCount {
                    break
                }
            }

            if recentLinesNewestFirst.count >= targetCount {
                break
            }
        }

        let limitedNewestFirst = Array(recentLinesNewestFirst.prefix(limit))
        return Array(limitedNewestFirst.reversed())
    }

    private func orderedLogFileURLsNewestFirstLocked() -> [URL] {
        allManagedLogFileURLsLocked().sorted { leftURL, rightURL in
            let leftDate = modifiedDateLocked(for: leftURL) ?? Date.distantPast
            let rightDate = modifiedDateLocked(for: rightURL) ?? Date.distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return leftURL.lastPathComponent > rightURL.lastPathComponent
        }
    }

    private func modifiedDateLocked(for url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) else {
            return nil
        }
        return values.contentModificationDate ?? values.creationDate
    }

    private func readTailLinesLocked(from url: URL, maximumBytes: Int) -> [String] {
        guard maximumBytes > 0 else { return [] }
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let sizeValue = attributes[.size] as? NSNumber
        else {
            return []
        }

        let fileSize = sizeValue.intValue
        guard fileSize > 0 else { return [] }

        let readSize = min(fileSize, maximumBytes)
        let offset = max(0, fileSize - readSize)

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.readToEnd(), !data.isEmpty else {
                return []
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return []
            }

            var lines = text
                .split(whereSeparator: \.isNewline)
                .map(String.init)

            if offset > 0, !lines.isEmpty {
                lines.removeFirst()
            }
            return lines
        } catch {
            return []
        }
    }

    private func readLinesLocked(from url: URL, startOffset: Int, dropLeadingPartialLine: Bool) -> [String] {
        guard startOffset >= 0 else { return [] }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(startOffset))
            guard let data = try handle.readToEnd(), !data.isEmpty else {
                return []
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return []
            }

            var lines = text
                .split(whereSeparator: \.isNewline)
                .map(String.init)

            if dropLeadingPartialLine, !lines.isEmpty {
                lines.removeFirst()
            }

            return lines
        } catch {
            return []
        }
    }

    private func parsedLogLevelLocked(from line: String) -> RuntimeLogLevel {
        let segments = line.split(separator: "]", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return .info }
        let levelToken = segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard levelToken.hasPrefix("[") else { return .info }
        let rawValue = String(levelToken.dropFirst())
        return RuntimeLogLevel(rawValue: rawValue) ?? .info
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

    private static var minimumLevel: RuntimeLogLevel {
        RuntimeLogPreferencesStore.loadMinimumLevel()
    }

    private static func shouldRecord(level: RuntimeLogLevel, category: String) -> Bool {
        guard level >= minimumLevel else { return false }
        if noisyCategories.contains(category), !isVerboseEnabled {
            return level >= .warning
        }
        return true
    }

    private static func emit(
        level: RuntimeLogLevel,
        category: String,
        message: @autoclosure () -> String
    ) {
        guard shouldRecord(level: level, category: category) else { return }
        RuntimeDiagnostics.shared.log(level: level, category: category, message: message())
    }

    static func info(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .info, category: category, message: message())
    }

    static func warning(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .warning, category: category, message: message())
    }

    static func error(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .error, category: category, message: message())
    }
}
