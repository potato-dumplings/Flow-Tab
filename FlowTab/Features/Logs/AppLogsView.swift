import SwiftUI
import FlowTabCore

struct AppLogsView: View {
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
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, HomePageLayout.alignedTopInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("flowtab.tab.logs.content")
    }
}

