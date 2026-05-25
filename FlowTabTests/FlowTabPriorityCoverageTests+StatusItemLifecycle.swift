import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testAppDelegateKeepsAppRunningAfterLastWindowCloses() {
        let delegate = AppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }

    @MainActor
    func testAppDelegateAppliesActivationPolicyFromVisibilityPreference() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        defer {
            AppDelegate.testHooks = previousHooks
            clearIsolatedUserDefaults(userDefaults)
        }

        let application = TestActivationPolicyApplication(initialPolicy: .regular)
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            activationPolicyApplication: application
        )

        let delegate = AppDelegate()
        delegate.applyActivationPolicyFromPreferences()

        XCTAssertEqual(application.appliedPolicies, [.accessory])
        XCTAssertEqual(application.flowTabActivationPolicy, .accessory)

        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        delegate.applyActivationPolicyFromPreferences()

        XCTAssertEqual(application.appliedPolicies, [.accessory, .regular])
        XCTAssertEqual(application.flowTabActivationPolicy, .regular)

        delegate.applyActivationPolicyFromPreferences()
        XCTAssertEqual(application.appliedPolicies, [.accessory, .regular])
    }

    @MainActor
    func testStatusItemMenuContainsOnlyQuitAndQuitRequestsTermination() {
        let previousContext = FlowPresentationState.shared.context
        defer {
            FlowPresentationState.shared.setThemeMode(rawValue: previousContext.themeMode.rawValue)
            FlowPresentationState.shared.setAppLanguage(rawValue: previousContext.appLanguage.rawValue)
        }
        FlowPresentationState.shared.setAppLanguage(rawValue: AppLanguage.simplifiedChinese.rawValue)

        let delegate = AppDelegate()
        let menu = delegate.makeStatusItemMenu()

        XCTAssertEqual(menu.items.map(\.title), [AppStrings.text(.menuQuit, language: .simplifiedChinese)])
        XCTAssertEqual(
            menu.items.first?.identifier?.rawValue,
            AppDelegate.statusItemQuitMenuItemIdentifier
        )
        XCTAssertNotNil(menu.items.first?.action)

        FlowPresentationState.shared.setAppLanguage(rawValue: AppLanguage.english.rawValue)
        XCTAssertEqual(
            delegate.makeStatusItemMenu().items.map(\.title),
            [AppStrings.text(.menuQuit, language: .english)]
        )

        let application = TestTerminationApplication()
        delegate.handleStatusItemQuitAction(application: application)

        XCTAssertEqual(application.terminateCallCount, 1)
    }

    @MainActor
    func testStatusItemOpenActionPreservesLastSelectedTab() {
        let previousSelectedTab = HomeTabState.shared.selectedTab
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
        }

        HomeTabState.shared.selectedTab = .logs
        let application = TestAppWindowApplication(isHidden: false, appWindows: [])
        let delegate = AppDelegate()

        delegate.handleStatusItemOpenAction(application: application)

        XCTAssertEqual(HomeTabState.shared.selectedTab, .logs)
        XCTAssertEqual(application.showSettingsWindowActionCount, 1)
    }
}
