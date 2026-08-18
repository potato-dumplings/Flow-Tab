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

    @MainActor
    func testStatusItemOpenActionReactivatesWindowAfterRestoringHiddenDefaultPolicy() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        defer {
            AppDelegate.testHooks = previousHooks
            clearIsolatedUserDefaults(userDefaults)
        }

        let window = TestAppWindow(isPanelWindow: false, isMiniaturized: false)
        let application = TestAppWindowApplication(isHidden: false, appWindows: [window])
        let activationPolicyApplication = TestActivationPolicyApplication(initialPolicy: .accessory)
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            activationPolicyApplication: activationPolicyApplication
        )

        let delegate = AppDelegate()
        delegate.handleStatusItemOpenAction(application: application)

        XCTAssertEqual(
            activationPolicyApplication.appliedPolicies,
            [.regular, .accessory]
        )
        XCTAssertEqual(activationPolicyApplication.flowTabActivationPolicy, .accessory)
        XCTAssertEqual(application.activateCallCount, 2)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 2)
        XCTAssertEqual(window.orderFrontRegardlessCallCount, 2)
    }

    @MainActor
    func testStatusItemOpenActionKeepsRegularPolicyWhenRegularAppVisibilityIsEnabled() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        defer {
            AppDelegate.testHooks = previousHooks
            clearIsolatedUserDefaults(userDefaults)
        }

        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        let window = TestAppWindow(isPanelWindow: false, isMiniaturized: false)
        let application = TestAppWindowApplication(isHidden: false, appWindows: [window])
        let activationPolicyApplication = TestActivationPolicyApplication(initialPolicy: .regular)
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            activationPolicyApplication: activationPolicyApplication
        )

        let delegate = AppDelegate()
        delegate.handleStatusItemOpenAction(application: application)

        XCTAssertEqual(activationPolicyApplication.appliedPolicies, [])
        XCTAssertEqual(application.activateCallCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 1)
    }

    @MainActor
    func testStatusItemOpenActionWaitsForWindowVisibilityBeforeRestoringAccessory() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        defer {
            AppDelegate.testHooks = previousHooks
            clearIsolatedUserDefaults(userDefaults)
        }

        let window = TestAppWindow(isPanelWindow: false, isMiniaturized: true, isVisible: false)
        let application = TestAppWindowApplication(isHidden: false, appWindows: [window])
        let activationPolicyApplication = TestActivationPolicyApplication(initialPolicy: .accessory)
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            activationPolicyApplication: activationPolicyApplication
        )

        let delegate = AppDelegate()
        delegate.handleStatusItemOpenAction(application: application)

        XCTAssertEqual(activationPolicyApplication.appliedPolicies, [.regular])
        XCTAssertFalse(window.isMiniaturized)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 1)

        window.isVisible = true
        window.emitPresentationEvidence(.windowDidBecomeKey)

        XCTAssertEqual(
            activationPolicyApplication.appliedPolicies,
            [.regular, .accessory]
        )
        XCTAssertGreaterThanOrEqual(application.activateCallCount, 2)
    }

    @MainActor
    func testTemporaryStatusItemActivationSupersedesPriorWindowObservation() {
        let firstWindow = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: true,
            isVisible: false
        )
        let firstApplication = TestAppWindowApplication(
            isHidden: false,
            appWindows: [firstWindow]
        )
        let secondWindow = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: true,
            isVisible: false
        )
        let secondApplication = TestAppWindowApplication(
            isHidden: false,
            appWindows: [secondWindow]
        )
        let activationPolicyApplication =
            TestActivationPolicyApplication(initialPolicy: .accessory)

        AppWindowCoordinator.activateMainWindowOrOpenHomeScene(
            application: firstApplication,
            activationPolicyApplication: activationPolicyApplication,
            temporarilyUseRegularActivation: true
        )
        AppWindowCoordinator.activateMainWindowOrOpenHomeScene(
            application: secondApplication,
            activationPolicyApplication: activationPolicyApplication,
            temporarilyUseRegularActivation: true
        )

        firstWindow.isVisible = true
        firstWindow.emitPresentationEvidence(.windowDidBecomeKey)
        XCTAssertEqual(activationPolicyApplication.appliedPolicies, [.regular])

        secondWindow.isVisible = true
        secondWindow.emitPresentationEvidence(.windowDidBecomeKey)
        XCTAssertEqual(
            activationPolicyApplication.appliedPolicies,
            [.regular, .accessory]
        )
        XCTAssertEqual(
            firstWindow.activePresentationEvidenceObserverCount,
            0
        )
        XCTAssertEqual(
            secondWindow.activePresentationEvidenceObserverCount,
            0
        )
    }
}
