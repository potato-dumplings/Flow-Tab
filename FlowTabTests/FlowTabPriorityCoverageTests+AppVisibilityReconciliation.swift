import AppKit
import Dispatch
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testReplacedAppDelegateCannotCommitStaleVisibilityReconciliation() async {
        guard
            let staleUserDefaults = makeIsolatedUserDefaults(),
            let currentUserDefaults = makeIsolatedUserDefaults()
        else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let stressRunner = SpyStressRunner()
        let staleScanRelease = DispatchSemaphore(value: 0)
        var staleDelegate: AppDelegate?
        var currentDelegate: AppDelegate?
        defer {
            staleScanRelease.signal()
            staleDelegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            currentDelegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousLaunchEnvironment
            clearIsolatedUserDefaults(staleUserDefaults)
            clearIsolatedUserDefaults(currentUserDefaults)
        }

        func testHooks(
            userDefaults: UserDefaults,
            recordsProvider: @escaping @Sendable () -> [InstalledAppRecord]
        ) -> AppDelegate.TestHooks {
            AppDelegate.TestHooks(
                userDefaults: userDefaults,
                makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                    hotkeyFactory.make(
                        configuration: configuration,
                        signature: signature,
                        forwardHotkeyID: forwardHotkeyID,
                        backwardHotkeyID: backwardHotkeyID
                    )
                },
                commandTabTakeoverController: SpyCommandTabTakeoverController(),
                stressRunner: stressRunner,
                activationPolicyApplication: TestActivationPolicyApplication(),
                appVisibilityRecordsProvider: recordsProvider
            )
        }

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = ["FlowTab"]
        FlowTabTestLaunchOptions.environmentOverrideForTesting = [:]
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}

        let staleHiddenAppID = "com.example.stale-helper"
        staleUserDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        staleUserDefaults.set([staleHiddenAppID], forKey: AppPreferenceKeys.hiddenAppIDs)
        let staleScanStarted = expectation(description: "stale visibility scan started")
        AppDelegate.testHooks = testHooks(
            userDefaults: staleUserDefaults,
            recordsProvider: {
                staleScanStarted.fulfill()
                _ = staleScanRelease.wait(timeout: .now() + 5)
                return []
            }
        )
        let firstDelegate = AppDelegate()
        staleDelegate = firstDelegate
        firstDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await fulfillment(of: [staleScanStarted], timeout: 5)

        let configurableAppID = "com.example.current-editor"
        currentUserDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        currentUserDefaults.set(
            [configurableAppID, "com.example.current-helper"],
            forKey: AppPreferenceKeys.hiddenAppIDs
        )
        AppDelegate.testHooks = testHooks(
            userDefaults: currentUserDefaults,
            recordsProvider: {
                [
                    InstalledAppRecord(
                        id: configurableAppID,
                        displayName: "Current Editor",
                        bundleIdentifier: configurableAppID,
                        path: "/Applications/Current Editor.app",
                        isRunning: true
                    )
                ]
            }
        )
        var publicationCount = 0
        let currentReconciliationPublished = expectation(
            description: "current visibility reconciliation published"
        )
        let observer = NotificationCenter.default.addObserver(
            forName: .flowTabAppVisibilityPreferenceChanged,
            object: nil,
            queue: .main
        ) { _ in
            publicationCount += 1
            if publicationCount == 1 {
                currentReconciliationPublished.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let secondDelegate = AppDelegate()
        currentDelegate = secondDelegate
        secondDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await fulfillment(of: [currentReconciliationPublished], timeout: 5)

        staleScanRelease.signal()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(
            staleUserDefaults.stringArray(forKey: AppPreferenceKeys.hiddenAppIDs),
            [staleHiddenAppID]
        )
        XCTAssertEqual(
            currentUserDefaults.stringArray(forKey: AppPreferenceKeys.hiddenAppIDs),
            [configurableAppID]
        )
    }

    @MainActor
    func testAppDelegateLaunchReconcilesLegacyHiddenAppIDsOnce() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousLaunchEnvironment
            clearIsolatedUserDefaults(userDefaults)
        }

        let configurableAppID = "com.example.editor"
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        userDefaults.set(
            [configurableAppID, "com.example.menu-bar", "com.example.helper"],
            forKey: AppPreferenceKeys.hiddenAppIDs
        )
        FlowTabTestLaunchOptions.argumentsOverrideForTesting = ["FlowTab"]
        FlowTabTestLaunchOptions.environmentOverrideForTesting = [:]
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
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
            appVisibilityRecordsProvider: {
                [
                    InstalledAppRecord(
                        id: configurableAppID,
                        displayName: "Editor",
                        bundleIdentifier: configurableAppID,
                        path: "/Applications/Editor.app",
                        isRunning: true
                    ),
                    InstalledAppRecord(
                        id: "com.example.menu-bar",
                        displayName: "Menu Bar",
                        bundleIdentifier: "com.example.menu-bar",
                        path: "/Applications/Menu Bar.app",
                        isRunning: true,
                        visibilityCapability: .systemManaged(reason: .macOSRuntimeMode)
                    )
                ]
            }
        )
        let reconciliationPublished = expectation(
            description: "launch hidden application reconciliation published"
        )
        reconciliationPublished.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .flowTabAppVisibilityPreferenceChanged,
            object: nil,
            queue: .main
        ) { _ in
            reconciliationPublished.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await fulfillment(of: [reconciliationPublished], timeout: 5)

        XCTAssertEqual(
            userDefaults.stringArray(forKey: AppPreferenceKeys.hiddenAppIDs),
            [configurableAppID]
        )
    }
}
