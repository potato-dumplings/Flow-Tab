#if FLOWTAB_TESTING
import AppKit
import Carbon

struct AppDelegateTestHooks {
    var userDefaults: UserDefaults? = nil
    var makePanelController: (() -> SwitcherPanelController)? = nil
    var makeHotkeyMonitor: ((
        SwitcherHotkeyConfiguration,
        OSType,
        UInt32,
        UInt32
    ) -> any HotkeyMonitoring)? = nil
    var hotkeyChordEventAccessSnapshotProvider:
        (() -> HotkeyChordEventAccessSnapshot)? = nil
    var commandTabTakeoverController: (any CommandTabTakeoverControlling)? = nil
    var stressRunner: (any TabSwitchStressRunning)? = nil
    var launchAtLoginManager: (any LaunchAtLoginManaging)? = nil
    var activationPolicyApplication: (any AppActivationPolicyApplying)? = nil
    var runtimeProjectionService: (any RuntimeProjectionServing)? = nil
    var updateCoordinator: (any FlowTabUpdateCoordinating)? = nil
    var workspaceNotificationCenter: NotificationCenter? = nil
    var appLaunchWindowEvidenceCoordinator:
        (any RuntimeAppLaunchWindowEvidenceCoordinating)? = nil
    var appVisibilityRecordsProvider:
        (@Sendable () -> [InstalledAppRecord])? = nil
}

@MainActor
private var appDelegateTestHooksStorage = AppDelegateTestHooks()

@MainActor
extension AppDelegate {
    typealias TestHooks = AppDelegateTestHooks

    static var testHooks: TestHooks {
        get { appDelegateTestHooksStorage }
        set { appDelegateTestHooksStorage = newValue }
    }

    var resolvedUserDefaults: UserDefaults {
        Self.testHooks.userDefaults ?? .standard
    }

    var resolvedStressRunner: any TabSwitchStressRunning {
        Self.testHooks.stressRunner ?? TabSwitchStressRunner.shared
    }

    var resolvedLaunchAtLoginManager: any LaunchAtLoginManaging {
        Self.testHooks.launchAtLoginManager ?? LaunchAtLoginController.shared
    }

    var resolvedActivationPolicyApplication: any AppActivationPolicyApplying {
        Self.testHooks.activationPolicyApplication ?? NSApp
    }

    var resolvedRuntimeProjectionService: any RuntimeProjectionServing {
        Self.testHooks.runtimeProjectionService ?? sharedRuntimeProjectionService
    }

    var resolvedUpdateCoordinator: any FlowTabUpdateCoordinating {
        Self.testHooks.updateCoordinator
            ?? FlowTabUITestUpdateCoordinator.shared
    }

    var resolvedWorkspaceNotificationCenter: NotificationCenter {
        Self.testHooks.workspaceNotificationCenter ?? NSWorkspace.shared.notificationCenter
    }

    func signalWorkspaceAppActivated(_ app: NSRunningApplication) {
        guard !FlowTabTestLaunchOptions.usesMockRuntimeProjection else {
            resolvedRuntimeProjectionService.signalFocusedCurrentAppWindowsChanged()
            return
        }
        guard let appDirectoryEntry = RuntimeAppDirectoryFactSource.runningApplicationEntry(
            for: app
        ) else {
            return
        }
        resolvedRuntimeProjectionService.signalAppActivated(
            appID: RuntimeAppIdentity.appID(for: app),
            pid: app.processIdentifier,
            appDirectoryEntry: appDirectoryEntry
        )
    }

    func makeAppLaunchWindowEvidenceCoordinator()
        -> any RuntimeAppLaunchWindowEvidenceCoordinating
    {
        Self.testHooks.appLaunchWindowEvidenceCoordinator
            ?? makeDefaultAppLaunchWindowEvidenceCoordinator()
    }

    func makePanelController() -> SwitcherPanelController {
        Self.testHooks.makePanelController?() ?? SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: resolvedRuntimeProjectionService)
        )
    }

    func makeHotkeyMonitor(
        configuration: SwitcherHotkeyConfiguration,
        signature: OSType,
        forwardHotkeyID: UInt32,
        backwardHotkeyID: UInt32
    ) -> any HotkeyMonitoring {
        if let makeHotkeyMonitor = Self.testHooks.makeHotkeyMonitor {
            return makeHotkeyMonitor(
                configuration,
                signature,
                forwardHotkeyID,
                backwardHotkeyID
            )
        }
        return OptionTabHotkeyMonitor(
            configuration: configuration,
            signature: signature,
            forwardHotkeyID: forwardHotkeyID,
            backwardHotkeyID: backwardHotkeyID,
            startsMonitoring: false
        )
    }

    func currentHotkeyChordEventAccessSnapshot()
        -> HotkeyChordEventAccessSnapshot
    {
        Self.testHooks.hotkeyChordEventAccessSnapshotProvider?()
            ?? .current()
    }

    var hasPanelControllerForTesting: Bool {
        panelController != nil
    }

    var hasMainHotkeyMonitorForTesting: Bool {
        hotkeyMonitor != nil
    }

    var hasInAppHotkeyMonitorForTesting: Bool {
        inAppWindowHotkeyMonitor != nil
    }

    var hasHotkeyObserverForTesting: Bool {
        hotkeyObserver != nil
    }

    var hasAppVisibilityObserverForTesting: Bool {
        appVisibilityObserver != nil
    }

    var hasLanguageObserverForTesting: Bool {
        languageObserver != nil
    }

    var hasWorkspaceLifecycleObserverForTesting: Bool {
        !workspaceLifecycleObservers.isEmpty
    }

    var hasStatusItemForTesting: Bool {
        statusItem != nil
    }
}
#endif
