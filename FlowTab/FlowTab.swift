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
    static let appLanguage = "appLanguage"
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
    static let flowTabLanguagePreferenceChanged = Notification.Name(
        "FlowTab.LanguagePreferenceChanged"
    )
}

protocol AppWindowOpeningWindow: AnyObject {
    var isPanelWindow: Bool { get }
    var isMiniaturized: Bool { get }

    func deminiaturize(_ sender: Any?)
    func makeKeyAndOrderFront(_ sender: Any?)
    func orderFrontRegardless()
}

protocol AppWindowOpeningApplication: AnyObject {
    var isHidden: Bool { get }
    var appWindows: [any AppWindowOpeningWindow] { get }

    func activate(ignoringOtherApps flag: Bool)
    func unhide(_ sender: Any?)
    func sendShowSettingsWindowAction() -> Bool
}

extension NSWindow: AppWindowOpeningWindow {
    var isPanelWindow: Bool {
        self is NSPanel
    }
}

extension NSApplication: AppWindowOpeningApplication {
    var appWindows: [any AppWindowOpeningWindow] {
        windows.map { $0 }
    }

    func sendShowSettingsWindowAction() -> Bool {
        sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
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
    static let minAutoEnterDelay: Double = 0.0
    static let maxAutoEnterDelay: Double = 999.99

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
        return (clamped * 100).rounded() / 100
    }

    static func sanitizeAutoEnterDelayText(_ rawText: String) -> String {
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

        if let parsedValue = Double(sanitized), parsedValue > maxAutoEnterDelay {
            return String(format: "%.2f", maxAutoEnterDelay)
        }

        return sanitized
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
            return AppStrings.text(.themeFollowSystem)
        case .light:
            return AppStrings.text(.themeLight)
        case .dark:
            return AppStrings.text(.themeDark)
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
        activateMainWindowOrOpenHomeScene(application: NSApp)
    }

    @MainActor
    static func activateMainWindowOrOpenHomeScene(application: any AppWindowOpeningApplication) {
        application.activate(ignoringOtherApps: true)
        if application.isHidden {
            application.unhide(nil)
        }
        if let window = application.appWindows.first(where: { !$0.isPanelWindow }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        _ = application.sendShowSettingsWindowAction()
    }
}

@main
struct FlowTabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appWindowWidth: CGFloat = 1120
    private let appWindowHeight: CGFloat = 760
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue

    private var appLanguage: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    init() {
        SystemAppMRUTracker.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup("FlowTab") {
            HomeRootView()
                .frame(minWidth: appWindowWidth, minHeight: appWindowHeight)
                .id(appLanguageRaw)
        }
        .defaultSize(width: appWindowWidth, height: appWindowHeight)

        Settings {
            HomeRootView()
                .frame(minWidth: appWindowWidth, minHeight: appWindowHeight)
                .id(appLanguageRaw)
        }

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(AppStrings.text(.menuSettings, language: appLanguage)) {
                    AppWindowCoordinator.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu(AppStrings.text(.menuLogs, language: appLanguage)) {
                Button(AppStrings.text(.menuOpenLogs, language: appLanguage)) {
                    AppWindowCoordinator.openLogs()
                }
            }

            CommandMenu(AppStrings.text(.menuSettings, language: appLanguage)) {
                Button(AppStrings.text(.menuOpenSettings, language: appLanguage)) {
                    AppWindowCoordinator.openSettings()
                }
                Button(AppStrings.text(.menuOpenHome, language: appLanguage)) {
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
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue

    private var themeMode: ThemeMode {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
    }

    private var dividerColor: Color {
        resolvedColorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    private var resolvedColorScheme: ColorScheme {
        themeMode.resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    @ViewBuilder
    private func tabContainer<Content: View>(
        isSelected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(selectedTab: $tabState.selectedTab)

            Divider()
                .overlay(dividerColor)

            ZStack {
                tabContainer(isSelected: tabState.selectedTab == .home) {
                    HomeLandingView(isActive: tabState.selectedTab == .home) {
                        tabState.selectedTab = .settings
                    }
                }
                tabContainer(isSelected: tabState.selectedTab == .logs) {
                    AppLogsView(isActive: tabState.selectedTab == .logs)
                }
                tabContainer(isSelected: tabState.selectedTab == .settings) {
                    AppSettingsView(isActive: tabState.selectedTab == .settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(resolvedColorScheme)
        .animation(.none, value: resolvedColorScheme)
        .id(appLanguageRaw)
    }
}

private struct HomeSidebar: View {
    @Binding var selectedTab: HomeTab
    @ObservedObject private var systemTheme = SystemThemeState.shared
    @AppStorage(AppPreferenceKeys.themeMode)
    private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue
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

    private var appLanguage: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    private var items: [(tab: HomeTab, title: String, icon: String)] {
        [
            (.home, AppStrings.text(.tabHome, language: appLanguage), "house.fill"),
            (.logs, AppStrings.text(.tabLogs, language: appLanguage), "text.alignleft"),
            (.settings, AppStrings.text(.tabSettings, language: appLanguage), "gearshape")
        ]
    }

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

                    VStack(alignment: .leading, spacing: 0) {
                        Text("FlowTab")
                            .font(.system(size: 21, weight: .bold))
                            .lineLimit(1)
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
                    .tracking(appLanguage == .english ? 0 : 4)
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
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue
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

    private var appLanguage: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    private var permissionGuideMessage: String {
        if !accessibilityTrusted && !screenCaptureTrusted {
            return AppStrings.text(.permissionGuideAll, language: appLanguage)
        }
        if !accessibilityTrusted {
            return AppStrings.text(.permissionGuideAccessibility, language: appLanguage)
        }
        if !screenCaptureTrusted {
            return AppStrings.text(.permissionGuideScreenCapture, language: appLanguage)
        }
        return AppStrings.text(.permissionGuideReady, language: appLanguage)
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
            if active {
                handleVisibilityChanged(true)
            }
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

            FlowActionButton(title: AppStrings.text(.actionGoToSettings, language: appLanguage), tone: .blueDominant) {
                openSettings()
            }

            FlowActionButton(
                title: AppStrings.text(.actionDontRemindAgain, language: appLanguage),
                tone: .grayDominant
            ) {
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
        HomeSectionCard(
            title: AppStrings.text(.homeAppLayerTitle, language: appLanguage),
            subtitle: AppStrings.text(.homeAppLayerSubtitle, language: appLanguage)
        ) {
            if appSummaries.isEmpty {
                HomeLayerRowView(
                    title: AppStrings.text(.homeNoSwitchableApps, language: appLanguage),
                    subtitle: AppStrings.text(
                        .homeTriggerHotkeyFirst,
                        replacements: ["hotkey": hotkeyConfiguration.mainShortcutText],
                        language: appLanguage
                    ),
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
            title: AppStrings.text(.homeWindowLayerTitle, language: appLanguage),
            subtitle: activeApp.map {
                AppStrings.text(
                    .homeAppWindowsOf,
                    replacements: ["app": $0.displayName],
                    language: appLanguage
                )
            } ?? AppStrings.text(.homeCurrentAppWindows, language: appLanguage)
        ) {
            if let activeApp, windowsByAppID[activeApp.appID] == nil {
                HomeLayerRowView(
                    title: AppStrings.text(.homeWindowDataLoading, language: appLanguage),
                    subtitle: AppStrings.text(
                        .homeReadingWindowsOf,
                        replacements: ["app": activeApp.displayName],
                        language: appLanguage
                    ),
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
                    title: AppStrings.text(.homeNoSwitchableWindows, language: appLanguage),
                    subtitle: AppStrings.text(.homeConfirmAccessibility, language: appLanguage),
                    trailing: "0w",
                    isSelected: false
                )
            } else {
                HomeLayerRowView(
                    title: AppStrings.text(.homeNoWindowData, language: appLanguage),
                    subtitle: AppStrings.text(.homeWaitCacheUpdate, language: appLanguage),
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
        guard active else { return }

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

private struct AppKitHotkeySettingsCardContent: NSViewRepresentable {
    @Binding var hotkeyPrimaryModifierRaw: String
    @Binding var hotkeyMainKeyRaw: String
    @Binding var hotkeyQuitKeyRaw: String
    @Binding var inAppWindowHotkeyPrimaryModifierRaw: String
    @Binding var inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverActive: Bool
    let accessibilityTrusted: Bool

    final class Coordinator {
        var hotkeyPrimaryModifierRaw: Binding<String>
        var hotkeyMainKeyRaw: Binding<String>
        var hotkeyQuitKeyRaw: Binding<String>
        var inAppWindowHotkeyPrimaryModifierRaw: Binding<String>
        var inAppWindowHotkeyMainKeyRaw: Binding<String>

        init(
            hotkeyPrimaryModifierRaw: Binding<String>,
            hotkeyMainKeyRaw: Binding<String>,
            hotkeyQuitKeyRaw: Binding<String>,
            inAppWindowHotkeyPrimaryModifierRaw: Binding<String>,
            inAppWindowHotkeyMainKeyRaw: Binding<String>
        ) {
            self.hotkeyPrimaryModifierRaw = hotkeyPrimaryModifierRaw
            self.hotkeyMainKeyRaw = hotkeyMainKeyRaw
            self.hotkeyQuitKeyRaw = hotkeyQuitKeyRaw
            self.inAppWindowHotkeyPrimaryModifierRaw = inAppWindowHotkeyPrimaryModifierRaw
            self.inAppWindowHotkeyMainKeyRaw = inAppWindowHotkeyMainKeyRaw
        }

        func update(
            hotkeyPrimaryModifierRaw: Binding<String>,
            hotkeyMainKeyRaw: Binding<String>,
            hotkeyQuitKeyRaw: Binding<String>,
            inAppWindowHotkeyPrimaryModifierRaw: Binding<String>,
            inAppWindowHotkeyMainKeyRaw: Binding<String>
        ) {
            self.hotkeyPrimaryModifierRaw = hotkeyPrimaryModifierRaw
            self.hotkeyMainKeyRaw = hotkeyMainKeyRaw
            self.hotkeyQuitKeyRaw = hotkeyQuitKeyRaw
            self.inAppWindowHotkeyPrimaryModifierRaw = inAppWindowHotkeyPrimaryModifierRaw
            self.inAppWindowHotkeyMainKeyRaw = inAppWindowHotkeyMainKeyRaw
        }

        func setHotkeyPrimaryModifier(_ rawValue: String) {
            hotkeyPrimaryModifierRaw.wrappedValue = rawValue
        }

        func setHotkeyMainKey(_ rawValue: String) {
            hotkeyMainKeyRaw.wrappedValue = rawValue
        }

        func setHotkeyQuitKey(_ rawValue: String) {
            hotkeyQuitKeyRaw.wrappedValue = rawValue
        }

        func setInAppWindowPrimaryModifier(_ rawValue: String) {
            inAppWindowHotkeyPrimaryModifierRaw.wrappedValue = rawValue
        }

        func setInAppWindowMainKey(_ rawValue: String) {
            inAppWindowHotkeyMainKeyRaw.wrappedValue = rawValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            hotkeyPrimaryModifierRaw: $hotkeyPrimaryModifierRaw,
            hotkeyMainKeyRaw: $hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: $hotkeyQuitKeyRaw,
            inAppWindowHotkeyPrimaryModifierRaw: $inAppWindowHotkeyPrimaryModifierRaw,
            inAppWindowHotkeyMainKeyRaw: $inAppWindowHotkeyMainKeyRaw
        )
    }

    func makeNSView(context: Context) -> HotkeySettingsCardAppKitView {
        let view = HotkeySettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: HotkeySettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: HotkeySettingsCardAppKitView, context: Context) {
        context.coordinator.update(
            hotkeyPrimaryModifierRaw: $hotkeyPrimaryModifierRaw,
            hotkeyMainKeyRaw: $hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: $hotkeyQuitKeyRaw,
            inAppWindowHotkeyPrimaryModifierRaw: $inAppWindowHotkeyPrimaryModifierRaw,
            inAppWindowHotkeyMainKeyRaw: $inAppWindowHotkeyMainKeyRaw
        )
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: HotkeySettingsCardState(
                hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw,
                inAppWindowHotkeyPrimaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw,
                inAppWindowHotkeyMainKeyRaw: inAppWindowHotkeyMainKeyRaw,
                commandTabTakeoverActive: commandTabTakeoverActive,
                accessibilityTrusted: accessibilityTrusted
            )
        )
    }

    private func connect(_ view: HotkeySettingsCardAppKitView, coordinator: Coordinator) {
        view.onHotkeyPrimaryModifierChanged = { coordinator.setHotkeyPrimaryModifier($0) }
        view.onHotkeyMainKeyChanged = { coordinator.setHotkeyMainKey($0) }
        view.onHotkeyQuitKeyChanged = { coordinator.setHotkeyQuitKey($0) }
        view.onInAppWindowPrimaryModifierChanged = { coordinator.setInAppWindowPrimaryModifier($0) }
        view.onInAppWindowMainKeyChanged = { coordinator.setInAppWindowMainKey($0) }
    }
}

private struct HotkeySettingsCardState: Equatable {
    let hotkeyPrimaryModifierRaw: String
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyPrimaryModifierRaw: String
    let inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverActive: Bool
    let accessibilityTrusted: Bool

    var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: hotkeyPrimaryModifierRaw,
            mainKeyRaw: hotkeyMainKeyRaw,
            quitKeyRaw: hotkeyQuitKeyRaw
        )
    }

    var inAppWindowHotkeyConfiguration: SwitcherHotkeyConfiguration {
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

    var mainUsesCommandTab: Bool {
        hotkeyConfiguration.primaryModifier == .command && hotkeyConfiguration.mainKey == .tab
    }

    var inAppUsesCommandTab: Bool {
        inAppWindowHotkeyConfiguration.primaryModifier == .command
            && inAppWindowHotkeyConfiguration.mainKey == .tab
    }

    var commandTabTakeoverStatusText: String {
        commandTabTakeoverActive
            ? AppStrings.text(.hotkeyCommandTabTakeoverActive)
            : AppStrings.text(.hotkeyCommandTabTakeoverInactive)
    }

    var mainSummaryText: String {
        AppStrings.text(
            .hotkeyMainSummary,
            replacements: [
                "main": hotkeyConfiguration.mainShortcutText,
                "reverseLabel": AppStrings.text(.hotkeySummaryReverseLabel),
                "reverse": hotkeyConfiguration.backwardShortcutText,
                "quitLabel": AppStrings.text(.hotkeySummaryQuitLabel),
                "quit": hotkeyConfiguration.quitShortcutText
            ]
        )
    }

    var inAppSummaryText: String {
        AppStrings.text(
            .hotkeyInAppSummary,
            replacements: [
                "inAppLabel": AppStrings.text(.hotkeySummaryInAppLabel),
                "main": inAppWindowHotkeyConfiguration.mainShortcutText,
                "reverseLabel": AppStrings.text(.hotkeySummaryReverseLabel),
                "reverse": inAppWindowHotkeyConfiguration.backwardShortcutText
            ]
        )
    }
}

private final class HotkeySettingsCardAppKitView: NSView {
    var onHotkeyPrimaryModifierChanged: ((String) -> Void)?
    var onHotkeyMainKeyChanged: ((String) -> Void)?
    var onHotkeyQuitKeyChanged: ((String) -> Void)?
    var onInAppWindowPrimaryModifierChanged: ((String) -> Void)?
    var onInAppWindowMainKeyChanged: ((String) -> Void)?

    private let stackView = NSStackView()
    private let mainPrimaryModifierPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let mainKeyPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let quitKeyPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let inAppPrimaryModifierPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let inAppMainKeyPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let mainSummaryLabel = HotkeySettingsCardAppKitView.makeSecondaryLabel()
    private let mainTakeoverStatusLabel = HotkeySettingsCardAppKitView.makeStatusLabel()
    private let divider = NSBox()
    private let inAppRowsContainer = NSStackView()
    private let inAppSummaryLabel = HotkeySettingsCardAppKitView.makeSecondaryLabel()
    private let inAppTakeoverStatusLabel = HotkeySettingsCardAppKitView.makeStatusLabel()
    private var isApplyingState = false
    private var currentState: HotkeySettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(width: NSView.noIntrinsicMetric, height: stackView.fittingSize.height)
    }

    func update(with state: HotkeySettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        selectItem(in: mainPrimaryModifierPopUp, rawValue: state.hotkeyConfiguration.primaryModifier.rawValue)
        selectItem(in: mainKeyPopUp, rawValue: state.hotkeyConfiguration.mainKey.rawValue)
        selectItem(in: quitKeyPopUp, rawValue: state.hotkeyConfiguration.quitKey.rawValue)
        selectItem(
            in: inAppPrimaryModifierPopUp,
            rawValue: state.inAppWindowHotkeyConfiguration.primaryModifier.rawValue
        )
        selectItem(
            in: inAppMainKeyPopUp,
            rawValue: state.inAppWindowHotkeyConfiguration.mainKey.rawValue
        )
        isApplyingState = false

        mainSummaryLabel.stringValue = state.mainSummaryText
        mainTakeoverStatusLabel.stringValue = state.commandTabTakeoverStatusText
        mainTakeoverStatusLabel.textColor = state.commandTabTakeoverActive ? .systemGreen : .systemRed
        mainTakeoverStatusLabel.isHidden = !state.mainUsesCommandTab

        inAppRowsContainer.alphaValue = state.accessibilityTrusted ? 1 : 0.55
        inAppPrimaryModifierPopUp.isEnabled = state.accessibilityTrusted
        inAppMainKeyPopUp.isEnabled = state.accessibilityTrusted
        inAppSummaryLabel.stringValue = state.inAppSummaryText
        inAppTakeoverStatusLabel.stringValue = state.commandTabTakeoverStatusText
        inAppTakeoverStatusLabel.textColor = state.commandTabTakeoverActive ? .systemGreen : .systemRed
        inAppTakeoverStatusLabel.isHidden = !state.inAppUsesCommandTab

        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        configure(
            popUp: mainPrimaryModifierPopUp,
            options: SwitcherPrimaryModifier.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            action: #selector(handleMainPrimaryModifierChanged)
        )
        configure(
            popUp: mainKeyPopUp,
            options: SwitcherHotkeyKey.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            action: #selector(handleMainKeyChanged)
        )
        configure(
            popUp: quitKeyPopUp,
            options: SwitcherHotkeyKey.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            action: #selector(handleQuitKeyChanged)
        )
        configure(
            popUp: inAppPrimaryModifierPopUp,
            options: SwitcherPrimaryModifier.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            action: #selector(handleInAppPrimaryModifierChanged)
        )
        configure(
            popUp: inAppMainKeyPopUp,
            options: SwitcherHotkeyKey.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            action: #selector(handleInAppMainKeyChanged)
        )

        let mainPrimaryRow = makeControlRow(title: AppStrings.text(.hotkeyRowMainModifier), control: mainPrimaryModifierPopUp)
        let mainKeyRow = makeControlRow(title: AppStrings.text(.hotkeyRowMainKey), control: mainKeyPopUp)
        let quitKeyRow = makeControlRow(title: AppStrings.text(.hotkeyRowQuitKey), control: quitKeyPopUp)
        stackView.addArrangedSubview(mainPrimaryRow)
        stackView.addArrangedSubview(mainKeyRow)
        stackView.addArrangedSubview(quitKeyRow)
        mainPrimaryRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        mainKeyRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        quitKeyRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        stackView.addArrangedSubview(mainSummaryLabel)
        stackView.addArrangedSubview(mainTakeoverStatusLabel)

        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        inAppRowsContainer.orientation = .vertical
        inAppRowsContainer.alignment = .leading
        inAppRowsContainer.spacing = 10
        inAppRowsContainer.detachesHiddenViews = true
        inAppRowsContainer.translatesAutoresizingMaskIntoConstraints = false
        inAppRowsContainer.setContentHuggingPriority(.required, for: .vertical)
        inAppRowsContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        let inAppPrimaryRow = makeControlRow(title: AppStrings.text(.hotkeyRowInAppModifier), control: inAppPrimaryModifierPopUp)
        let inAppMainKeyRow = makeControlRow(title: AppStrings.text(.hotkeyRowInAppKey), control: inAppMainKeyPopUp)
        inAppRowsContainer.addArrangedSubview(inAppPrimaryRow)
        inAppRowsContainer.addArrangedSubview(inAppMainKeyRow)
        inAppPrimaryRow.widthAnchor.constraint(equalTo: inAppRowsContainer.widthAnchor).isActive = true
        inAppMainKeyRow.widthAnchor.constraint(equalTo: inAppRowsContainer.widthAnchor).isActive = true

        stackView.addArrangedSubview(inAppRowsContainer)
        stackView.addArrangedSubview(inAppSummaryLabel)
        stackView.addArrangedSubview(inAppTakeoverStatusLabel)
    }

    private func makeControlRow(title: String, control: NSPopUpButton) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.detachesHiddenViews = true
        return row
    }

    private func configure(
        popUp: NSPopUpButton,
        options: [(id: String, title: String)],
        action: Selector
    ) {
        popUp.target = self
        popUp.action = action
        popUp.controlSize = .regular
        popUp.font = .systemFont(ofSize: 13)
        popUp.alignment = .right
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.menu = NSMenu()

        for option in options {
            let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
            item.representedObject = option.id
            popUp.menu?.addItem(item)
        }

        popUp.widthAnchor.constraint(equalToConstant: 160).isActive = true
    }

    private func selectItem(in popUp: NSPopUpButton, rawValue: String) {
        guard let item = popUp.itemArray.first(where: { ($0.representedObject as? String) == rawValue }) else {
            return
        }
        popUp.select(item)
    }

    @objc private func handleMainPrimaryModifierChanged(_ sender: NSPopUpButton) {
        guard !isApplyingState else { return }
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        onHotkeyPrimaryModifierChanged?(rawValue)
    }

    @objc private func handleMainKeyChanged(_ sender: NSPopUpButton) {
        guard !isApplyingState else { return }
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        onHotkeyMainKeyChanged?(rawValue)
    }

    @objc private func handleQuitKeyChanged(_ sender: NSPopUpButton) {
        guard !isApplyingState else { return }
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        onHotkeyQuitKeyChanged?(rawValue)
    }

    @objc private func handleInAppPrimaryModifierChanged(_ sender: NSPopUpButton) {
        guard !isApplyingState else { return }
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        onInAppWindowPrimaryModifierChanged?(rawValue)
    }

    @objc private func handleInAppMainKeyChanged(_ sender: NSPopUpButton) {
        guard !isApplyingState else { return }
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        onInAppWindowMainKeyChanged?(rawValue)
    }

    private static func makeSecondaryLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private static func makeStatusLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isHidden = true
        return label
    }
}

private extension NSView {
    func preferredFittingSize(forWidth width: CGFloat?) -> CGSize {
        let widthConstraint: NSLayoutConstraint?
        let normalizedWidth = width.flatMap { proposedWidth -> CGFloat? in
            guard proposedWidth.isFinite, proposedWidth > 0 else { return nil }
            return proposedWidth
        }

        if let normalizedWidth {
            // SwiftUI may pass `.infinity`/`nan` during measurement; AppKit crashes if that becomes a constraint constant.
            widthConstraint = widthAnchor.constraint(equalToConstant: normalizedWidth)
            widthConstraint?.priority = .defaultHigh
            widthConstraint?.isActive = true
        } else {
            widthConstraint = nil
        }

        layoutSubtreeIfNeeded()
        let fitted = fittingSize
        widthConstraint?.isActive = false
        return fitted
    }
}

private final class FlowCapsuleSegmentedControl: NSView {
    var onSelectionChanged: ((String) -> Void)?

    private let options: [(id: String, title: String)]
    private let stackView = NSStackView()
    private var buttonsByID: [String: NSButton] = [:]
    private var selectedID: String?

    init(options: [(id: String, title: String)]) {
        self.options = options
        super.init(frame: .zero)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        self.options = []
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 300, height: 32)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateSelection(id: String) {
        guard selectedID != id else { return }
        selectedID = id
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])

        for option in options {
            let button = NSButton(title: option.title, target: self, action: #selector(handleButtonPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(option.id)
            button.setButtonType(.momentaryChange)
            button.isBordered = false
            button.focusRingType = .none
            button.translatesAutoresizingMaskIntoConstraints = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 9
            button.layer?.masksToBounds = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            stackView.addArrangedSubview(button)
            buttonsByID[option.id] = button
        }

        updateAppearance()
    }

    @objc private func handleButtonPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        selectedID = id
        updateAppearance()
        onSelectionChanged?(id)
    }

    private func updateAppearance() {
        guard let layer else { return }
        layer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor

        for (id, button) in buttonsByID {
            let isSelected = id == selectedID
            button.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
            let titleColor = isSelected ? NSColor.controlAccentColor : NSColor.labelColor
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: titleColor
                ]
            )
        }
    }
}

private final class FlowGradientActionButton: NSButton {
    var tone: FlowActionButtonTone = .grayDominant {
        didSet { updateAppearance() }
    }

    private let gradientLayer = CAGradientLayer()
    private let borderLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(title: String, symbolName: String? = nil, tone: FlowActionButtonTone) {
        self.title = title
        self.tone = tone
        if let symbolName {
            image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        } else {
            image = nil
        }
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true

        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradientLayer)
        layer?.addSublayer(borderLayer)
        updateAppearance()
    }

    private func updateAppearance() {
        wantsLayer = true
        let cornerRadius = bounds.height / 2
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = cornerRadius
        gradientLayer.colors = gradientColors(for: tone)

        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1
        borderLayer.strokeColor = borderColor(for: tone)

        layer?.cornerRadius = cornerRadius
        layer?.shadowColor = shadowColor(for: tone)
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: 2)

        let titleColor = tone == .blueDominant
            ? NSColor.white
            : NSColor.labelColor.withAlphaComponent(0.78)
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: titleColor
            ]
        )
        contentTintColor = titleColor
    }

    private func gradientColors(for tone: FlowActionButtonTone) -> [CGColor] {
        switch tone {
        case .grayDominant:
            return [
                NSColor.labelColor.withAlphaComponent(0.12).cgColor,
                NSColor.labelColor.withAlphaComponent(0.09).cgColor,
                NSColor.controlAccentColor.withAlphaComponent(0.26).cgColor
            ]
        case .blueDominant:
            return [
                NSColor.controlAccentColor.withAlphaComponent(0.94).cgColor,
                NSColor.controlAccentColor.withAlphaComponent(0.76).cgColor,
                NSColor.labelColor.withAlphaComponent(0.18).cgColor
            ]
        }
    }

    private func borderColor(for tone: FlowActionButtonTone) -> CGColor {
        switch tone {
        case .grayDominant:
            return NSColor.labelColor.withAlphaComponent(0.24).cgColor
        case .blueDominant:
            return NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
        }
    }

    private func shadowColor(for tone: FlowActionButtonTone) -> CGColor {
        switch tone {
        case .grayDominant:
            return NSColor.labelColor.withAlphaComponent(0.08).cgColor
        case .blueDominant:
            return NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
        }
    }
}

private final class FlowSoftTextField: NSView {
    let textField = NSTextField(string: "")

    private var isEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 72, height: 28)
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setEditing(_ editing: Bool) {
        guard isEditing != editing else { return }
        isEditing = editing
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = "0.35"
        textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.alignment = .center
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }

        let isDark = effectiveAppearance.isFlowTabDarkInterface
        let borderColor: NSColor
        let backgroundColor: NSColor

        if isEditing {
            borderColor = .controlAccentColor.withAlphaComponent(isDark ? 0.55 : 0.35)
            backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.white.withAlphaComponent(0.98)
            layer.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 5
            layer.shadowOffset = .zero
        } else {
            borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.black.withAlphaComponent(0.08)
            backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.05)
                : NSColor.white.withAlphaComponent(0.84)
            layer.shadowOpacity = 0
        }

        layer.cornerRadius = 9
        layer.borderWidth = 1
        layer.borderColor = borderColor.cgColor
        layer.backgroundColor = backgroundColor.cgColor
    }
}

private class AppKitSettingsCardBaseView: NSView {
    let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureRootStack()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureRootStack()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(width: NSView.noIntrinsicMetric, height: stackView.fittingSize.height)
    }

    func addFullWidthArrangedSubview(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func configureRootStack() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    static func makeControlRow(title: String, control: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.detachesHiddenViews = true
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    static func makeBodyLabel(fontSize: CGFloat = 11) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: fontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    static func makeStatusLabel(fontSize: CGFloat = 12) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: fontSize)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    static func configure(
        popUp: NSPopUpButton,
        options: [(id: String, title: String)],
        target: AnyObject,
        action: Selector,
        width: CGFloat = 160
    ) {
        popUp.target = target
        popUp.action = action
        popUp.controlSize = .regular
        popUp.font = .systemFont(ofSize: 13)
        popUp.alignment = .right
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.menu = NSMenu()

        for option in options {
            let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
            item.representedObject = option.id
            popUp.menu?.addItem(item)
        }

        popUp.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    static func selectItem(in popUp: NSPopUpButton, rawValue: String) {
        guard let item = popUp.itemArray.first(where: { ($0.representedObject as? String) == rawValue }) else {
            return
        }
        popUp.select(item)
    }

}

private extension NSAppearance {
    var isFlowTabDarkInterface: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private final class AppKitSectionCardView: NSView {
    private let stackView = NSStackView()
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private let verticalInset: CGFloat = 14

    init(title: String, subtitle: String, contentView: NSView) {
        titleLabel = NSTextField(labelWithString: title)
        subtitleLabel = NSTextField(labelWithString: subtitle)
        super.init(frame: .zero)
        buildViewHierarchy(contentView: contentView)
    }

    required init?(coder: NSCoder) {
        titleLabel = NSTextField(labelWithString: "")
        subtitleLabel = NSTextField(labelWithString: "")
        super.init(coder: coder)
        buildViewHierarchy(contentView: NSView())
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: stackView.fittingSize.height + verticalInset * 2
        )
    }

    private func buildViewHierarchy(contentView: NSView) {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.setContentHuggingPriority(.required, for: .vertical)
        contentView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -verticalInset)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        if effectiveAppearance.isFlowTabDarkInterface {
            layer.backgroundColor = NSColor(
                red: 0.13,
                green: 0.13,
                blue: 0.15,
                alpha: 0.96
            ).cgColor
            layer.borderColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
            layer.shadowOpacity = 0
        } else {
            layer.backgroundColor = NSColor(
                red: 0.965,
                green: 0.97,
                blue: 0.978,
                alpha: 1
            ).cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.14).cgColor
            layer.shadowColor = NSColor.black.withAlphaComponent(0.05).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        layer.cornerRadius = 12
        layer.borderWidth = 1
    }
}

private struct AppKitSettingsPageState: Equatable {
    let showShortcutHint: Bool
    let showInCommandTab: Bool
    let themeModeRaw: String
    let appLanguageRaw: String
    let windowLayerAutoEnterDelayText: String
    let autoRestoreMinimizedWindowOnSwitch: Bool
    let hideMinimizedAppsFromAppLayer: Bool
    let showPermissionReminder: Bool
    let searchEnabled: Bool
    let searchDefaultScopeRaw: String
    let hotkeyPrimaryModifierRaw: String
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyPrimaryModifierRaw: String
    let inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverActive: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
}

private final class AppKitFlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class AppKitSettingsPageContainerView: NSView {
    let pageView = AppKitSettingsPageView()

    private let scrollView = NSScrollView()
    private let documentView = AppKitFlippedDocumentView()
    private let contentInset: CGFloat = 24
    private var wasActive = false
    private var pendingInitialFocusClear = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func update(with state: AppKitSettingsPageState, isActive: Bool) {
        pageView.update(with: state)
        if isActive && !wasActive {
            clearInitialFirstResponderIfNeeded()
        }
        wasActive = isActive
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let viewportWidth = scrollView.contentView.bounds.width
        guard viewportWidth > 0 else { return }

        let pageWidth = max(viewportWidth - contentInset * 2, 320)
        let fittedSize = pageView.preferredFittingSize(forWidth: pageWidth)
        let documentHeight = fittedSize.height + contentInset * 2

        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: viewportWidth,
            height: documentHeight
        )
        pageView.frame = NSRect(
            x: contentInset,
            y: contentInset,
            width: pageWidth,
            height: fittedSize.height
        )
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        pageView.translatesAutoresizingMaskIntoConstraints = true
        documentView.translatesAutoresizingMaskIntoConstraints = true
        documentView.addSubview(pageView)
        scrollView.documentView = documentView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func clearInitialFirstResponderIfNeeded() {
        guard !pendingInitialFocusClear else { return }
        pendingInitialFocusClear = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingInitialFocusClear = false
            self.resignPageFirstResponderIfNeeded()
        }
    }

    private func resignPageFirstResponderIfNeeded() {
        guard let window else { return }

        if let view = window.firstResponder as? NSView, view.isDescendant(of: pageView) {
            window.makeFirstResponder(nil)
            return
        }

        if let editor = window.firstResponder as? NSTextView,
            let editedView = editor.delegate as? NSView,
            editedView.isDescendant(of: pageView)
        {
            window.makeFirstResponder(nil)
        }
    }
}

private struct AppKitSettingsPageContent: NSViewRepresentable {
    let isActive: Bool
    @Binding var showShortcutHint: Bool
    @Binding var showInCommandTab: Bool
    @Binding var themeModeRaw: String
    @Binding var appLanguageRaw: String
    let windowLayerAutoEnterDelayText: String
    @Binding var autoRestoreMinimizedWindowOnSwitch: Bool
    @Binding var hideMinimizedAppsFromAppLayer: Bool
    @Binding var showPermissionReminder: Bool
    @Binding var searchEnabled: Bool
    @Binding var searchDefaultScopeRaw: String
    @Binding var hotkeyPrimaryModifierRaw: String
    @Binding var hotkeyMainKeyRaw: String
    @Binding var hotkeyQuitKeyRaw: String
    @Binding var inAppWindowHotkeyPrimaryModifierRaw: String
    @Binding var inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverActive: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let onWindowLayerAutoEnterDelayTextChanged: (String) -> Void
    let onWindowLayerAutoEnterDelayTextCommitted: () -> Void
    let onWindowLayerAutoEnterDelayEditingChanged: (Bool) -> Void
    let onAccessibilityAction: () -> Void
    let onScreenCaptureAction: () -> Void

    func makeNSView(context: Context) -> AppKitSettingsPageContainerView {
        AppKitSettingsPageContainerView()
    }

    func updateNSView(_ nsView: AppKitSettingsPageContainerView, context: Context) {
        let showShortcutHint = $showShortcutHint
        let showInCommandTab = $showInCommandTab
        let themeModeRaw = $themeModeRaw
        let appLanguageRaw = $appLanguageRaw
        let autoRestoreMinimizedWindowOnSwitch = $autoRestoreMinimizedWindowOnSwitch
        let hideMinimizedAppsFromAppLayer = $hideMinimizedAppsFromAppLayer
        let showPermissionReminder = $showPermissionReminder
        let searchEnabled = $searchEnabled
        let searchDefaultScopeRaw = $searchDefaultScopeRaw
        let hotkeyPrimaryModifierRaw = $hotkeyPrimaryModifierRaw
        let hotkeyMainKeyRaw = $hotkeyMainKeyRaw
        let hotkeyQuitKeyRaw = $hotkeyQuitKeyRaw
        let inAppWindowHotkeyPrimaryModifierRaw = $inAppWindowHotkeyPrimaryModifierRaw
        let inAppWindowHotkeyMainKeyRaw = $inAppWindowHotkeyMainKeyRaw
        let pageView = nsView.pageView

        pageView.onShowShortcutHintChanged = { showShortcutHint.wrappedValue = $0 }
        pageView.onShowInCommandTabChanged = { showInCommandTab.wrappedValue = $0 }
        pageView.onThemeModeChanged = { themeModeRaw.wrappedValue = $0 }
        pageView.onAppLanguageChanged = { appLanguageRaw.wrappedValue = $0 }
        pageView.onWindowLayerAutoEnterDelayTextChanged = onWindowLayerAutoEnterDelayTextChanged
        pageView.onWindowLayerAutoEnterDelayTextCommitted = onWindowLayerAutoEnterDelayTextCommitted
        pageView.onWindowLayerAutoEnterDelayEditingChanged = onWindowLayerAutoEnterDelayEditingChanged
        pageView.onAutoRestoreMinimizedWindowOnSwitchChanged = {
            autoRestoreMinimizedWindowOnSwitch.wrappedValue = $0
        }
        pageView.onHideMinimizedAppsFromAppLayerChanged = {
            hideMinimizedAppsFromAppLayer.wrappedValue = $0
        }
        pageView.onSearchEnabledChanged = { searchEnabled.wrappedValue = $0 }
        pageView.onSearchDefaultScopeChanged = { searchDefaultScopeRaw.wrappedValue = $0 }
        pageView.onHotkeyPrimaryModifierChanged = { hotkeyPrimaryModifierRaw.wrappedValue = $0 }
        pageView.onHotkeyMainKeyChanged = { hotkeyMainKeyRaw.wrappedValue = $0 }
        pageView.onHotkeyQuitKeyChanged = { hotkeyQuitKeyRaw.wrappedValue = $0 }
        pageView.onInAppWindowPrimaryModifierChanged = {
            inAppWindowHotkeyPrimaryModifierRaw.wrappedValue = $0
        }
        pageView.onInAppWindowMainKeyChanged = {
            inAppWindowHotkeyMainKeyRaw.wrappedValue = $0
        }
        pageView.onShowPermissionReminderChanged = { showPermissionReminder.wrappedValue = $0 }
        pageView.onAccessibilityAction = onAccessibilityAction
        pageView.onScreenCaptureAction = onScreenCaptureAction
        nsView.update(
            with: AppKitSettingsPageState(
                showShortcutHint: showShortcutHint.wrappedValue,
                showInCommandTab: showInCommandTab.wrappedValue,
                themeModeRaw: themeModeRaw.wrappedValue,
                appLanguageRaw: appLanguageRaw.wrappedValue,
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: autoRestoreMinimizedWindowOnSwitch.wrappedValue,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer.wrappedValue,
                showPermissionReminder: showPermissionReminder.wrappedValue,
                searchEnabled: searchEnabled.wrappedValue,
                searchDefaultScopeRaw: searchDefaultScopeRaw.wrappedValue,
                hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw.wrappedValue,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw.wrappedValue,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw.wrappedValue,
                inAppWindowHotkeyPrimaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw.wrappedValue,
                inAppWindowHotkeyMainKeyRaw: inAppWindowHotkeyMainKeyRaw.wrappedValue,
                commandTabTakeoverActive: commandTabTakeoverActive,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted
            ),
            isActive: isActive
        )
    }
}

private final class AppKitSettingsPageView: NSView {
    var onShowShortcutHintChanged: ((Bool) -> Void)?
    var onShowInCommandTabChanged: ((Bool) -> Void)?
    var onThemeModeChanged: ((String) -> Void)?
    var onAppLanguageChanged: ((String) -> Void)?
    var onWindowLayerAutoEnterDelayTextChanged: ((String) -> Void)?
    var onWindowLayerAutoEnterDelayTextCommitted: (() -> Void)?
    var onWindowLayerAutoEnterDelayEditingChanged: ((Bool) -> Void)?
    var onAutoRestoreMinimizedWindowOnSwitchChanged: ((Bool) -> Void)?
    var onHideMinimizedAppsFromAppLayerChanged: ((Bool) -> Void)?
    var onSearchEnabledChanged: ((Bool) -> Void)?
    var onSearchDefaultScopeChanged: ((String) -> Void)?
    var onHotkeyPrimaryModifierChanged: ((String) -> Void)?
    var onHotkeyMainKeyChanged: ((String) -> Void)?
    var onHotkeyQuitKeyChanged: ((String) -> Void)?
    var onInAppWindowPrimaryModifierChanged: ((String) -> Void)?
    var onInAppWindowMainKeyChanged: ((String) -> Void)?
    var onShowPermissionReminderChanged: ((Bool) -> Void)?
    var onAccessibilityAction: (() -> Void)?
    var onScreenCaptureAction: (() -> Void)?

    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: AppStrings.text(.settingsPageTitle))
    private let subtitleLabel = NSTextField(labelWithString: AppStrings.text(.settingsPageSubtitle))
    private let columnsStack = NSStackView()
    private let leftColumn = NSStackView()
    private let rightColumn = NSStackView()
    private let dismissEditingClickRecognizer = NSClickGestureRecognizer()

    private let appearanceContent = AppearanceSettingsCardAppKitView()
    private let windowBehaviorContent = WindowBehaviorSettingsCardAppKitView()
    private let permissionContent = PermissionSettingsCardAppKitView()
    private let searchContent = SearchSettingsCardAppKitView()
    private let hotkeyContent = HotkeySettingsCardAppKitView()

    private lazy var appearanceCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardAppearanceTitle),
        subtitle: AppStrings.text(.settingsCardAppearanceSubtitle),
        contentView: appearanceContent
    )
    private lazy var windowBehaviorCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardWindowBehaviorTitle),
        subtitle: AppStrings.text(.settingsCardWindowBehaviorSubtitle),
        contentView: windowBehaviorContent
    )
    private lazy var permissionCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardPermissionTitle),
        subtitle: AppStrings.text(.settingsCardPermissionSubtitle),
        contentView: permissionContent
    )
    private lazy var searchCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardSearchTitle),
        subtitle: AppStrings.text(.settingsCardSearchSubtitle),
        contentView: searchContent
    )
    private lazy var hotkeyCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardHotkeyTitle),
        subtitle: AppStrings.text(.settingsCardHotkeySubtitle),
        contentView: hotkeyContent
    )

    private var currentState: AppKitSettingsPageState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
        wireCallbacks()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
        wireCallbacks()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(width: NSView.noIntrinsicMetric, height: contentStack.fittingSize.height)
    }

    func update(with state: AppKitSettingsPageState) {
        guard currentState != state else { return }
        currentState = state

        appearanceContent.update(
            with: AppearanceSettingsCardState(
                showShortcutHint: state.showShortcutHint,
                showInCommandTab: state.showInCommandTab,
                themeModeRaw: state.themeModeRaw,
                appLanguageRaw: state.appLanguageRaw
            )
        )
        windowBehaviorContent.update(
            with: WindowBehaviorSettingsCardState(
                windowLayerAutoEnterDelayText: state.windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: state.autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: state.hideMinimizedAppsFromAppLayer
            )
        )
        searchContent.update(
            with: SearchSettingsCardState(
                searchEnabled: state.searchEnabled,
                searchDefaultScopeRaw: state.searchDefaultScopeRaw
            )
        )
        hotkeyContent.update(
            with: HotkeySettingsCardState(
                hotkeyPrimaryModifierRaw: state.hotkeyPrimaryModifierRaw,
                hotkeyMainKeyRaw: state.hotkeyMainKeyRaw,
                hotkeyQuitKeyRaw: state.hotkeyQuitKeyRaw,
                inAppWindowHotkeyPrimaryModifierRaw: state.inAppWindowHotkeyPrimaryModifierRaw,
                inAppWindowHotkeyMainKeyRaw: state.inAppWindowHotkeyMainKeyRaw,
                commandTabTakeoverActive: state.commandTabTakeoverActive,
                accessibilityTrusted: state.accessibilityTrusted
            )
        )
        permissionContent.update(
            with: PermissionSettingsCardState(
                showPermissionReminder: state.showPermissionReminder,
                accessibilityTrusted: state.accessibilityTrusted,
                screenCaptureTrusted: state.screenCaptureTrusted
            )
        )
        appearanceCard.invalidateIntrinsicContentSize()
        windowBehaviorCard.invalidateIntrinsicContentSize()
        permissionCard.invalidateIntrinsicContentSize()
        searchCard.invalidateIntrinsicContentSize()
        hotkeyCard.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        dismissEditingClickRecognizer.target = self
        dismissEditingClickRecognizer.action = #selector(handlePageClickToDismissEditing(_:))
        dismissEditingClickRecognizer.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(dismissEditingClickRecognizer)

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2
        headerStack.detachesHiddenViews = true
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.detachesHiddenViews = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        columnsStack.orientation = .horizontal
        columnsStack.alignment = .top
        columnsStack.distribution = .fillEqually
        columnsStack.spacing = 12
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        columnsStack.setContentHuggingPriority(.required, for: .vertical)
        columnsStack.setContentCompressionResistancePriority(.required, for: .vertical)

        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 12
        leftColumn.detachesHiddenViews = true
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.setContentHuggingPriority(.required, for: .vertical)
        leftColumn.setContentCompressionResistancePriority(.required, for: .vertical)

        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = 12
        rightColumn.detachesHiddenViews = true
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.setContentHuggingPriority(.required, for: .vertical)
        rightColumn.setContentCompressionResistancePriority(.required, for: .vertical)

        contentStack.addArrangedSubview(headerStack)
        contentStack.addArrangedSubview(columnsStack)
        headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        columnsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        columnsStack.addArrangedSubview(leftColumn)
        columnsStack.addArrangedSubview(rightColumn)

        addCard(appearanceCard, to: leftColumn)
        addCard(windowBehaviorCard, to: leftColumn)
        addCard(permissionCard, to: leftColumn)
        addCard(searchCard, to: rightColumn)
        addCard(hotkeyCard, to: rightColumn)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func wireCallbacks() {
        appearanceContent.onShowShortcutHintChanged = { [weak self] in
            self?.onShowShortcutHintChanged?($0)
        }
        appearanceContent.onShowInCommandTabChanged = { [weak self] in
            self?.onShowInCommandTabChanged?($0)
        }
        appearanceContent.onThemeModeChanged = { [weak self] in
            self?.onThemeModeChanged?($0)
        }
        appearanceContent.onAppLanguageChanged = { [weak self] in
            self?.onAppLanguageChanged?($0)
        }

        windowBehaviorContent.onWindowLayerAutoEnterDelayTextChanged = { [weak self] in
            self?.onWindowLayerAutoEnterDelayTextChanged?($0)
        }
        windowBehaviorContent.onWindowLayerAutoEnterDelayTextCommitted = { [weak self] in
            self?.onWindowLayerAutoEnterDelayTextCommitted?()
        }
        windowBehaviorContent.onWindowLayerAutoEnterDelayEditingChanged = { [weak self] in
            self?.onWindowLayerAutoEnterDelayEditingChanged?($0)
        }
        windowBehaviorContent.onAutoRestoreMinimizedWindowOnSwitchChanged = { [weak self] in
            self?.onAutoRestoreMinimizedWindowOnSwitchChanged?($0)
        }
        windowBehaviorContent.onHideMinimizedAppsFromAppLayerChanged = { [weak self] in
            self?.onHideMinimizedAppsFromAppLayerChanged?($0)
        }

        searchContent.onSearchEnabledChanged = { [weak self] in
            self?.onSearchEnabledChanged?($0)
        }
        searchContent.onSearchDefaultScopeChanged = { [weak self] in
            self?.onSearchDefaultScopeChanged?($0)
        }

        hotkeyContent.onHotkeyPrimaryModifierChanged = { [weak self] in
            self?.onHotkeyPrimaryModifierChanged?($0)
        }
        hotkeyContent.onHotkeyMainKeyChanged = { [weak self] in
            self?.onHotkeyMainKeyChanged?($0)
        }
        hotkeyContent.onHotkeyQuitKeyChanged = { [weak self] in
            self?.onHotkeyQuitKeyChanged?($0)
        }
        hotkeyContent.onInAppWindowPrimaryModifierChanged = { [weak self] in
            self?.onInAppWindowPrimaryModifierChanged?($0)
        }
        hotkeyContent.onInAppWindowMainKeyChanged = { [weak self] in
            self?.onInAppWindowMainKeyChanged?($0)
        }

        permissionContent.onShowPermissionReminderChanged = { [weak self] in
            self?.onShowPermissionReminderChanged?($0)
        }
        permissionContent.onAccessibilityAction = { [weak self] in
            self?.onAccessibilityAction?()
        }
        permissionContent.onScreenCaptureAction = { [weak self] in
            self?.onScreenCaptureAction?()
        }
    }

    @objc private func handlePageClickToDismissEditing(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        let location = recognizer.location(in: self)
        let hitView = hitTest(location)
        guard !windowBehaviorContent.containsDelayInputDescendant(hitView) else { return }
        guard windowBehaviorContent.ownsDelayInputFirstResponder(window?.firstResponder) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    private func addCard(_ card: NSView, to column: NSStackView) {
        column.addArrangedSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    }
}

private struct AppKitAppearanceSettingsCardContent: NSViewRepresentable {
    @Binding var showShortcutHint: Bool
    @Binding var showInCommandTab: Bool
    @Binding var themeModeRaw: String
    @Binding var appLanguageRaw: String

    final class Coordinator {
        var showShortcutHint: Binding<Bool>
        var showInCommandTab: Binding<Bool>
        var themeModeRaw: Binding<String>
        var appLanguageRaw: Binding<String>

        init(
            showShortcutHint: Binding<Bool>,
            showInCommandTab: Binding<Bool>,
            themeModeRaw: Binding<String>,
            appLanguageRaw: Binding<String>
        ) {
            self.showShortcutHint = showShortcutHint
            self.showInCommandTab = showInCommandTab
            self.themeModeRaw = themeModeRaw
            self.appLanguageRaw = appLanguageRaw
        }

        func update(
            showShortcutHint: Binding<Bool>,
            showInCommandTab: Binding<Bool>,
            themeModeRaw: Binding<String>,
            appLanguageRaw: Binding<String>
        ) {
            self.showShortcutHint = showShortcutHint
            self.showInCommandTab = showInCommandTab
            self.themeModeRaw = themeModeRaw
            self.appLanguageRaw = appLanguageRaw
        }

        func setShowShortcutHint(_ value: Bool) {
            showShortcutHint.wrappedValue = value
        }

        func setShowInCommandTab(_ value: Bool) {
            showInCommandTab.wrappedValue = value
        }

        func setThemeMode(rawValue: String) {
            themeModeRaw.wrappedValue = rawValue
        }

        func setAppLanguage(rawValue: String) {
            appLanguageRaw.wrappedValue = rawValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            showShortcutHint: $showShortcutHint,
            showInCommandTab: $showInCommandTab,
            themeModeRaw: $themeModeRaw,
            appLanguageRaw: $appLanguageRaw
        )
    }

    func makeNSView(context: Context) -> AppearanceSettingsCardAppKitView {
        let view = AppearanceSettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AppearanceSettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: AppearanceSettingsCardAppKitView, context: Context) {
        context.coordinator.update(
            showShortcutHint: $showShortcutHint,
            showInCommandTab: $showInCommandTab,
            themeModeRaw: $themeModeRaw,
            appLanguageRaw: $appLanguageRaw
        )
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: AppearanceSettingsCardState(
                showShortcutHint: showShortcutHint,
                showInCommandTab: showInCommandTab,
                themeModeRaw: themeModeRaw,
                appLanguageRaw: appLanguageRaw
            )
        )
    }

    private func connect(_ view: AppearanceSettingsCardAppKitView, coordinator: Coordinator) {
        view.onShowShortcutHintChanged = { coordinator.setShowShortcutHint($0) }
        view.onShowInCommandTabChanged = { coordinator.setShowInCommandTab($0) }
        view.onThemeModeChanged = { coordinator.setThemeMode(rawValue: $0) }
        view.onAppLanguageChanged = { coordinator.setAppLanguage(rawValue: $0) }
    }
}

private struct AppearanceSettingsCardState: Equatable {
    let showShortcutHint: Bool
    let showInCommandTab: Bool
    let themeModeRaw: String
    let appLanguageRaw: String

    var resolvedThemeMode: ThemeMode {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
    }

    var resolvedAppLanguage: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }
}

private final class AppearanceSettingsCardAppKitView: AppKitSettingsCardBaseView {
    var onShowShortcutHintChanged: ((Bool) -> Void)?
    var onShowInCommandTabChanged: ((Bool) -> Void)?
    var onThemeModeChanged: ((String) -> Void)?
    var onAppLanguageChanged: ((String) -> Void)?

    private let showShortcutHintSwitch = NSSwitch()
    private let showInCommandTabSwitch = NSSwitch()
    private let themeModeControl = FlowCapsuleSegmentedControl(
        options: AppearanceSettingsCardAppKitView.themeOptions()
    )
    private let appLanguagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let descriptionLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private var isApplyingState = false
    private var currentState: AppearanceSettingsCardState?

    private static func themeOptions() -> [(id: String, title: String)] {
        ThemeMode.allCases.map { (id: $0.rawValue, title: $0.displayName) }
    }

    private static func languageOptions() -> [(id: String, title: String)] {
        AppLanguage.allCases.map { (id: $0.rawValue, title: $0.displayName) }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func update(with state: AppearanceSettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        showShortcutHintSwitch.state = state.showShortcutHint ? .on : .off
        showInCommandTabSwitch.state = state.showInCommandTab ? .on : .off
        themeModeControl.updateSelection(id: state.resolvedThemeMode.rawValue)
        AppKitSettingsCardBaseView.selectItem(
            in: appLanguagePopUp,
            rawValue: state.resolvedAppLanguage.rawValue
        )
        isApplyingState = false

        descriptionLabel.stringValue = AppStrings.text(.appearanceDescription)
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        showShortcutHintSwitch.target = self
        showShortcutHintSwitch.action = #selector(handleShowShortcutHintChanged)
        showInCommandTabSwitch.target = self
        showInCommandTabSwitch.action = #selector(handleShowInCommandTabChanged)
        themeModeControl.translatesAutoresizingMaskIntoConstraints = false
        themeModeControl.onSelectionChanged = { [weak self] rawValue in
            self?.handleThemeModeChanged(rawValue)
        }
        themeModeControl.widthAnchor.constraint(equalToConstant: 300).isActive = true
        AppKitSettingsCardBaseView.configure(
            popUp: appLanguagePopUp,
            options: Self.languageOptions(),
            target: self,
            action: #selector(handleAppLanguageChanged(_:)),
            width: 180
        )

        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.appearanceShowShortcutHint),
                control: showShortcutHintSwitch
            )
        )
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.appearanceShowAppWindow),
                control: showInCommandTabSwitch
            )
        )
        addFullWidthArrangedSubview(descriptionLabel)
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.appearanceThemeMode),
                control: themeModeControl
            )
        )
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.appearanceLanguage),
                control: appLanguagePopUp
            )
        )
    }

    @objc private func handleShowShortcutHintChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowShortcutHintChanged?(sender.state == .on)
    }

    @objc private func handleShowInCommandTabChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowInCommandTabChanged?(sender.state == .on)
    }

    private func handleThemeModeChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onThemeModeChanged?(rawValue)
    }

    @objc private func handleAppLanguageChanged(_ sender: NSPopUpButton) {
        guard !isApplyingState else { return }
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        onAppLanguageChanged?(rawValue)
    }
}

private struct AppKitWindowBehaviorSettingsCardContent: NSViewRepresentable {
    let windowLayerAutoEnterDelayText: String
    @Binding var autoRestoreMinimizedWindowOnSwitch: Bool
    @Binding var hideMinimizedAppsFromAppLayer: Bool
    let onWindowLayerAutoEnterDelayTextChanged: (String) -> Void
    let onWindowLayerAutoEnterDelayTextCommitted: () -> Void
    let onWindowLayerAutoEnterDelayEditingChanged: (Bool) -> Void

    final class Coordinator {
        var autoRestoreMinimizedWindowOnSwitch: Binding<Bool>
        var hideMinimizedAppsFromAppLayer: Binding<Bool>
        var onWindowLayerAutoEnterDelayTextChanged: (String) -> Void
        var onWindowLayerAutoEnterDelayTextCommitted: () -> Void
        var onWindowLayerAutoEnterDelayEditingChanged: (Bool) -> Void

        init(
            autoRestoreMinimizedWindowOnSwitch: Binding<Bool>,
            hideMinimizedAppsFromAppLayer: Binding<Bool>,
            onWindowLayerAutoEnterDelayTextChanged: @escaping (String) -> Void,
            onWindowLayerAutoEnterDelayTextCommitted: @escaping () -> Void,
            onWindowLayerAutoEnterDelayEditingChanged: @escaping (Bool) -> Void
        ) {
            self.autoRestoreMinimizedWindowOnSwitch = autoRestoreMinimizedWindowOnSwitch
            self.hideMinimizedAppsFromAppLayer = hideMinimizedAppsFromAppLayer
            self.onWindowLayerAutoEnterDelayTextChanged = onWindowLayerAutoEnterDelayTextChanged
            self.onWindowLayerAutoEnterDelayTextCommitted = onWindowLayerAutoEnterDelayTextCommitted
            self.onWindowLayerAutoEnterDelayEditingChanged = onWindowLayerAutoEnterDelayEditingChanged
        }

        func update(
            autoRestoreMinimizedWindowOnSwitch: Binding<Bool>,
            hideMinimizedAppsFromAppLayer: Binding<Bool>,
            onWindowLayerAutoEnterDelayTextChanged: @escaping (String) -> Void,
            onWindowLayerAutoEnterDelayTextCommitted: @escaping () -> Void,
            onWindowLayerAutoEnterDelayEditingChanged: @escaping (Bool) -> Void
        ) {
            self.autoRestoreMinimizedWindowOnSwitch = autoRestoreMinimizedWindowOnSwitch
            self.hideMinimizedAppsFromAppLayer = hideMinimizedAppsFromAppLayer
            self.onWindowLayerAutoEnterDelayTextChanged = onWindowLayerAutoEnterDelayTextChanged
            self.onWindowLayerAutoEnterDelayTextCommitted = onWindowLayerAutoEnterDelayTextCommitted
            self.onWindowLayerAutoEnterDelayEditingChanged = onWindowLayerAutoEnterDelayEditingChanged
        }

        func setAutoRestoreMinimizedWindowOnSwitch(_ value: Bool) {
            autoRestoreMinimizedWindowOnSwitch.wrappedValue = value
        }

        func setHideMinimizedAppsFromAppLayer(_ value: Bool) {
            hideMinimizedAppsFromAppLayer.wrappedValue = value
        }

        func changeDelayText(_ value: String) {
            onWindowLayerAutoEnterDelayTextChanged(value)
        }

        func commitDelayText() {
            onWindowLayerAutoEnterDelayTextCommitted()
        }

        func setDelayEditing(_ isEditing: Bool) {
            onWindowLayerAutoEnterDelayEditingChanged(isEditing)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
            onWindowLayerAutoEnterDelayTextChanged: onWindowLayerAutoEnterDelayTextChanged,
            onWindowLayerAutoEnterDelayTextCommitted: onWindowLayerAutoEnterDelayTextCommitted,
            onWindowLayerAutoEnterDelayEditingChanged: onWindowLayerAutoEnterDelayEditingChanged
        )
    }

    func makeNSView(context: Context) -> WindowBehaviorSettingsCardAppKitView {
        let view = WindowBehaviorSettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WindowBehaviorSettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: WindowBehaviorSettingsCardAppKitView, context: Context) {
        context.coordinator.update(
            autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
            onWindowLayerAutoEnterDelayTextChanged: onWindowLayerAutoEnterDelayTextChanged,
            onWindowLayerAutoEnterDelayTextCommitted: onWindowLayerAutoEnterDelayTextCommitted,
            onWindowLayerAutoEnterDelayEditingChanged: onWindowLayerAutoEnterDelayEditingChanged
        )
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: WindowBehaviorSettingsCardState(
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            )
        )
    }

    private func connect(_ view: WindowBehaviorSettingsCardAppKitView, coordinator: Coordinator) {
        view.onWindowLayerAutoEnterDelayTextChanged = { coordinator.changeDelayText($0) }
        view.onWindowLayerAutoEnterDelayTextCommitted = { coordinator.commitDelayText() }
        view.onWindowLayerAutoEnterDelayEditingChanged = { coordinator.setDelayEditing($0) }
        view.onAutoRestoreMinimizedWindowOnSwitchChanged = {
            coordinator.setAutoRestoreMinimizedWindowOnSwitch($0)
        }
        view.onHideMinimizedAppsFromAppLayerChanged = {
            coordinator.setHideMinimizedAppsFromAppLayer($0)
        }
    }
}

private struct WindowBehaviorSettingsCardState: Equatable {
    let windowLayerAutoEnterDelayText: String
    let autoRestoreMinimizedWindowOnSwitch: Bool
    let hideMinimizedAppsFromAppLayer: Bool
}

private final class WindowBehaviorSettingsCardAppKitView: AppKitSettingsCardBaseView, NSTextFieldDelegate {
    var onWindowLayerAutoEnterDelayTextChanged: ((String) -> Void)?
    var onWindowLayerAutoEnterDelayTextCommitted: (() -> Void)?
    var onWindowLayerAutoEnterDelayEditingChanged: ((Bool) -> Void)?
    var onAutoRestoreMinimizedWindowOnSwitchChanged: ((Bool) -> Void)?
    var onHideMinimizedAppsFromAppLayerChanged: ((Bool) -> Void)?

    private let delayInputField = FlowSoftTextField()
    private let autoRestoreMinimizedWindowSwitch = NSSwitch()
    private let hideMinimizedAppsSwitch = NSSwitch()
    private let noteLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private var isApplyingState = false
    private var currentState: WindowBehaviorSettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func containsDelayInputDescendant(_ view: NSView?) -> Bool {
        guard let view else { return false }
        return view.isDescendant(of: delayInputField)
    }

    func ownsDelayInputFirstResponder(_ responder: NSResponder?) -> Bool {
        if let view = responder as? NSView {
            return view.isDescendant(of: delayInputField)
        }

        if let editor = responder as? NSTextView,
            let editedView = editor.delegate as? NSView
        {
            return editedView.isDescendant(of: delayInputField)
        }

        return false
    }

    func update(with state: WindowBehaviorSettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        if delayInputField.textField.stringValue != state.windowLayerAutoEnterDelayText {
            delayInputField.textField.stringValue = state.windowLayerAutoEnterDelayText
        }
        autoRestoreMinimizedWindowSwitch.state = state.autoRestoreMinimizedWindowOnSwitch ? .on : .off
        hideMinimizedAppsSwitch.state = state.hideMinimizedAppsFromAppLayer ? .on : .off
        isApplyingState = false

        noteLabel.stringValue = AppStrings.text(.windowBehaviorNote)
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        let delayTextField = delayInputField.textField
        delayTextField.delegate = self

        let delayUnitLabel = NSTextField(labelWithString: AppStrings.text(.windowBehaviorSecondUnit))
        delayUnitLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        delayUnitLabel.textColor = .secondaryLabelColor

        let delayControl = NSStackView(views: [delayInputField, delayUnitLabel])
        delayControl.orientation = .horizontal
        delayControl.alignment = .centerY
        delayControl.spacing = 8
        delayControl.translatesAutoresizingMaskIntoConstraints = false
        delayControl.setContentHuggingPriority(.required, for: .vertical)
        delayControl.setContentCompressionResistancePriority(.required, for: .vertical)

        autoRestoreMinimizedWindowSwitch.target = self
        autoRestoreMinimizedWindowSwitch.action = #selector(handleAutoRestoreMinimizedWindowSwitchChanged)
        hideMinimizedAppsSwitch.target = self
        hideMinimizedAppsSwitch.action = #selector(handleHideMinimizedAppsSwitchChanged)

        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.windowBehaviorAutoEnterDelay),
                control: delayControl
            )
        )
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.windowBehaviorAutoRestoreMinimized),
                control: autoRestoreMinimizedWindowSwitch
            )
        )
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.windowBehaviorHideMinimizedApps),
                control: hideMinimizedAppsSwitch
            )
        )
        addFullWidthArrangedSubview(noteLabel)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isApplyingState else { return }
        guard notification.object as? NSTextField === delayInputField.textField else { return }
        let rawText = delayInputField.textField.stringValue
        let sanitizedText = WindowLayerPreferencesStore.sanitizeAutoEnterDelayText(rawText)
        if sanitizedText != rawText {
            isApplyingState = true
            delayInputField.textField.stringValue = sanitizedText
            isApplyingState = false
        }
        onWindowLayerAutoEnterDelayTextChanged?(sanitizedText)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === delayInputField.textField else { return }
        delayInputField.setEditing(true)
        onWindowLayerAutoEnterDelayEditingChanged?(true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === delayInputField.textField else { return }
        delayInputField.setEditing(false)
        onWindowLayerAutoEnterDelayEditingChanged?(false)
        onWindowLayerAutoEnterDelayTextCommitted?()
    }

    @objc private func handleAutoRestoreMinimizedWindowSwitchChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onAutoRestoreMinimizedWindowOnSwitchChanged?(sender.state == .on)
    }

    @objc private func handleHideMinimizedAppsSwitchChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onHideMinimizedAppsFromAppLayerChanged?(sender.state == .on)
    }
}

private struct AppKitSearchSettingsCardContent: NSViewRepresentable {
    @Binding var searchEnabled: Bool
    @Binding var searchDefaultScopeRaw: String

    final class Coordinator {
        var searchEnabled: Binding<Bool>
        var searchDefaultScopeRaw: Binding<String>

        init(searchEnabled: Binding<Bool>, searchDefaultScopeRaw: Binding<String>) {
            self.searchEnabled = searchEnabled
            self.searchDefaultScopeRaw = searchDefaultScopeRaw
        }

        func update(searchEnabled: Binding<Bool>, searchDefaultScopeRaw: Binding<String>) {
            self.searchEnabled = searchEnabled
            self.searchDefaultScopeRaw = searchDefaultScopeRaw
        }

        func setSearchEnabled(_ value: Bool) {
            searchEnabled.wrappedValue = value
        }

        func setSearchDefaultScope(rawValue: String) {
            searchDefaultScopeRaw.wrappedValue = rawValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(searchEnabled: $searchEnabled, searchDefaultScopeRaw: $searchDefaultScopeRaw)
    }

    func makeNSView(context: Context) -> SearchSettingsCardAppKitView {
        let view = SearchSettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SearchSettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: SearchSettingsCardAppKitView, context: Context) {
        context.coordinator.update(searchEnabled: $searchEnabled, searchDefaultScopeRaw: $searchDefaultScopeRaw)
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: SearchSettingsCardState(
                searchEnabled: searchEnabled,
                searchDefaultScopeRaw: searchDefaultScopeRaw
            )
        )
    }

    private func connect(_ view: SearchSettingsCardAppKitView, coordinator: Coordinator) {
        view.onSearchEnabledChanged = { coordinator.setSearchEnabled($0) }
        view.onSearchDefaultScopeChanged = { coordinator.setSearchDefaultScope(rawValue: $0) }
    }
}

private struct SearchSettingsCardState: Equatable {
    let searchEnabled: Bool
    let searchDefaultScopeRaw: String

    var resolvedScope: SwitcherSearchScope {
        SwitcherSearchScope(rawValue: searchDefaultScopeRaw) ?? SearchInteractionPreferencesStore.defaultScope
    }

    var summaryText: String {
        searchEnabled
            ? AppStrings.text(.searchSummaryEnabled)
            : AppStrings.text(.searchSummaryDisabled)
    }
}

private final class SearchSettingsCardAppKitView: AppKitSettingsCardBaseView {
    var onSearchEnabledChanged: ((Bool) -> Void)?
    var onSearchDefaultScopeChanged: ((String) -> Void)?

    private let searchEnabledSwitch = NSSwitch()
    private let searchDefaultScopePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scopeRowContainer = NSStackView()
    private let summaryLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private var isApplyingState = false
    private var currentState: SearchSettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func update(with state: SearchSettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        searchEnabledSwitch.state = state.searchEnabled ? .on : .off
        AppKitSettingsCardBaseView.selectItem(
            in: searchDefaultScopePopUp,
            rawValue: state.resolvedScope.rawValue
        )
        isApplyingState = false

        searchDefaultScopePopUp.isEnabled = state.searchEnabled
        scopeRowContainer.alphaValue = state.searchEnabled ? 1 : 0.5
        summaryLabel.stringValue = state.summaryText
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        searchEnabledSwitch.target = self
        searchEnabledSwitch.action = #selector(handleSearchEnabledChanged)
        AppKitSettingsCardBaseView.configure(
            popUp: searchDefaultScopePopUp,
            options: SwitcherSearchScope.allCases.map { (id: $0.rawValue, title: $0.label) },
            target: self,
            action: #selector(handleSearchDefaultScopeChanged)
        )

        let searchEnabledRow = AppKitSettingsCardBaseView.makeControlRow(
            title: AppStrings.text(.searchEnable),
            control: searchEnabledSwitch
        )
        scopeRowContainer.orientation = .vertical
        scopeRowContainer.alignment = .leading
        scopeRowContainer.spacing = 0
        scopeRowContainer.detachesHiddenViews = true
        scopeRowContainer.translatesAutoresizingMaskIntoConstraints = false
        scopeRowContainer.setContentHuggingPriority(.required, for: .vertical)
        scopeRowContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        scopeRowContainer.addArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.searchDefaultScope),
                control: searchDefaultScopePopUp
            )
        )
        if let scopeRow = scopeRowContainer.arrangedSubviews.first {
            scopeRow.widthAnchor.constraint(equalTo: scopeRowContainer.widthAnchor).isActive = true
        }

        addFullWidthArrangedSubview(searchEnabledRow)
        addFullWidthArrangedSubview(scopeRowContainer)
        addFullWidthArrangedSubview(summaryLabel)
    }

    @objc private func handleSearchEnabledChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onSearchEnabledChanged?(sender.state == .on)
    }

    @objc private func handleSearchDefaultScopeChanged(_ sender: NSPopUpButton) {
        guard !isApplyingState else { return }
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        onSearchDefaultScopeChanged?(rawValue)
    }
}

private struct AppKitPermissionSettingsCardContent: NSViewRepresentable {
    @Binding var showPermissionReminder: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let onAccessibilityAction: () -> Void
    let onScreenCaptureAction: () -> Void

    final class Coordinator {
        var showPermissionReminder: Binding<Bool>
        var onAccessibilityAction: () -> Void
        var onScreenCaptureAction: () -> Void

        init(
            showPermissionReminder: Binding<Bool>,
            onAccessibilityAction: @escaping () -> Void,
            onScreenCaptureAction: @escaping () -> Void
        ) {
            self.showPermissionReminder = showPermissionReminder
            self.onAccessibilityAction = onAccessibilityAction
            self.onScreenCaptureAction = onScreenCaptureAction
        }

        func update(
            showPermissionReminder: Binding<Bool>,
            onAccessibilityAction: @escaping () -> Void,
            onScreenCaptureAction: @escaping () -> Void
        ) {
            self.showPermissionReminder = showPermissionReminder
            self.onAccessibilityAction = onAccessibilityAction
            self.onScreenCaptureAction = onScreenCaptureAction
        }

        func setShowPermissionReminder(_ value: Bool) {
            showPermissionReminder.wrappedValue = value
        }

        func triggerAccessibilityAction() {
            onAccessibilityAction()
        }

        func triggerScreenCaptureAction() {
            onScreenCaptureAction()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            showPermissionReminder: $showPermissionReminder,
            onAccessibilityAction: onAccessibilityAction,
            onScreenCaptureAction: onScreenCaptureAction
        )
    }

    func makeNSView(context: Context) -> PermissionSettingsCardAppKitView {
        let view = PermissionSettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: PermissionSettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: PermissionSettingsCardAppKitView, context: Context) {
        context.coordinator.update(
            showPermissionReminder: $showPermissionReminder,
            onAccessibilityAction: onAccessibilityAction,
            onScreenCaptureAction: onScreenCaptureAction
        )
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: PermissionSettingsCardState(
                showPermissionReminder: showPermissionReminder,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted
            )
        )
    }

    private func connect(_ view: PermissionSettingsCardAppKitView, coordinator: Coordinator) {
        view.onShowPermissionReminderChanged = { coordinator.setShowPermissionReminder($0) }
        view.onAccessibilityAction = { coordinator.triggerAccessibilityAction() }
        view.onScreenCaptureAction = { coordinator.triggerScreenCaptureAction() }
    }
}

private struct PermissionSettingsCardState: Equatable {
    let showPermissionReminder: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool

    var accessibilityStatusText: String {
        accessibilityTrusted
            ? AppStrings.text(.permissionAccessibilityGranted)
            : AppStrings.text(.permissionAccessibilityDenied)
    }

    var accessibilityButtonTitle: String {
        accessibilityTrusted
            ? AppStrings.text(.permissionAccessibilityClose)
            : AppStrings.text(.permissionAccessibilityRequest)
    }

    var screenCaptureStatusText: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenGranted)
            : AppStrings.text(.permissionScreenDenied)
    }

    var screenCaptureButtonTitle: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenClose)
            : AppStrings.text(.permissionScreenRequest)
    }
}

private final class PermissionStatusActionRowView: NSView {
    let titleLabel = AppKitSettingsCardBaseView.makeStatusLabel()
    let detailLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    let actionButton: FlowGradientActionButton
    private let stackView = NSStackView()
    private let textStack = NSStackView()

    override init(frame frameRect: NSRect) {
        actionButton = FlowGradientActionButton()
        super.init(frame: .zero)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        actionButton = FlowGradientActionButton()
        super.init(coder: coder)
        buildViewHierarchy()
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.detachesHiddenViews = true
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 10
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(stackView)
        stackView.addArrangedSubview(textStack)
        stackView.addArrangedSubview(spacer)
        stackView.addArrangedSubview(actionButton)
        actionButton.widthAnchor.constraint(equalToConstant: 166).isActive = true

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    func update(text: String, detail: String, isGranted: Bool, buttonTitle: String) {
        titleLabel.stringValue = text
        titleLabel.textColor = isGranted ? .systemGreen : .systemOrange
        detailLabel.stringValue = detail
        actionButton.update(
            title: buttonTitle,
            tone: isGranted ? .blueDominant : .grayDominant
        )
    }
}

private final class PermissionSettingsCardAppKitView: AppKitSettingsCardBaseView {
    var onShowPermissionReminderChanged: ((Bool) -> Void)?
    var onAccessibilityAction: (() -> Void)?
    var onScreenCaptureAction: (() -> Void)?

    private let showPermissionReminderSwitch = NSSwitch()
    private let accessibilityRow: PermissionStatusActionRowView
    private let screenCaptureRow: PermissionStatusActionRowView
    private var isApplyingState = false
    private var currentState: PermissionSettingsCardState?

    override init(frame frameRect: NSRect) {
        accessibilityRow = PermissionStatusActionRowView()
        screenCaptureRow = PermissionStatusActionRowView()
        super.init(frame: frameRect)
        accessibilityRow.actionButton.target = self
        accessibilityRow.actionButton.action = #selector(handleAccessibilityAction)
        screenCaptureRow.actionButton.target = self
        screenCaptureRow.actionButton.action = #selector(handleScreenCaptureAction)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        accessibilityRow = PermissionStatusActionRowView()
        screenCaptureRow = PermissionStatusActionRowView()
        super.init(coder: coder)
        accessibilityRow.actionButton.target = self
        accessibilityRow.actionButton.action = #selector(handleAccessibilityAction)
        screenCaptureRow.actionButton.target = self
        screenCaptureRow.actionButton.action = #selector(handleScreenCaptureAction)
        buildViewHierarchy()
    }

    func update(with state: PermissionSettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        showPermissionReminderSwitch.state = state.showPermissionReminder ? .on : .off
        isApplyingState = false

        accessibilityRow.update(
            text: state.accessibilityStatusText,
            detail: AppStrings.text(.permissionAccessibilityDetail),
            isGranted: state.accessibilityTrusted,
            buttonTitle: state.accessibilityButtonTitle
        )
        screenCaptureRow.update(
            text: state.screenCaptureStatusText,
            detail: AppStrings.text(.permissionScreenDetail),
            isGranted: state.screenCaptureTrusted,
            buttonTitle: state.screenCaptureButtonTitle
        )
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        showPermissionReminderSwitch.target = self
        showPermissionReminderSwitch.action = #selector(handleShowPermissionReminderChanged)

        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.permissionHomeReminderToggle),
                control: showPermissionReminderSwitch
            )
        )
        addFullWidthArrangedSubview(accessibilityRow)
        addFullWidthArrangedSubview(screenCaptureRow)
    }

    @objc private func handleShowPermissionReminderChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowPermissionReminderChanged?(sender.state == .on)
    }

    @objc private func handleAccessibilityAction() {
        onAccessibilityAction?()
    }

    @objc private func handleScreenCaptureAction() {
        onScreenCaptureAction?()
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
                        Text(AppStrings.text(.logsPageTitle))
                            .font(.system(size: 22, weight: .semibold))
                        Text(AppStrings.text(.logsPageSubtitle))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    RuntimeLogsSection(
                        enableVerboseDiagnostics: $enableVerboseDiagnostics,
                        runtimeLogLevelRaw: $runtimeLogLevelRaw,
                        hotkeyShortcutText: hotkeyConfiguration.mainShortcutText
                    )
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
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue
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
    @State private var hasAttemptedScreenCapturePermissionRequest = false
    @State private var accessibilityPermissionPollTask: Task<Void, Never>?
    @State private var screenCapturePollTask: Task<Void, Never>?
    @State private var windowLayerAutoEnterDelayText = ""
    @State private var didInitialize = false
    @State private var isWindowLayerAutoEnterDelayEditing = false

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

    private var windowLayerAutoEnterDelay: Double {
        WindowLayerPreferencesStore.normalizedAutoEnterDelay(windowLayerAutoEnterDelayRaw)
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            AppKitSettingsPageContent(
                isActive: isActive,
                showShortcutHint: $showShortcutHint,
                showInCommandTab: $showInCommandTab,
                themeModeRaw: $themeModeRaw,
                appLanguageRaw: $appLanguageRaw,
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
                showPermissionReminder: $showPermissionReminder,
                searchEnabled: $searchEnabled,
                searchDefaultScopeRaw: $searchDefaultScopeRaw,
                hotkeyPrimaryModifierRaw: $hotkeyPrimaryModifierRaw,
                hotkeyMainKeyRaw: $hotkeyMainKeyRaw,
                hotkeyQuitKeyRaw: $hotkeyQuitKeyRaw,
                inAppWindowHotkeyPrimaryModifierRaw: $inAppWindowHotkeyPrimaryModifierRaw,
                inAppWindowHotkeyMainKeyRaw: $inAppWindowHotkeyMainKeyRaw,
                commandTabTakeoverActive: commandTabTakeoverActive,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted,
                onWindowLayerAutoEnterDelayTextChanged: applyWindowLayerAutoEnterDelayText,
                onWindowLayerAutoEnterDelayTextCommitted: commitWindowLayerAutoEnterDelayText,
                onWindowLayerAutoEnterDelayEditingChanged: {
                    isWindowLayerAutoEnterDelayEditing = $0
                },
                onAccessibilityAction: {
                    if accessibilityTrusted {
                        openAccessibilityPrivacySettings()
                    } else {
                        requestAccessibilityPermission()
                    }
                },
                onScreenCaptureAction: {
                    if screenCaptureTrusted {
                        openScreenCapturePrivacySettings()
                    } else {
                        requestScreenCapturePermission()
                    }
                }
            )
            .id(appLanguageRaw)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .onChange(of: appLanguageRaw) {
            enforceLanguageConsistency()
            notifyLanguagePreferenceChanged()
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
        .onChange(of: windowLayerAutoEnterDelayRaw) {
            enforceWindowLayerPreferencesConsistency()
            if !isWindowLayerAutoEnterDelayEditing {
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
            enforceLanguageConsistency()
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
            // Screen capture prompts are often one-shot after denial; keep first click as request, then route later clicks.
            if hasAttemptedScreenCapturePermissionRequest {
                presentScreenCapturePermissionReminder()
            } else {
                hasAttemptedScreenCapturePermissionRequest = true
            }
            startScreenCapturePermissionPolling()
        } else {
            hasAttemptedScreenCapturePermissionRequest = false
        }
    }

    private func presentScreenCapturePermissionReminder() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppStrings.text(.alertScreenDeniedTitle)
        alert.informativeText = AppStrings.text(.alertScreenDeniedMessage)
        alert.addButton(withTitle: AppStrings.text(.alertOpenSystemSettings))
        alert.addButton(withTitle: AppStrings.text(.alertLater))
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenCapturePrivacySettings()
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

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    private func refreshScreenCaptureStatus() {
        let trusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
        screenCaptureTrusted = trusted
        if trusted {
            hasAttemptedScreenCapturePermissionRequest = false
        }
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

    private func enforceLanguageConsistency() {
        let resolved = AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
        if appLanguageRaw != resolved.rawValue {
            appLanguageRaw = resolved.rawValue
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
        let sanitized = WindowLayerPreferencesStore.sanitizeAutoEnterDelayText(rawText)
        if windowLayerAutoEnterDelayText != sanitized {
            windowLayerAutoEnterDelayText = sanitized
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
        let sanitized = WindowLayerPreferencesStore.sanitizeAutoEnterDelayText(
            windowLayerAutoEnterDelayText
        )
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

    private func notifyLanguagePreferenceChanged() {
        RuntimeLog.info("App", "language=\(appLanguageRaw)")
        NotificationCenter.default.post(name: .flowTabLanguagePreferenceChanged, object: nil)
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
        HomeSectionCard(
            title: AppStrings.text(.logsSectionTitle),
            subtitle: AppStrings.text(.logsSectionSubtitle)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(AppStrings.text(.logsEnableVerbose), isOn: $enableVerboseDiagnostics)
                    .toggleStyle(.switch)
                    .font(.system(size: 12))

                HStack(spacing: 10) {
                    Text(AppStrings.text(.logsLevel))
                        .font(.system(size: 12))
                    Picker(AppStrings.text(.logsLevel), selection: $runtimeLogLevelRaw) {
                        ForEach(RuntimeLogLevel.allCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                Text(
                    AppStrings.text(
                        .logsDirectory,
                        replacements: ["path": RuntimeDiagnostics.logsDirectoryPath]
                    )
                )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button(AppStrings.text(.logsOpenDirectory)) {
                        openLogsDirectory()
                    }
                    .buttonStyle(LogsActionButtonStyle(tint: logsActionButtonTint))

                    Button(AppStrings.text(.logsClear)) {
                        logsViewModel.clearDisplayedOutput(minimumLevel: selectedLogLevel)
                    }
                    .buttonStyle(LogsActionButtonStyle(tint: logsActionButtonTint))
                }

                ScrollView {
                    Group {
                        if logsViewModel.lines.isEmpty {
                            Text(
                                AppStrings.text(
                                    .logsEmptyHint,
                                    replacements: ["hotkey": hotkeyShortcutText]
                                )
                            )
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
    private var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicyFromPreferences()

        let panelController = SwitcherPanelController()
        self.panelController = panelController

        setupHotkeyMonitor()
        setupInAppWindowHotkeyMonitor()
        installHotkeyObserver()
        installAppVisibilityObserver()
        installLanguageObserver()

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
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
            self.languageObserver = nil
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

    private func installLanguageObserver() {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
        languageObserver = NotificationCenter.default.addObserver(
            forName: .flowTabLanguagePreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.installStatusItem()
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
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.length = NSStatusItem.squareLength
        item.menu = nil
        if let button = item.button {
            let icon = (NSImage(named: "MenuBarIcon")?.copy() as? NSImage)
                ?? (NSApp.applicationIconImage.copy() as? NSImage)
                ?? NSImage(named: NSImage.applicationIconName)
                ?? NSImage()
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            button.title = ""
            button.image = icon
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("FlowTab")
            button.target = self
            button.action = #selector(openAppFromStatusItem)
            button.sendAction(on: [.leftMouseUp])
        }
        statusItem = item
    }

    @objc
    private func openAppFromStatusItem() {
        handleStatusItemOpenAction(application: NSApp)
    }

    func handleStatusItemOpenAction(application: any AppWindowOpeningApplication) {
        AppWindowCoordinator.activateMainWindowOrOpenHomeScene(application: application)
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
        let rawName = (displayName?.isEmpty == false ? displayName : bundleName) ?? "FlowTab"
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
        logsDirectoryURL = baseURL.appendingPathComponent("FlowTab/logs", isDirectory: true)
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
