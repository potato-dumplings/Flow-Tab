//
//  FlowTabUITests.swift
//  FlowTabUITests
//
//  Created by lk on 3/24/26.
//

import Foundation
import XCTest

final class FlowTabUITests: XCTestCase {
    private var preservedFlowTabUserDefaultsDomain: [String: Any]?

    enum Identifier {
        static let homeTabButton = "flowtab.sidebar.tab.home"
        static let logsTabButton = "flowtab.sidebar.tab.logs"
        static let settingsTabButton = "flowtab.sidebar.tab.settings"
        static let homeTabContent = "flowtab.tab.home.content"
        static let homeAppList = "flowtab.home.app.list"
        static let homeAppMockBrowser = "flowtab.home.app.com-flowtab-mock-browser"
        static let homeAppMockMail = "flowtab.home.app.com-flowtab-mock-mail"
        static let homeWindowList = "flowtab.home.window.list"
        static let logsTabContent = "flowtab.tab.logs.content"
        static let settingsTabContent = "flowtab.tab.settings.content"
        static let permissionBanner = "flowtab.home.permission.banner"
        static let permissionOpenSettings = "flowtab.home.permission.open-settings"
        static let permissionDismiss = "flowtab.home.permission.dismiss"
        static let permissionReminderSwitch = "flowtab.settings.permission.reminder"
        static let logsClearButton = "flowtab.logs.clear"
        static let logsOpenDirectoryButton = "flowtab.logs.open-directory"
        static let logsLines = "flowtab.logs.lines"
        static let logsEmptyHint = "flowtab.logs.empty-hint"
        static let logsSeededDebugLine = "flowtab.logs.line.seeded.debug"
        static let logsSeededInfoLine = "flowtab.logs.line.seeded.info"
        static let logsSeededWarnLine = "flowtab.logs.line.seeded.warn"
        static let logsSeededErrorLine = "flowtab.logs.line.seeded.error"
        static let settingsAppearanceShowShortcutHint = "flowtab.settings.appearance.show-shortcut-hint"
        static let settingsAppearanceShowInCommandTab = "flowtab.settings.appearance.show-in-command-tab"
        static let settingsAppearanceThemeMode = "flowtab.settings.appearance.theme-mode"
        static let settingsAppearanceAppLanguage = "flowtab.settings.appearance.app-language"
        static let settingsWindowAutoEnterDelay = "flowtab.settings.window.auto-enter-delay"
        static let settingsWindowAutoEnterDelayInput = "flowtab.settings.window.auto-enter-delay.input"
        static let settingsWindowAutoRestoreMinimized = "flowtab.settings.window.auto-restore-minimized"
        static let settingsWindowHideMinimizedApps = "flowtab.settings.window.hide-minimized-apps"
        static let settingsSearchEnabled = "flowtab.settings.search.enabled"
        static let settingsSearchDefaultScope = "flowtab.settings.search.default-scope"
        static let settingsAppVisibilityManage = "flowtab.settings.app-visibility.manage"
        static let settingsAppVisibilityManager = "flowtab.settings.app-visibility.manager"
        static let settingsAppVisibilitySearch = "flowtab.settings.app-visibility.search"
        static let settingsAppVisibilityFilterHidden = "flowtab.settings.app-visibility.filter.hidden"
        static let settingsAppVisibilityShowToggle = "flowtab.settings.app-visibility.show-toggle"
        static let settingsAppVisibilityMockMail = "flowtab.settings.app-visibility.app.com-flowtab-mock-mail"
        static let settingsPermissionAccessibilityAction = "flowtab.settings.permission.accessibility-action"
        static let settingsPermissionScreenCaptureAction = "flowtab.settings.permission.screen-capture-action"
        static let settingsPermissionLaunchAtLogin = "flowtab.settings.permission.launch-at-login"
        static let settingsHotkeyMainModifier = "flowtab.settings.hotkey.main-modifier"
        static let settingsHotkeyMainKey = "flowtab.settings.hotkey.main-key"
        static let settingsHotkeyQuitKey = "flowtab.settings.hotkey.quit-key"
        static let settingsHotkeyInAppModifier = "flowtab.settings.hotkey.in-app-modifier"
        static let settingsHotkeyInAppKey = "flowtab.settings.hotkey.in-app-key"
        static let settingsHotkeyMainTakeoverStatus = "flowtab.settings.hotkey.main-takeover-status"
        static let switcherSummary = "flowtab.testing.switcher.summary"
        static let switcherAppMockBrowser = "flowtab.switcher.app.com-flowtab-mock-browser"
        static let switcherAppMockMail = "flowtab.switcher.app.com-flowtab-mock-mail"
        static let switcherAppMockManyWindows = "flowtab.switcher.app.com-flowtab-mock-many-windows"
        static let switcherAppMockMinimizedNotes = "flowtab.switcher.app.com-flowtab-mock-minimized-notes"
        static let switcherNextWindowPage = "flowtab.switcher.window-page.next"
        static let switcherSearchInput = "flowtab.switcher.search.input"
        static let switcherSearchAppMockMail = "flowtab.switcher.search.app.com-flowtab-mock-mail"
        static let switcherSearchWindowMockMailInbox =
            "flowtab.switcher.search.window.window-com-flowtab-mock-mail-mock-mail-inbox"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateAppIfRunning()
        preserveAndClearFlowTabUserDefaultsForUITest()
        terminateSpaceFixtureAppIfRunning()
        terminateConfiguredSpaceFixtureWorkflowAppsIfRunning()
    }

    override func tearDownWithError() throws {
        terminateAppIfRunning()
        terminateSpaceFixtureAppIfRunning()
        terminateConfiguredSpaceFixtureWorkflowAppsIfRunning()
        restoreFlowTabUserDefaultsAfterUITest()
    }

    private func preserveAndClearFlowTabUserDefaultsForUITest() {
        let domainName = FlowTabUITestAppIdentity.configured().bundleIdentifier
        let userDefaults = UserDefaults(suiteName: domainName) ?? .standard
        preservedFlowTabUserDefaultsDomain = sanitizedPreservedDomain(
            userDefaults.persistentDomain(forName: domainName)
        )
        userDefaults.removePersistentDomain(forName: domainName)
        userDefaults.synchronize()
    }

    private func restoreFlowTabUserDefaultsAfterUITest() {
        let domainName = FlowTabUITestAppIdentity.configured().bundleIdentifier
        let userDefaults = UserDefaults(suiteName: domainName) ?? .standard
        userDefaults.removePersistentDomain(forName: domainName)
        if let preservedFlowTabUserDefaultsDomain {
            userDefaults.setPersistentDomain(
                preservedFlowTabUserDefaultsDomain,
                forName: domainName
            )
        }
        userDefaults.synchronize()
        preservedFlowTabUserDefaultsDomain = nil
    }

    private func sanitizedPreservedDomain(_ domain: [String: Any]?) -> [String: Any]? {
        guard var domain else { return nil }
        guard let hiddenAppIDs = domain["hiddenAppIDs"] as? [String] else { return domain }

        // Existing local runs may already have leaked UI-test app IDs into the real app domain.
        let sanitizedHiddenAppIDs = hiddenAppIDs.filter { !isUITestMockAppID($0) }
        if sanitizedHiddenAppIDs.isEmpty {
            domain.removeValue(forKey: "hiddenAppIDs")
        } else {
            domain["hiddenAppIDs"] = sanitizedHiddenAppIDs
        }
        return domain
    }

    private func isUITestMockAppID(_ appID: String) -> Bool {
        appID.hasPrefix("com.flowtab.mock.") || appID == "com.xxx.test" || appID == "com.xxx.csgo"
    }
}
