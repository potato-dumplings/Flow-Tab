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
        static let homeAppMockBrowser = "flowtab.home.app.\("com.flowtab.mock.browser".flowTabUITestAccessibilityIdentifierComponent)"
        static let homeAppMockMail = "flowtab.home.app.\("com.flowtab.mock.mail".flowTabUITestAccessibilityIdentifierComponent)"
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
        static let settingsAppVisibilityMockMail = "flowtab.settings.app-visibility.app.\("com.flowtab.mock.mail".flowTabUITestAccessibilityIdentifierComponent)"
        static let settingsPermissionAccessibilityAction = "flowtab.settings.permission.accessibility-action"
        static let settingsPermissionScreenCaptureAction = "flowtab.settings.permission.screen-capture-action"
        static let settingsPermissionLaunchAtLogin = "flowtab.settings.permission.launch-at-login"
        static let settingsHotkeyMainModifier = "flowtab.settings.hotkey.main-modifier"
        static let settingsHotkeyMainKey = "flowtab.settings.hotkey.main-key"
        static let settingsHotkeyQuitKey = "flowtab.settings.hotkey.quit-key"
        static let settingsHotkeyInAppModifier = "flowtab.settings.hotkey.in-app-modifier"
        static let settingsHotkeyInAppKey = "flowtab.settings.hotkey.in-app-key"
        static let settingsHotkeyMainTakeoverStatus = "flowtab.settings.hotkey.main-takeover-status"
        static let statusItem = "flowtab.status-item"
        static let statusItemQuit = "flowtab.status-item.quit"
        static let switcherSummary = "flowtab.testing.switcher.summary"
        static let switcherAppMockBrowser = "flowtab.switcher.app.\("com.flowtab.mock.browser".flowTabUITestAccessibilityIdentifierComponent)"
        static let switcherAppMockMail = "flowtab.switcher.app.\("com.flowtab.mock.mail".flowTabUITestAccessibilityIdentifierComponent)"
        static let switcherAppMockManyWindows = "flowtab.switcher.app.\("com.flowtab.mock.many-windows".flowTabUITestAccessibilityIdentifierComponent)"
        static let switcherAppMockMinimizedNotes = "flowtab.switcher.app.\("com.flowtab.mock.minimized-notes".flowTabUITestAccessibilityIdentifierComponent)"
        static let switcherNextWindowPage = "flowtab.switcher.window-page.next"
        static let switcherSearchInput = "flowtab.switcher.search.input"
        static let switcherSearchAppMockMail = "flowtab.switcher.search.app.\("com.flowtab.mock.mail".flowTabUITestAccessibilityIdentifierComponent)"
        static let switcherSearchWindowMockMailInbox =
            "flowtab.switcher.search.window.\("window:com.flowtab.mock.mail#mock-mail-inbox".flowTabUITestAccessibilityIdentifierComponent)"
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

extension String {
    var flowTabUITestAccessibilitySlug: String {
        let replaced = flowTabUITestAccessibilityStableSource
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return replaced.isEmpty ? "item" : replaced
    }

    var flowTabUITestAccessibilityIdentifierComponent: String {
        "\(flowTabUITestAccessibilitySlug).id-\(Self.flowTabUITestAccessibilityDigest(flowTabUITestAccessibilityStableSource))"
    }

    private var flowTabUITestAccessibilityStableSource: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "item" : trimmed
    }

    private static func flowTabUITestAccessibilityDigest(_ value: String) -> String {
        let digest = flowTabUITestAccessibilityHash64(value) & 0xffff_ffff
        return String(format: "%08llx", digest)
    }

    private static func flowTabUITestAccessibilityHash64(_ value: String) -> UInt64 {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
