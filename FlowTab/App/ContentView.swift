import SwiftUI
import AppKit
import FlowTabCore

struct ContentView: View {
    @ObservedObject private var presentation = FlowPresentationState.shared
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
