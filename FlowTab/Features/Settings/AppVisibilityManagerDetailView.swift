import SwiftUI
import FlowTabCore

struct AppVisibilityManagerDetailView: View {
    @ObservedObject var model: AppVisibilityManagerModel

    let language: AppLanguage
    let groupedSurface: Color
    let borderColor: Color
    let rowSeparatorColor: Color

    var body: some View {
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
        let presentation = model.presentation(for: app)
        let isPreferenceHidden = model.isPreferenceHidden(app)
        let isControlAvailable = presentation.controlMode != .unavailable
        return VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .center, spacing: 16) {
                AppVisibilityIconView(app: app, size: 62)
                    .id(AppVisibilityIconSourceKey(app: app).value)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(app.displayName)
                            .font(FlowTypography.swiftUI(.pageTitle))
                            .lineLimit(1)
                        switch presentation.state {
                        case .visible:
                            EmptyView()
                        case .hidden:
                            visibilityBadge(
                                text: AppStrings.text(
                                    .appVisibilityHiddenBadge,
                                    language: language
                                ),
                                color: .secondary,
                                accessibilityIdentifier:
                                    "flowtab.settings.app-visibility.effective-hidden-badge"
                            )
                        case .unavailable:
                            visibilityBadge(
                                text: AppStrings.text(
                                    .appVisibilitySystemManagedBadge,
                                    language: language
                                ),
                                color: .orange,
                                accessibilityIdentifier:
                                    "flowtab.settings.app-visibility.system-managed-badge"
                            )
                        }
                    }
                    Text(app.subtitle)
                        .font(FlowTypography.swiftUI(.body))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Text(toggleTitle(presentation.controlMode))
                        .font(FlowTypography.swiftUI(.formLabelEmphasized))
                        .accessibilityIdentifier(
                            presentation.controlMode == .regularModeOnly
                                ? "flowtab.settings.app-visibility.regular-mode-toggle-title"
                                : "flowtab.settings.app-visibility.standard-toggle-title"
                        )
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { !isPreferenceHidden },
                            set: { model.setHidden(!$0, for: app.id) }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!isControlAvailable)
                    .accessibilityIdentifier("flowtab.settings.app-visibility.show-toggle")
                }

                if let reasonText = reasonText(for: presentation.state) {
                    Text(reasonText.text)
                        .font(FlowTypography.swiftUI(.body))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(reasonText.accessibilityIdentifier)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                detailRow(
                    title: AppStrings.text(.appVisibilityBundleID, language: language),
                    value: app.bundleIdentifier ?? "-"
                )
                Divider().overlay(rowSeparatorColor)
                detailRow(
                    title: AppStrings.text(.appVisibilityPath, language: language),
                    value: app.path ?? "-"
                )
                Divider().overlay(rowSeparatorColor)
                detailRow(
                    title: AppStrings.text(.appVisibilityStatus, language: language),
                    value: statusText(presentation.state)
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

            if isControlAvailable {
                Text(AppStrings.text(.appVisibilityEffectNote, language: language))
                    .font(FlowTypography.swiftUI(.body))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            AppVisibilityDetailProjectionAccessibility.identifier(
                appID: app.id,
                generation: model.selectionProjectionGeneration
            )
        )
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(FlowTypography.swiftUI(.bodyEmphasized))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(FlowTypography.swiftUI(.body))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 38)
    }

    private func visibilityBadge(
        text: String,
        color: Color,
        accessibilityIdentifier: String
    ) -> some View {
        Text(text)
            .font(FlowTypography.swiftUI(.micro))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.text(.appVisibilityNoSelectionTitle, language: language))
                .font(FlowTypography.swiftUI(.pageTitle))
            Text(AppStrings.text(.appVisibilityNoSelectionSubtitle, language: language))
                .font(FlowTypography.swiftUI(.body))
                .foregroundStyle(.secondary)
        }
    }

    private func statusText(_ state: AppVisibilityPresentationState) -> String {
        switch state {
        case .visible:
            return AppStrings.text(.appVisibilityStatusVisible, language: language)
        case .hidden:
            return AppStrings.text(.appVisibilityStatusHidden, language: language)
        case .unavailable:
            return AppStrings.text(.appVisibilityStatusSystemManaged, language: language)
        }
    }

    private func unavailableReasonText(_ reason: AppVisibilityUnavailableReason) -> String {
        switch reason {
        case .staticBundleDeclaration:
            return AppStrings.text(.appVisibilitySystemManagedReason, language: language)
        }
    }

    private func toggleTitle(_ controlMode: AppVisibilityControlMode) -> String {
        AppStrings.text(
            controlMode == .regularModeOnly
                ? .appVisibilityShowInSwitcherRegularMode
                : .appVisibilityShowInSwitcher,
            language: language
        )
    }

    private func reasonText(
        for state: AppVisibilityPresentationState
    ) -> (text: String, accessibilityIdentifier: String)? {
        switch state {
        case .visible, .hidden(reason: .userPreference):
            return nil
        case .hidden(reason: .runtimeMode):
            return (
                AppStrings.text(.appVisibilityRuntimeHiddenReason, language: language),
                "flowtab.settings.app-visibility.runtime-hidden-reason"
            )
        case let .unavailable(reason):
            return (
                unavailableReasonText(reason),
                "flowtab.settings.app-visibility.unavailable-reason"
            )
        }
    }
}
