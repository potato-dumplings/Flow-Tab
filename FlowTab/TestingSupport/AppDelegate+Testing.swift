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
    var commandTabTakeoverController: (any CommandTabTakeoverControlling)? = nil
    var stressRunner: (any TabSwitchStressRunning)? = nil
    var launchAtLoginManager: (any LaunchAtLoginManaging)? = nil
    var activationPolicyApplication: (any AppActivationPolicyApplying)? = nil
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

    func makePanelController() -> SwitcherPanelController {
        Self.testHooks.makePanelController?() ?? SwitcherPanelController()
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
            backwardHotkeyID: backwardHotkeyID
        )
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

    var hasStatusItemForTesting: Bool {
        statusItem != nil
    }
}
