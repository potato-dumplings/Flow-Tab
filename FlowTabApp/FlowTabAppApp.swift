import SwiftUI
import AppKit
import ApplicationServices

enum AppPreferenceKeys {
    static let showShortcutHint = "showShortcutHint"
    static let hasPromptedAccessibilityPermission = "hasPromptedAccessibilityPermission"
    static let hotkeyPrimaryModifier = "hotkeyPrimaryModifier"
    static let hotkeyMainKey = "hotkeyMainKey"
    static let hotkeyQuitKey = "hotkeyQuitKey"
}

extension Notification.Name {
    static let flowTabReRegisterHotkeys = Notification.Name("FlowTab.ReRegisterHotkeys")
}

enum HomeTab: Hashable {
    case home
    case monitor
    case previewLogs
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

    static func openMonitor() {
        Task { @MainActor in
            if HomeTabState.shared.selectedTab != .monitor {
                HomeTabState.shared.selectedTab = .monitor
            }
            activateMainWindowOrOpenHomeScene()
        }
    }

    static func openPreviewLogs() {
        Task { @MainActor in
            if HomeTabState.shared.selectedTab != .previewLogs {
                HomeTabState.shared.selectedTab = .previewLogs
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
                SettingsLink {
                    Text("打开应用首页")
                }
            }

            CommandMenu("FlowTab") {
                Button("打开应用首页") {
                    AppWindowCoordinator.openHome()
                }
                Button("查看日志监控") {
                    AppWindowCoordinator.openMonitor()
                }
                Button("查看预览日志") {
                    AppWindowCoordinator.openPreviewLogs()
                }
            }
        }
    }
}

private struct HomeRootView: View {
    @ObservedObject private var tabState = HomeTabState.shared

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(selectedTab: $tabState.selectedTab)

            Divider()
                .overlay(Color.white.opacity(0.08))

            Group {
                switch tabState.selectedTab {
                case .home:
                    HomeLandingView()
                case .monitor:
                    AppSettingsView()
                case .previewLogs:
                    PreviewLogView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeSidebar: View {
    @Binding var selectedTab: HomeTab
    private let textColumnWidth: CGFloat = 120

    private let items: [(tab: HomeTab, title: String, icon: String)] = [
        (.home, "首页", "house.fill"),
        (.monitor, "监控页面", "waveform.path.ecg"),
        (.previewLogs, "预览日志", "photo.stack")
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.98),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .center, spacing: 22) {
                HStack(alignment: .center, spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FlowTab")
                            .font(.system(size: 22, weight: .bold))
                            .lineLimit(1)

                        Text("工作台")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)

                VStack(alignment: .center, spacing: 14) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
        .frame(width: 240)
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: textColumnWidth, alignment: .leading)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.92))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.52)
                            : Color.white.opacity(0.001)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 1.1 : 0.8
                    )
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
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.09),
                    Color.clear,
                    Color(nsColor: .underPageBackgroundColor).opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
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

private struct AppSettingsView: View {
    @AppStorage(AppPreferenceKeys.showShortcutHint) private var showShortcutHint = true
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
    @ObservedObject private var diagnostics = RuntimeDiagnostics.shared
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var accessibilityPermissionPollTask: Task<Void, Never>?
    @State private var screenCapturePollTask: Task<Void, Never>?

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

    var body: some View {
        ZStack {
            HomeBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("监控页面")
                            .font(.system(size: 22, weight: .semibold))
                        Text("统一视觉风格下的运行诊断面板")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HomeSectionCard(title: "偏好", subtitle: "基础显示设置与快捷键") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("显示快捷键提示", isOn: $showShortcutHint)
                                .toggleStyle(.switch)
                                .font(.system(size: 13))

                            Divider()

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

                    HomeSectionCard(title: "运行与权限", subtitle: "辅助功能、屏幕录制、快照与日志") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(accessibilityTrusted ? "辅助功能权限：已授权" : "辅助功能权限：未授权")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(
                                            accessibilityTrusted
                                                ? Color.green.opacity(0.14)
                                                : Color.orange.opacity(0.16)
                                        )
                                )
                                .foregroundStyle(accessibilityTrusted ? .green : .orange)

                            Text(screenCaptureTrusted ? "屏幕录制权限：已授权" : "屏幕录制权限：未授权")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(
                                            screenCaptureTrusted
                                                ? Color.green.opacity(0.14)
                                                : Color.orange.opacity(0.16)
                                        )
                                )
                                .foregroundStyle(screenCaptureTrusted ? .green : .orange)

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    openAccessibilityButton
                                    requestAccessibilityPermissionButton
                                    openScreenCaptureButton
                                    requestScreenCaptureButton
                                    captureSnapshotButton
                                    clearLogsButton
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        openAccessibilityButton
                                        requestAccessibilityPermissionButton
                                    }
                                    HStack(spacing: 8) {
                                        openScreenCaptureButton
                                        requestScreenCaptureButton
                                    }
                                    HStack(spacing: 8) {
                                        captureSnapshotButton
                                        clearLogsButton
                                    }
                                }
                            }

                            Text("当前实例 bundle: \(bundleIdentifier)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text("当前实例路径: \(bundlePath)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)

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

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    if diagnostics.entries.isEmpty {
                                        Text("暂无日志。触发 \(hotkeyConfiguration.mainShortcutText) 后再回来看。")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        ForEach(diagnostics.entries) { entry in
                                            Text(
                                                "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] "
                                                    + "[\(entry.category)] \(entry.message)"
                                            )
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                        }
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
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            enforceHotkeyConsistency()
            refreshAccessibilityStatus()
            refreshScreenCaptureStatus()
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
        .onDisappear {
            accessibilityPermissionPollTask?.cancel()
            screenCapturePollTask?.cancel()
        }
    }

    private var openAccessibilityButton: some View {
        Button("打开辅助功能设置") {
            guard
                let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
            else { return }
            NSWorkspace.shared.open(url)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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

    private var openScreenCaptureButton: some View {
        Button("打开屏幕录制设置") {
            guard
                let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )
            else { return }
            NSWorkspace.shared.open(url)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var requestScreenCaptureButton: some View {
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

    private var captureSnapshotButton: some View {
        Button("采集当前快照") {
            let snapshot = RuntimeSnapshotProvider().snapshot()
            RuntimeLog.info("Manual", "snapshot apps=\(snapshot.apps.count)")
            for app in snapshot.apps.prefix(16) {
                RuntimeLog.info(
                    "Manual",
                    "\(app.displayName) windows=\(app.windows.count)"
                )
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

private struct PreviewLogView: View {
    @ObservedObject private var diagnostics = RuntimeDiagnostics.shared
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission

    private var previewEntries: [RuntimeDiagnostics.Entry] {
        diagnostics.entries.filter { entry in
            entry.category.caseInsensitiveCompare("Preview") == .orderedSame
        }
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("预览日志")
                        .font(.system(size: 22, weight: .semibold))
                    Text("窗口预览链路专用日志（权限、窗口匹配、抓图结果）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HomeSectionCard(title: "屏幕录制权限", subtitle: "预览功能依赖该权限") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(screenCaptureTrusted ? "屏幕录制权限：已授权" : "屏幕录制权限：未授权")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        screenCaptureTrusted
                                            ? Color.green.opacity(0.14)
                                            : Color.orange.opacity(0.16)
                                    )
                            )
                            .foregroundStyle(screenCaptureTrusted ? .green : .orange)

                        HStack(spacing: 8) {
                            Button("打开屏幕录制设置") {
                                guard
                                    let url = URL(
                                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                                    )
                                else { return }
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("请求屏幕录制权限") {
                                let trusted = ScreenCapturePermissionChecker.requestScreenCapturePermission()
                                RuntimeLog.info("Preview", "screenCapture prompt requested immediateTrusted=\(trusted)")
                                refreshScreenCaptureStatus()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("清空全部日志") {
                                diagnostics.clear()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                HomeSectionCard(title: "预览日志流", subtitle: "仅显示 Preview 分类，最近 \(previewEntries.count) 条") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if previewEntries.isEmpty {
                                Text("暂无预览日志。进入窗口层后会在这里显示抓图链路信息。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(previewEntries) { entry in
                                    Text(
                                        "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] "
                                            + "[\(entry.category)] \(entry.message)"
                                    )
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(minHeight: 360)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshScreenCaptureStatus()
        }
    }

    private func refreshScreenCaptureStatus() {
        screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: SwitcherPanelController?
    private var hotkeyMonitor: OptionTabHotkeyMonitor?
    private var statusItem: NSStatusItem?
    private var hotkeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = SwitcherPanelController()
        self.panelController = panelController

        setupHotkeyMonitor()
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
        RuntimeLog.info(
            "HotKey",
            "register main=\(hotkeyConfiguration.mainShortcutText) backward=\(hotkeyConfiguration.backwardShortcutText) quit=\(hotkeyConfiguration.quitShortcutText)"
        )
        hotkeyMonitor = monitor
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

        let openMonitorItem = NSMenuItem(
            title: "查看日志监控",
            action: #selector(openMonitorFromMenu),
            keyEquivalent: ""
        )
        openMonitorItem.target = self
        menu.addItem(openMonitorItem)

        let openPreviewLogsItem = NSMenuItem(
            title: "查看预览日志",
            action: #selector(openPreviewLogsFromMenu),
            keyEquivalent: ""
        )
        openPreviewLogsItem.target = self
        menu.addItem(openPreviewLogsItem)

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
    private func openHomeFromMenu() {
        AppWindowCoordinator.openHome()
    }

    @objc
    private func openMonitorFromMenu() {
        AppWindowCoordinator.openMonitor()
    }

    @objc
    private func openPreviewLogsFromMenu() {
        AppWindowCoordinator.openPreviewLogs()
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
    }

    static let shared = RuntimeDiagnostics()

    @Published private(set) var entries: [Entry] = []
    private let maxEntries = 800

    private init() {}

    func log(category: String, message: String) {
        entries.append(
            Entry(
                timestamp: Date(),
                category: category,
                message: message
            )
        )

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

enum RuntimeLog {
    static func info(_ category: String, _ message: @autoclosure @escaping () -> String) {
        DispatchQueue.main.async {
            RuntimeDiagnostics.shared.log(category: category, message: message())
        }
    }
}
