import SwiftUI
import AppKit
import FlowTabCore

struct AppLogsView: View {
    let isActive: Bool
    let appLanguage: AppLanguage
    let targetAppearance: NSAppearance

    @AppStorage(AppPreferenceKeys.runtimeLogLevel)
    private var runtimeLogLevelRaw = RuntimeLogPreferencesStore.defaultLevel.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultBaseKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyReverseModifiers)
    private var hotkeyReverseModifiersRaw =
        SwitcherHotkeyPreferencesStore.defaultReverseKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKeys.rawValue

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: hotkeyPrimaryModifierRaw,
            reverseKeysRaw: hotkeyReverseModifiersRaw,
            mainKeysRaw: hotkeyMainKeyRaw,
            quitKeysRaw: hotkeyQuitKeyRaw
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
                        runtimeLogLevelRaw: $runtimeLogLevelRaw,
                        isActive: isActive,
                        hotkeyShortcutText: hotkeyConfiguration.mainShortcutText,
                        appLanguage: appLanguage,
                        targetAppearance: targetAppearance
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
