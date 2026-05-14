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

    func testAppVisibilityFilterNormalizesHiddenAppIDs() {
        let normalizedIDs = AppVisibilityFilter.normalizedHiddenAppIDs([
            " com.example.mail ",
            "",
            "\n",
            "com.example.mail",
            "com.example.browser"
        ])

        XCTAssertEqual(normalizedIDs, ["com.example.browser", "com.example.mail"])
    }

    func testAppVisibilityFilterRemovesHiddenApps() {
        let apps = [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: false, lastActiveAt: 300)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 290)
                ]
            )
        ]
        let filter = AppVisibilityFilter(hiddenAppIDs: ["com.example.mail"])

        XCTAssertEqual(filter.filteredApps(apps).map(\.id), ["com.example.browser"])
        XCTAssertFalse(filter.includes(appID: "com.example.mail"))
        XCTAssertTrue(filter.includes(appID: "com.example.browser"))
    }

    func testAppVisibilityFilterRanksHiddenAppsAfterVisibleApps() {
        let appIDs = [
            "com.example.mail",
            "com.example.browser",
            "com.example.notes"
        ]
        let filter = AppVisibilityFilter(hiddenAppIDs: ["com.example.mail"])
        let orderedAppIDs = appIDs.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = filter.visibilitySortRank(appID: lhs.element)
                let rhsRank = filter.visibilitySortRank(appID: rhs.element)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        XCTAssertEqual(orderedAppIDs, ["com.example.browser", "com.example.notes", "com.example.mail"])
        XCTAssertTrue(filter.isHidden(appID: "com.example.mail"))
        XCTAssertFalse(filter.isHidden(appID: "com.example.browser"))
        XCTAssertEqual(filter.visibilitySortRank(appID: " "), 0)
    }
}
