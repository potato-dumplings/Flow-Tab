import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

private final class SpyLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus
    private(set) var requestedEnabledValues: [Bool] = []
    var setEnabledError: Error?

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedEnabledValues.append(enabled)
        if let setEnabledError {
            throw setEnabledError
        }
        status = enabled ? .enabled : .disabled
    }
}

extension FlowTabTests {
    func testLaunchAtLoginPreferenceDefaultsToNotAllowed() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer {
            clearIsolatedUserDefaults(userDefaults)
        }

        XCTAssertFalse(
            LaunchAtLoginPreferencesStore.loadAllowLaunchAtLogin(userDefaults: userDefaults)
        )

        userDefaults.set(true, forKey: AppPreferenceKeys.allowLaunchAtLogin)
        XCTAssertTrue(
            LaunchAtLoginPreferencesStore.loadAllowLaunchAtLogin(userDefaults: userDefaults)
        )

        userDefaults.set(false, forKey: AppPreferenceKeys.allowLaunchAtLogin)
        XCTAssertFalse(
            LaunchAtLoginPreferencesStore.loadAllowLaunchAtLogin(userDefaults: userDefaults)
        )
    }

    func testLaunchAtLoginControllerReconcilesOnlyWhenStatusNeedsChange() throws {
        let previousStatusOverride = LaunchAtLoginController.statusOverrideForTesting
        let previousSetEnabledOverride = LaunchAtLoginController.setEnabledOverrideForTesting
        defer {
            LaunchAtLoginController.statusOverrideForTesting = previousStatusOverride
            LaunchAtLoginController.setEnabledOverrideForTesting = previousSetEnabledOverride
        }

        var status = LaunchAtLoginStatus.disabled
        var requests: [Bool] = []
        LaunchAtLoginController.statusOverrideForTesting = {
            status
        }
        LaunchAtLoginController.setEnabledOverrideForTesting = { enabled in
            requests.append(enabled)
            status = enabled ? .enabled : .disabled
        }

        let controller = LaunchAtLoginController()
        XCTAssertEqual(controller.status, .disabled)

        try controller.reconcile(allowed: true)
        XCTAssertEqual(requests, [true])
        XCTAssertEqual(controller.status, .enabled)

        try controller.reconcile(allowed: true)
        XCTAssertEqual(requests, [true])

        status = .requiresApproval
        try controller.reconcile(allowed: true)
        XCTAssertEqual(requests, [true])

        try controller.reconcile(allowed: false)
        XCTAssertEqual(requests, [true, false])
        XCTAssertEqual(controller.status, .disabled)

        status = .unavailable
        try controller.reconcile(allowed: false)
        XCTAssertEqual(requests, [true, false])
        XCTAssertEqual(controller.status, .unavailable)
    }
}

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testAppDelegateLaunchDisablesLoginItemByDefault() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let launchAtLoginManager = SpyLaunchAtLoginManager(status: .enabled)
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner(),
            launchAtLoginManager: launchAtLoginManager
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertEqual(launchAtLoginManager.requestedEnabledValues, [false])
        XCTAssertEqual(launchAtLoginManager.status, .disabled)
        XCTAssertFalse(
            LaunchAtLoginPreferencesStore.loadAllowLaunchAtLogin(userDefaults: userDefaults)
        )
    }

    @MainActor
    func testAppDelegateLaunchEnablesLoginItemWhenPreferenceAllowsIt() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let launchAtLoginManager = SpyLaunchAtLoginManager(status: .disabled)
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        userDefaults.set(true, forKey: AppPreferenceKeys.allowLaunchAtLogin)
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner(),
            launchAtLoginManager: launchAtLoginManager
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertEqual(launchAtLoginManager.requestedEnabledValues, [true])
        XCTAssertEqual(launchAtLoginManager.status, .enabled)
    }
}
