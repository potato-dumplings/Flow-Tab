import AppKit
import SwiftUI

struct AppVisibilityManagerView: View {
    let onClose: () -> Void

    @StateObject private var model = AppVisibilityManagerModel()
    @ObservedObject private var systemTheme = SystemThemeState.shared
    @AppStorage(AppPreferenceKeys.themeMode)
    private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue

    private var colorScheme: ColorScheme {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
            .resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var sidebarBackground: Color {
        isDark ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    private var contentBackground: Color {
        isDark ? Color.black : Color.white
    }

    private var selectedBackground: Color {
        isDark ? Color.accentColor.opacity(0.36) : Color(red: 0.76, green: 0.83, blue: 0.95)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .overlay(borderColor)

            detailPane
        }
        .background(contentBackground)
        .preferredColorScheme(colorScheme)
        .id(appLanguageRaw)
        .onAppear {
            model.reload()
        }
        .onChange(of: model.query) { _ in
            resolveSelectionAfterVisibleAppsChange()
        }
        .onChange(of: model.filter) { _ in
            resolveSelectionAfterVisibleAppsChange()
        }
        .accessibilityIdentifier("flowtab.settings.app-visibility.manager")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onClose()
            } label: {
                Label(AppStrings.text(.appVisibilityBack), systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("flowtab.settings.app-visibility.back")

            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.text(.appVisibilityManagerTitle))
                    .font(.system(size: 21, weight: .semibold))
                Text(
                    AppStrings.text(
                        .appVisibilityManagerSubtitle,
                        replacements: ["count": "\(model.hiddenCount)"]
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            searchField

            Picker("", selection: $model.filter) {
                ForEach(AppVisibilityManagerModel.Filter.allCases) { filter in
                    Text(filter.title)
                        .tag(filter)
                        .accessibilityIdentifier("flowtab.settings.app-visibility.filter.\(filter.id)")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("flowtab.settings.app-visibility.filter")

            appList
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            AppVisibilitySearchField(
                text: $model.query,
                placeholder: AppStrings.text(.appVisibilitySearchPlaceholder),
                accessibilityIdentifier: "flowtab.settings.app-visibility.search"
            )
            .frame(height: 18)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var appList: some View {
        let visibleApps = model.visibleApps
        return List(selection: $model.selectedAppID) {
            ForEach(visibleApps) { app in
                AppVisibilityListRow(
                    app: app,
                    isHidden: model.isHidden(app),
                    isSelected: app.id == model.selectedAppID
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    model.selectedAppID = app.id
                }
                .tag(app.id as String?)
                .listRowBackground(app.id == model.selectedAppID ? selectedBackground : Color.clear)
                .accessibilityIdentifier("flowtab.settings.app-visibility.app.\(app.id.flowTabAccessibilitySlug)")
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.isLoading {
                ProgressView()
            } else if visibleApps.isEmpty {
                Text(AppStrings.text(.appVisibilityNoApps))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedApp = model.selectedApp {
                appDetail(for: selectedApp)
            } else {
                emptyDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(28)
    }

    private func appDetail(for app: InstalledAppRecord) -> some View {
        let isHidden = model.isHidden(app)
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                AppVisibilityIconView(app: app, size: 54)
                    .id(AppVisibilityIconSourceKey(app: app).value)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.displayName)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                    Text(app.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            Toggle(
                AppStrings.text(.appVisibilityShowInSwitcher),
                isOn: Binding(
                    get: { !isHidden },
                    set: { model.setHidden(!$0, for: app.id) }
                )
            )
            .toggleStyle(.switch)
            .font(.system(size: 14, weight: .medium))
            .accessibilityIdentifier("flowtab.settings.app-visibility.show-toggle")

            VStack(alignment: .leading, spacing: 8) {
                detailRow(title: AppStrings.text(.appVisibilityBundleID), value: app.bundleIdentifier ?? "-")
                detailRow(title: AppStrings.text(.appVisibilityPath), value: app.path ?? "-")
                detailRow(
                    title: AppStrings.text(.appVisibilityStatus),
                    value: isHidden
                        ? AppStrings.text(.appVisibilityStatusHidden)
                        : AppStrings.text(.appVisibilityStatusVisible)
                )
            }

            Text(AppStrings.text(.appVisibilityEffectNote))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.text(.appVisibilityNoSelectionTitle))
                .font(.system(size: 20, weight: .semibold))
            Text(AppStrings.text(.appVisibilityNoSelectionSubtitle))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func resolveSelectionAfterVisibleAppsChange() {
        let visibleApps = model.visibleApps
        guard let selectedAppID = model.selectedAppID else {
            model.selectedAppID = visibleApps.first?.id
            return
        }
        if !visibleApps.contains(where: { $0.id == selectedAppID }) {
            model.selectedAppID = visibleApps.first?.id
        }
    }
}

private struct AppVisibilityListRow: View {
    let app: InstalledAppRecord
    let isHidden: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppVisibilityIconView(app: app, size: 26)
                .id(AppVisibilityIconSourceKey(app: app).value)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if isHidden {
                        Text(AppStrings.text(.appVisibilityHiddenBadge))
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.16)))
                    }
                }
                Text(app.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct AppVisibilityIconView: View {
    let app: InstalledAppRecord
    let size: CGFloat
    @State private var iconState: AppVisibilityIconState

    init(app: InstalledAppRecord, size: CGFloat) {
        self.app = app
        self.size = size
        _iconState = State(
            initialValue: AppVisibilityIconState.resolved(for: app, resolveIcon: Self.resolveIcon)
        )
    }

    private var sourceKey: AppVisibilityIconSourceKey {
        AppVisibilityIconSourceKey(app: app)
    }

    var body: some View {
        Group {
            if let icon = iconState.icon(matching: sourceKey) {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: min(10, size / 5), style: .continuous))
        .onAppear {
            refreshIconIfNeeded()
        }
        .onChange(of: sourceKey) { _ in
            refreshIconIfNeeded()
        }
    }

    private func refreshIconIfNeeded() {
        var nextState = iconState
        nextState.refreshIfNeeded(for: app, resolveIcon: Self.resolveIcon)
        iconState = nextState
    }

    private static func resolveIcon(for app: InstalledAppRecord) -> NSImage? {
        if let path = app.path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if let bundleIdentifier = app.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(named: NSImage.applicationIconName)
    }
}

struct AppVisibilityIconSourceKey: Equatable {
    let value: String

    init(app: InstalledAppRecord) {
        if let path = app.path, !path.isEmpty {
            value = "path:\(path)"
        } else if let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty {
            value = "bundle:\(bundleIdentifier)"
        } else {
            value = "id:\(app.id)"
        }
    }
}

struct AppVisibilityIconState {
    private(set) var sourceKey: AppVisibilityIconSourceKey?
    private(set) var icon: NSImage?

    static func resolved(
        for app: InstalledAppRecord,
        resolveIcon: (InstalledAppRecord) -> NSImage?
    ) -> AppVisibilityIconState {
        var state = AppVisibilityIconState()
        state.refreshIfNeeded(for: app, resolveIcon: resolveIcon)
        return state
    }

    func icon(matching sourceKey: AppVisibilityIconSourceKey) -> NSImage? {
        self.sourceKey == sourceKey ? icon : nil
    }

    mutating func refreshIfNeeded(
        for app: InstalledAppRecord,
        resolveIcon: (InstalledAppRecord) -> NSImage?
    ) {
        let nextSourceKey = AppVisibilityIconSourceKey(app: app)
        guard sourceKey != nextSourceKey else { return }
        sourceKey = nextSourceKey
        icon = resolveIcon(app)
    }
}

private struct AppVisibilitySearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13)
        textField.placeholderString = placeholder
        textField.lineBreakMode = .byTruncatingTail
        textField.setAccessibilityIdentifier(accessibilityIdentifier)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        if nsView.accessibilityIdentifier() != accessibilityIdentifier {
            nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }
    }
}
