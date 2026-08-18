import SwiftUI
import AppKit
import FlowTabCore

struct ContentView: View {
    @ObservedObject private var presentation = FlowPresentationState.shared
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
            (presentation.context.resolvedColorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("FlowTab")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(
                    AppStrings.text(
                        .contentViewHint,
                        replacements: [
                            "mainHotkey": hotkeyConfiguration.mainShortcutText,
                            "quitHotkey": hotkeyConfiguration.quitShortcutText
                        ],
                        language: presentation.context.appLanguage
                    )
                )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 420, minHeight: 240)
        .preferredColorScheme(presentation.context.resolvedColorScheme)
        .animation(.none, value: presentation.context.resolvedColorScheme)
    }
}
