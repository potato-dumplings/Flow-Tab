import AppKit
import SwiftUI

struct AppVisibilityManagerView: View {
    private enum Layout {
        static let listRowHeight: CGFloat = 55
    }

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

    private var paneBackground: Color {
        isDark ? Color(red: 0.09, green: 0.09, blue: 0.10) : Color(red: 0.985, green: 0.986, blue: 0.99)
    }

    private var contentBackground: Color {
        isDark ? Color.black : Color(red: 0.998, green: 0.998, blue: 1.0)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var groupedSurface: Color {
        isDark ? Color.white.opacity(0.055) : Color.white.opacity(0.94)
    }

    private var rowSeparatorColor: Color {
        isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.045)
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane

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

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            searchField
            filterBar
            appList
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 372)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(paneBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button {
                onClose()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(AppStrings.text(.appVisibilityBack))
                        .font(.system(size: 12, weight: .regular))
                }
                .padding(.vertical, 6)
                .padding(.trailing, 8)
                .flowTabInteractiveHitArea()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("flowtab.settings.app-visibility.back")

            VStack(alignment: .leading, spacing: 3) {
                Text(AppStrings.text(.appVisibilityManagerTitle))
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(1)
                Text(
                    AppStrings.text(
                        .appVisibilityManagerSubtitle,
                        replacements: ["count": "\(model.hiddenCount)"]
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private var filterBar: some View {
        let filters = AppVisibilityManagerModel.Filter.allCases
        return HStack(spacing: 0) {
            ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                filterButton(filter)
                if index < filters.count - 1 {
                    Rectangle()
                        .fill(rowSeparatorColor)
                        .frame(width: 1, height: 17)
                }
            }
        }
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.045) : Color.white.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .accessibilityIdentifier("flowtab.settings.app-visibility.filter")
    }

    private func filterButton(_ filter: AppVisibilityManagerModel.Filter) -> some View {
        let isSelected = model.filter == filter
        return Button {
            model.filter = filter
        } label: {
            Text(filter.title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.78))
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(isDark ? 0.14 : 0.055))
                            .padding(2)
                    }
                }
                .flowTabInteractiveHitArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(.plain)
        .accessibilityIdentifier("flowtab.settings.app-visibility.filter.\(filter.id)")
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
            .frame(height: 17)
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(groupedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var appList: some View {
        let visibleApps = model.visibleApps
        return FlowSnappedListScrollView(
            rowCount: visibleApps.count,
            rowHeight: Layout.listRowHeight,
            accessibilityIdentifier: "flowtab.settings.app-visibility.list"
        ) {
            ForEach(Array(visibleApps.enumerated()), id: \.element.id) { index, app in
                appRowButton(
                    app: app,
                    isLast: index == visibleApps.count - 1
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(groupedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
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

    private func appRowButton(app: InstalledAppRecord, isLast: Bool) -> some View {
        Button {
            model.selectedAppID = app.id
        } label: {
            AppVisibilityListRow(
                app: app,
                isHidden: model.isHidden(app),
                isSelected: app.id == model.selectedAppID
            )
            .padding(.horizontal, 12)
            .frame(height: Layout.listRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                rowBackground(isSelected: app.id == model.selectedAppID)
            }
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(rowSeparatorColor)
                        .frame(height: 0.5)
                }
            }
            .flowTabInteractiveHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("flowtab.settings.app-visibility.app.\(app.id.flowTabAccessibilityIdentifierComponent)")
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool) -> some View {
        if isSelected {
            LinearGradient(
                colors: [
                    isDark ? Color.accentColor.opacity(0.24) : Color(red: 0.88, green: 0.93, blue: 1.0),
                    isDark ? Color.accentColor.opacity(0.16) : Color(red: 0.92, green: 0.96, blue: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color.clear
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
        .padding(.horizontal, 30)
        .padding(.top, 60)
        .padding(.bottom, 24)
    }

    private func appDetail(for app: InstalledAppRecord) -> some View {
        let isHidden = model.isHidden(app)
        return VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .center, spacing: 16) {
                AppVisibilityIconView(app: app, size: 62)
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

            HStack(spacing: 14) {
                Text(AppStrings.text(.appVisibilityShowInSwitcher))
                    .font(.system(size: 14, weight: .medium))
                Toggle(
                    "",
                    isOn: Binding(
                        get: { !isHidden },
                        set: { model.setHidden(!$0, for: app.id) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityIdentifier("flowtab.settings.app-visibility.show-toggle")
            }

            VStack(alignment: .leading, spacing: 0) {
                detailRow(title: AppStrings.text(.appVisibilityBundleID), value: app.bundleIdentifier ?? "-")
                Divider().overlay(rowSeparatorColor)
                detailRow(title: AppStrings.text(.appVisibilityPath), value: app.path ?? "-")
                Divider().overlay(rowSeparatorColor)
                detailRow(
                    title: AppStrings.text(.appVisibilityStatus),
                    value: isHidden
                        ? AppStrings.text(.appVisibilityStatusHidden)
                        : AppStrings.text(.appVisibilityStatusVisible)
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(groupedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )

            Text(AppStrings.text(.appVisibilityEffectNote))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 38)
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
        HStack(spacing: 9) {
            AppVisibilityIconView(app: app, size: 23)
                .id(AppVisibilityIconSourceKey(app: app).value)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if isHidden {
                        Text(AppStrings.text(.appVisibilityHiddenBadge))
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.16)))
                    }
                }
                Text(app.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(isSelected ? 0.88 : 0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowTabInteractiveHitArea: ViewModifier {
    @State private var didPushCursor = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    guard !didPushCursor else { return }
                    NSCursor.pointingHand.push()
                    didPushCursor = true
                } else {
                    popCursorIfNeeded()
                }
            }
            .onDisappear {
                popCursorIfNeeded()
            }
    }

    private func popCursorIfNeeded() {
        guard didPushCursor else { return }
        NSCursor.pop()
        didPushCursor = false
    }
}

private extension View {
    func flowTabInteractiveHitArea() -> some View {
        modifier(FlowTabInteractiveHitArea())
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
