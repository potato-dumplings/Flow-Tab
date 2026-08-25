import SwiftUI
import AppKit
import FlowTabCore

@MainActor
struct HomeRootView: View {
    @ObservedObject private var tabState = HomeTabState.shared
    @ObservedObject private var presentation = FlowPresentationState.shared
    @ObservedObject private var updatePresentation:
        FlowTabUpdatePresentationStore
    @StateObject private var appVisibilityModel: AppVisibilityManagerModel
    private let runtimeProjectionService: any RuntimeProjectionServing

    init(
        runtimeProjectionService: any RuntimeProjectionServing = homeRuntimeProjectionService,
        appVisibilityModel: AppVisibilityManagerModel? = nil,
        updatePresentation: FlowTabUpdatePresentationStore? = nil
    ) {
        self.runtimeProjectionService = runtimeProjectionService
        _updatePresentation = ObservedObject(
            wrappedValue: updatePresentation ?? .shared
        )
        _appVisibilityModel = StateObject(
            wrappedValue: appVisibilityModel ?? AppVisibilityManagerModel()
        )
    }

    private var dividerColor: Color {
        presentation.context.resolvedColorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.12)
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
            HomeSidebar(
                selectedTab: $tabState.selectedTab,
                presentationContext: presentation.context,
                updateAvailability: updatePresentation.availability,
                showAvailableUpdate: updatePresentation.showAvailableUpdate
            )

            Divider()
                .overlay(dividerColor)

            ZStack {
                tabContainer(isSelected: tabState.selectedTab == .home) {
                    HomeLandingView(
                        isActive: tabState.selectedTab == .home,
                        appLanguage: presentation.context.appLanguage,
                        runtimeProjectionService: runtimeProjectionService,
                        installedApps: appVisibilityModel.apps,
                        effectiveHiddenAppIDs:
                            appVisibilityModel.effectiveHiddenAppIDs
                    ) {
                        tabState.selectedTab = .settings
                    }
                }
                tabContainer(isSelected: tabState.selectedTab == .logs) {
                    AppLogsView(
                        isActive: tabState.selectedTab == .logs,
                        appLanguage: presentation.context.appLanguage,
                        targetAppearance: presentation.context.targetNSAppearance
                    )
                }
                tabContainer(isSelected: tabState.selectedTab == .settings) {
                    AppSettingsView(
                        isActive: tabState.selectedTab == .settings,
                        appVisibilityModel: appVisibilityModel
                    )
                        .id(
                            "settings-\(presentation.context.appearanceRebuildIdentity)"
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(presentation.context.resolvedColorScheme)
        .animation(.none, value: presentation.context.resolvedColorScheme)
        .onAppear {
            appVisibilityModel.reload()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            appVisibilityModel.reload()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )) { _ in
            appVisibilityModel.reload()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )) { _ in
            appVisibilityModel.reload()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .flowTabAppVisibilityPreferenceChanged
        )) { _ in
            appVisibilityModel.refreshStoredPreferences()
        }
    }
}

private struct HomeSidebar: View {
    @Binding var selectedTab: HomeTab
    let presentationContext: FlowPresentationContext
    let updateAvailability: FlowTabUpdateAvailability
    let showAvailableUpdate: @MainActor () -> Void
    @State private var accessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var isUpdateButtonHovered = false
    private let navIconColumnWidth: CGFloat = 24
    private let navItemSpacing: CGFloat = 15

    private var colorScheme: ColorScheme {
        presentationContext.resolvedColorScheme
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
        presentationContext.appLanguage
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
                HStack(alignment: .center, spacing: 0) {
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

                    Spacer(minLength: 4)

                    availableUpdateButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("flowtab.sidebar.header")

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
                    language: appLanguage,
                    colorScheme: colorScheme
                )
            }
            .padding(.horizontal, 10)
            .padding(.top, 17)
            .padding(.bottom, FlowPageLayout.bottomInset)
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
    private var availableUpdateButton: some View {
        if let update = updateAvailability.availableUpdate {
            Button {
                Task { @MainActor in
                    showAvailableUpdate()
                }
            } label: {
                ZStack {
                    Image(systemName: "arrow.down.to.line")
                        .imageScale(.small)
                        .opacity(isUpdateButtonHovered ? 0 : 1)
                        .scaleEffect(isUpdateButtonHovered ? 0.75 : 1)

                    Text(
                        AppStrings.text(
                            .updateButtonTitle,
                            language: appLanguage
                        )
                    )
                    .font(FlowTypography.swiftUI(.microEmphasized))
                    .opacity(isUpdateButtonHovered ? 1 : 0)
                    .scaleEffect(isUpdateButtonHovered ? 1 : 0.85)
                }
                .foregroundStyle(Color.white)
                .frame(
                    width: isUpdateButtonHovered
                        ? HomeSidebarUpdateLayout.expandedButtonWidth
                        : HomeSidebarUpdateLayout.updateButtonDiameter,
                    height: HomeSidebarUpdateLayout.updateButtonDiameter
                )
                .background(
                    Capsule().fill(Color(nsColor: .systemBlue))
                )
                .clipShape(Capsule())
                .animation(
                    HomeSidebarUpdateLayout.hoverAnimation,
                    value: isUpdateButtonHovered
                )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .onHover { isHovered in
                isUpdateButtonHovered = isHovered
            }
            .accessibilityIdentifier("flowtab.sidebar.update.download")
            .accessibilityLabel(
                AppStrings.text(
                    .updateDownloadVersion,
                    replacements: ["version": update.displayVersion],
                    language: appLanguage
                )
            )
            .accessibilityValue(
                isUpdateButtonHovered
                    ? AppStrings.text(
                        .updateButtonTitle,
                        language: appLanguage
                    )
                    : ""
            )
            .help(
                AppStrings.text(
                    .updateDownloadHelp,
                    replacements: ["version": update.displayVersion],
                    language: appLanguage
                )
            )
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
