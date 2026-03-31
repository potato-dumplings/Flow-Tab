import XCTest
@testable import FlowTabCore

final class PreferencesTests: XCTestCase {
    func testDefaultPreferencesMatchExpectedValues() {
        let defaults = SwitcherPreferences.default

        XCTAssertTrue(defaults.autoRestoreMinimizedWindowOnSwitch)
        XCTAssertEqual(defaults.mainSwitcherHotkey, .optionTab)
        XCTAssertTrue(defaults.allowOverrideCommandTab)
        XCTAssertEqual(defaults.windowSwitchingStrategy, .recentActiveWindow)
        XCTAssertTrue(defaults.groupNavigationWraps)
        XCTAssertEqual(defaults.themeMode, .followSystem)
    }

    func testHotkeyPresetsExposeExpectedKeysAndModifiers() {
        XCTAssertEqual(Hotkey.commandTab.key, "tab")
        XCTAssertEqual(Hotkey.commandTab.modifiers, [.command])

        XCTAssertEqual(Hotkey.optionTab.key, "tab")
        XCTAssertEqual(Hotkey.optionTab.modifiers, [.option])
    }

    func testKeyModifierSupportsComposedFlags() {
        let modifiers: KeyModifier = [.command, .shift]

        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertTrue(modifiers.contains(.shift))
        XCTAssertFalse(modifiers.contains(.option))
        XCTAssertEqual(modifiers.rawValue, KeyModifier.command.rawValue | KeyModifier.shift.rawValue)
    }

    func testThemeAndWindowStrategyExposeCompleteCaseSets() {
        XCTAssertEqual(
            Set(ThemeMode.allCases),
            Set([.light, .dark, .followSystem])
        )
        XCTAssertEqual(
            Set(WindowSwitchingStrategy.allCases),
            Set([.recentActiveWindow, .rememberLastSelectedWindow])
        )
    }
}
