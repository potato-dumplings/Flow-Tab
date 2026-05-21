import SwiftUI
import AppKit
import FlowTabCore

struct HomeRootView: View {
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
    @State private var accessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    private let navIconColumnWidth: CGFloat = 24
    private let navItemSpacing: CGFloat = 15

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
            ? Color.accentColor.opacity(0.32)
            : Color(red: 0.78, green: 0.85, blue: 0.97)
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

    private func refreshPermissionStatus() {
        accessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
        screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    }

    var body: some View {
        ZStack {
            sidebarBackgroundColor

            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .center, spacing: 9) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 0) {
                        Text("FlowTab")
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)

                VStack(alignment: .leading, spacing: 7) {
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

                HomePermissionStatusCard(
                    accessibilityTrusted: accessibilityTrusted,
                    screenCaptureTrusted: screenCaptureTrusted,
                    language: appLanguage
                )
            }
            .padding(.horizontal, 10)
            .padding(.top, 17)
            .padding(.bottom, HomePageLayout.bottomInset)
        }
        .frame(width: 200)
        .onAppear {
            refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            refreshPermissionStatus()
        }
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
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: navIconColumnWidth)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(appLanguage == .english ? 0 : 3)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? selectedItemForegroundColor : normalItemForegroundColor)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 47, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? selectedItemBackgroundColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(sidebarButtonIdentifier(for: tab))
    }
}
