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
        let isHidden = model.isHidden(app)
        let isConfigurable = app.visibilityCapability.isConfigurable
        return VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .center, spacing: 16) {
                AppVisibilityIconView(app: app, size: 62)
                    .id(AppVisibilityIconSourceKey(app: app).value)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(app.displayName)
                            .font(FlowTypography.swiftUI(.pageTitle))
                            .lineLimit(1)
                        if !isConfigurable {
                            Text(
                                AppStrings.text(
                                    .appVisibilitySystemManagedBadge,
                                    language: language
                                )
                            )
                            .font(FlowTypography.swiftUI(.micro))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                            .accessibilityIdentifier(
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
                    Text(AppStrings.text(.appVisibilityShowInSwitcher, language: language))
                        .font(FlowTypography.swiftUI(.formLabelEmphasized))
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { !isHidden },
                            set: { model.setHidden(!$0, for: app.id) }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!isConfigurable)
                    .accessibilityIdentifier("flowtab.settings.app-visibility.show-toggle")
                }

                if let reason = app.visibilityCapability.unavailableReason {
                    Text(unavailableReasonText(reason))
                        .font(FlowTypography.swiftUI(.body))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            "flowtab.settings.app-visibility.unavailable-reason"
                        )
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
                    value: statusText(isHidden: isHidden, isConfigurable: isConfigurable)
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

            if isConfigurable {
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

    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.text(.appVisibilityNoSelectionTitle, language: language))
                .font(FlowTypography.swiftUI(.pageTitle))
            Text(AppStrings.text(.appVisibilityNoSelectionSubtitle, language: language))
                .font(FlowTypography.swiftUI(.body))
                .foregroundStyle(.secondary)
        }
    }

    private func statusText(isHidden: Bool, isConfigurable: Bool) -> String {
        if !isConfigurable {
            return AppStrings.text(.appVisibilityStatusSystemManaged, language: language)
        }
        return AppStrings.text(
            isHidden ? .appVisibilityStatusHidden : .appVisibilityStatusVisible,
            language: language
        )
    }

    private func unavailableReasonText(_ reason: AppVisibilityUnavailableReason) -> String {
        switch reason {
        case .macOSRuntimeMode:
            return AppStrings.text(.appVisibilitySystemManagedReason, language: language)
        }
    }
}
