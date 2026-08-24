import SwiftUI

@MainActor
struct HomeAppLayerItemView: View {
    let app: HomeAppRowPresentation
    let isSelected: Bool
    let isWindowCountLoading: Bool
    let appLanguage: AppLanguage
    let onSelect: () -> Void

    private var appIDComponent: String {
        app.appID.flowTabAccessibilityIdentifierComponent
    }

    private var accessibilityIdentifier: String {
        "flowtab.home.app.\(appIDComponent)"
    }

    private var hiddenBadge: String? {
        app.isHidden
            ? AppStrings.text(.appVisibilityHiddenBadge, language: appLanguage)
            : nil
    }

    private var accessibilityLabel: String {
        hiddenBadge.map { "\(app.displayName) \($0)" } ?? app.displayName
    }

    private var accessibilityValue: String {
        if isWindowCountLoading {
            return app.isHidden ? "loading hidden" : "loading"
        }
        return app.isHidden ? "\(app.windowCount)w hidden" : "\(app.windowCount)w"
    }

    var body: some View {
        if app.hasRuntimeProjection {
            Button(action: onSelect) {
                rowContent
            }
            .buttonStyle(.plain)
            .frame(height: HomePageLayout.appLayerRowHeight)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
        } else {
            rowContent
                .frame(height: HomePageLayout.appLayerRowHeight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
        }
    }

    private var rowContent: some View {
        HomeLayerRowView(
            title: app.displayName,
            subtitle: app.appID,
            trailing: "\(app.windowCount)w",
            icon: HomeAppIconProvider.icon(
                appID: app.appID,
                bundleIdentifier: app.bundleIdentifier,
                bundleURL: app.bundleURL
            ),
            isTrailingLoading: isWindowCountLoading,
            badge: hiddenBadge,
            badgeAccessibilityIdentifier: app.isHidden
                ? "flowtab.home.app.hidden-badge.\(appIDComponent)"
                : nil,
            isSelected: app.hasRuntimeProjection && isSelected
        )
    }
}
