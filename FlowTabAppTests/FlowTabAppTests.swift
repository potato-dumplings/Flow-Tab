import XCTest
@testable import FlowTabApp
import FlowTabCore

final class FlowTabAppTests: XCTestCase {
    func testResolveKeepsCommandWhenMainShortcutIsCommandTab() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: SwitcherPrimaryModifier.command.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            quitKeyRaw: SwitcherHotkeyKey.q.rawValue
        )

        XCTAssertEqual(configuration.primaryModifier, .command)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
    }

    func testResolveFallsBackQuitKeyWhenQuitEqualsMainKey() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.q.rawValue,
            quitKeyRaw: SwitcherHotkeyKey.q.rawValue
        )

        XCTAssertEqual(configuration.mainKey, .q)
        XCTAssertEqual(configuration.quitKey, .w)
    }

    func testLoadPersistsNormalizedHotkeyValues() {
        let suiteName = "FlowTabAppTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults suite")
            return
        }

        userDefaults.set(
            SwitcherPrimaryModifier.command.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.hotkeyMainKey
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )

        let configuration = SwitcherHotkeyPreferencesStore.load(userDefaults: userDefaults)

        XCTAssertEqual(configuration.primaryModifier, .command)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyPrimaryModifier),
            SwitcherPrimaryModifier.command.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyMainKey),
            SwitcherHotkeyKey.tab.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey),
            SwitcherHotkeyKey.q.rawValue
        )

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testSearchMatchesAppByPartialName() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("fari"))
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Safari"])
    }

    func testSearchMatchesChineseAppByPinyinInitialsAndFullSpelling() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("wx"))
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])

        _ = coordinator.handleEscape()
        XCTAssertTrue(coordinator.appendQueryText("weixin"))
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])
    }

    func testSearchMatchesEnglishAbbreviation() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("vsc"))
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Visual Studio Code"])
    }

    func testSearchMatchesByBundleIDButNotGenericComPrefix() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("wechat"))
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])

        _ = coordinator.handleEscape()
        XCTAssertTrue(coordinator.appendQueryText("com"))
        XCTAssertTrue(coordinator.state.results.isEmpty)
    }

    func testWindowSearchCanMatchByAppNamePinyinInitials() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .window))

        XCTAssertTrue(coordinator.appendQueryText("wx"))
        XCTAssertEqual(coordinator.state.results.map(\.secondaryText), ["微信", "微信"])
    }

    private func searchSampleApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.tencent.xinWeChat",
                displayName: "微信",
                groupID: "social",
                lastActiveAt: 310,
                windows: [
                    WindowCandidate(id: "wechat-1", title: "工作群", isMinimized: false, lastActiveAt: 310),
                    WindowCandidate(id: "wechat-2", title: "文件传输助手", isMinimized: false, lastActiveAt: 280)
                ]
            ),
            AppSwitchCandidate(
                id: "com.microsoft.VSCode",
                displayName: "Visual Studio Code",
                groupID: "dev",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(
                        id: "vscode-1",
                        title: "FlowTabApp - SwitcherSearchCoordinator.swift",
                        isMinimized: false,
                        lastActiveAt: 300
                    )
                ]
            ),
            AppSwitchCandidate(
                id: "com.apple.Safari",
                displayName: "Safari",
                groupID: "web",
                lastActiveAt: 200,
                windows: [
                    WindowCandidate(id: "safari-1", title: "Apple", isMinimized: false, lastActiveAt: 200)
                ]
            )
        ]
    }
}
