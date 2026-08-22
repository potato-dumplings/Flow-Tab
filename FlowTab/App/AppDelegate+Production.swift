import AppKit
import Carbon

#if !FLOWTAB_TESTING
@MainActor
extension AppDelegate {
    var resolvedUserDefaults: UserDefaults {
        .standard
    }

    var resolvedLaunchAtLoginManager: any LaunchAtLoginManaging {
        LaunchAtLoginController.shared
    }

    var resolvedActivationPolicyApplication: any AppActivationPolicyApplying {
        NSApp
    }

    var resolvedRuntimeProjectionService: any RuntimeProjectionServing {
        sharedRuntimeProjectionService
    }

    var resolvedWorkspaceNotificationCenter: NotificationCenter {
        NSWorkspace.shared.notificationCenter
    }

    func signalWorkspaceAppActivated(_ app: NSRunningApplication) {
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
        makeDefaultAppLaunchWindowEvidenceCoordinator()
    }

    func makePanelController() -> SwitcherPanelController {
        SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: resolvedRuntimeProjectionService)
        )
    }

    func makeHotkeyMonitor(
        configuration: SwitcherHotkeyConfiguration,
        signature: OSType,
        forwardHotkeyID: UInt32,
        backwardHotkeyID: UInt32
    ) -> any HotkeyMonitoring {
        OptionTabHotkeyMonitor(
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
        .current()
    }
}
#endif
