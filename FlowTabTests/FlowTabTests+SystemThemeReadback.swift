import AppKit
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testSystemThemeStateMatchesCurrentSystemAppearanceWhenAppDefaultsContainAppleInterfaceStyle() {
        let systemAppearanceKey = "AppleInterfaceStyle"
        let state = SystemThemeState.shared
        let previousAppearance = NSApp.appearance
        let previousAppAppearanceRaw = systemThemeAppScopedDefaultString(
            forKey: systemAppearanceKey
        )
        NSApp.appearance = nil
        state.refreshColorScheme()
        let expectedSystemColorScheme = SystemThemeState.colorScheme(
            for: NSApp.effectiveAppearance
        )
        let appScopedContamination = expectedSystemColorScheme == .dark
            ? "Light"
            : "Dark"
        defer {
            NSApp.appearance = previousAppearance
            restoreSystemThemeUserDefaultsValue(
                previousAppAppearanceRaw,
                forKey: systemAppearanceKey
            )
            state.refreshColorScheme()
        }

        UserDefaults.standard.set(
            appScopedContamination,
            forKey: systemAppearanceKey
        )
        state.refreshColorScheme()
        let observedSystemColorScheme = SystemThemeState.colorScheme(
            for: NSApp.effectiveAppearance
        )

        XCTAssertEqual(observedSystemColorScheme, expectedSystemColorScheme)
        XCTAssertEqual(
            state.colorScheme,
            expectedSystemColorScheme,
            "Follow-system theme should match the current effective system appearance."
        )
    }

    private func systemThemeAppScopedDefaultString(forKey key: String) -> String? {
        guard let domainName = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: domainName)?[key]
            as? String
    }

    private func restoreSystemThemeUserDefaultsValue(
        _ value: String?,
        forKey key: String
    ) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
