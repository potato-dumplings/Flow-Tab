import SwiftUI
import FlowTabCore

struct AppLogsView: View {
    let isActive: Bool
    let appLanguage: AppLanguage

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
            FlowPageBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.text(.logsPageTitle, language: appLanguage))
                            .font(.system(size: 22, weight: .semibold))
                        Text(AppStrings.text(.logsPageSubtitle, language: appLanguage))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    RuntimeLogsSection(
                        enableVerboseDiagnostics: $enableVerboseDiagnostics,
                        runtimeLogLevelRaw: $runtimeLogLevelRaw,
                        hotkeyShortcutText: hotkeyConfiguration.mainShortcutText,
                        appLanguage: appLanguage
                    )
                }
                .padding(.horizontal, FlowPageLayout.horizontalInset)
                .padding(.bottom, 24)
                .padding(.top, FlowPageLayout.alignedTopInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("flowtab.tab.logs.content")
    }
}
