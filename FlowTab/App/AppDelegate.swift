import AppKit
import FlowTabCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private(set) var panelController: SwitcherPanelController?
    private(set) var hotkeyMonitor: (any HotkeyMonitoring)?
    private(set) var inAppWindowHotkeyMonitor: (any HotkeyMonitoring)?
    private lazy var commandTabTakeoverController: any CommandTabTakeoverControlling = {
        Self.testHooks.commandTabTakeoverController ?? CommandTabTakeoverController()
    }()
    private(set) var statusItem: NSStatusItem?
    private(set) var hotkeyObserver: NSObjectProtocol?
    private(set) var appVisibilityObserver: NSObjectProtocol?
    private(set) var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        FlowTabUITestBootstrapper.prepareIfNeeded(userDefaults: resolvedUserDefaults)
        applyActivationPolicyFromPreferences()

        let panelController = makePanelController()
        self.panelController = panelController
        FlowTabUITestBootstrapper.configurePanelControllerIfNeeded(panelController: panelController)

        setupHotkeyMonitors(using: HotkeyRegistrationRequest.load(userDefaults: resolvedUserDefaults))
        installHotkeyObserver()
        installAppVisibilityObserver()
        installLanguageObserver()

        installStatusItem()
        requestAccessibilityPermissionIfNeeded()
        AppWindowCoordinator.openHome()
        resolvedStressRunner.startIfNeeded()
        FlowTabUITestBootstrapper.presentInitialUIIfNeeded(panelController: panelController)
    }

    private func requestAccessibilityPermissionIfNeeded() {
        let userDefaults = resolvedUserDefaults
        let shouldPromptPermissionReminder = userDefaults.object(forKey: AppPreferenceKeys.showPermissionReminder) == nil
            ? true
            : userDefaults.bool(forKey: AppPreferenceKeys.showPermissionReminder)
        guard shouldPromptPermissionReminder else { return }
        guard !AccessibilityPermissionChecker.isTrusted() else { return }
        guard !userDefaults.bool(forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission)
        else { return }

        _ = AccessibilityPermissionChecker.requestPermission()
        userDefaults.set(true, forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Self.shared === self {
            Self.shared = nil
        }
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
            self.hotkeyObserver = nil
        }
        if let appVisibilityObserver {
            NotificationCenter.default.removeObserver(appVisibilityObserver)
            self.appVisibilityObserver = nil
        }
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
            self.languageObserver = nil
        }
        hotkeyMonitor?.stop()
        inAppWindowHotkeyMonitor?.stop()
        commandTabTakeoverController.restoreSystemShortcutsIfNeeded()
    }

    func requestHotkeyReload(using request: HotkeyRegistrationRequest, source: String) {
        RuntimeLog.info(
            "HotKey",
            "re-register requested source=\(source) requestID=\(request.requestID.uuidString) main=\(request.mainConfiguration.mainShortcutText) inApp=\(request.inAppWindowConfiguration.mainShortcutText)"
        )
        applyHotkeyReload(request, source: source)
        NotificationCenter.default.post(
            name: .flowTabReRegisterHotkeys,
            object: self,
            userInfo: request.notificationUserInfo
        )
    }

    private func setupHotkeyMonitors(using request: HotkeyRegistrationRequest) {
        setupHotkeyMonitor(using: request)
        setupInAppWindowHotkeyMonitor(using: request)
    }

    private func applyHotkeyReload(_ request: HotkeyRegistrationRequest, source: String) {
        RuntimeLog.info(
            "HotKey",
            "re-register applying source=\(source) requestID=\(request.requestID.uuidString)"
        )
        setupHotkeyMonitors(using: request)
    }

    private func setupHotkeyMonitor(using request: HotkeyRegistrationRequest) {
        hotkeyMonitor?.stop()

        var hotkeyConfiguration = request.mainConfiguration
        let inAppHotkeyConfiguration = request.inAppWindowConfiguration
        let mainUsesCommandTab =
            hotkeyConfiguration.primaryModifier == .command && hotkeyConfiguration.mainKey == .tab
        let inAppUsesCommandTab =
            inAppHotkeyConfiguration.primaryModifier == .command && inAppHotkeyConfiguration.mainKey == .tab
        let takeoverReady = commandTabTakeoverController.reconcileIfNeeded(
            shouldTakeOver: mainUsesCommandTab || inAppUsesCommandTab
        )
        if mainUsesCommandTab, !takeoverReady {
            hotkeyConfiguration = SwitcherHotkeyConfiguration(
                primaryModifier: .option,
                mainKey: hotkeyConfiguration.mainKey,
                quitKey: hotkeyConfiguration.quitKey
            )
            RuntimeLog.info("HotKey", "fallback to Option+Tab because Command+Tab takeover failed")
        }

        let monitor = makeHotkeyMonitor(
            configuration: hotkeyConfiguration,
            signature: 0x46544142, // "FTAB"
            forwardHotkeyID: 1,
            backwardHotkeyID: 2
        )
        monitor.onHotkeyPressed = { [weak panelController] isBackward in
            panelController?.handleGlobalHotkey(isBackward: isBackward)
            RuntimeLog.info(
                "HotKey",
                isBackward ? "HotKey Backward" : "HotKey Forward"
            )
        }
        monitor.onHotkeyReleased = { [weak panelController] isBackward in
            panelController?.handleGlobalHotkeyReleased()
            RuntimeLog.info(
                "HotKey",
                isBackward ? "HotKey Backward Released" : "HotKey Forward Released"
            )
        }
        RuntimeLog.info(
            "HotKey",
            "register main=\(hotkeyConfiguration.mainShortcutText) backward=\(hotkeyConfiguration.backwardShortcutText) quit=\(hotkeyConfiguration.quitShortcutText)"
        )
        hotkeyMonitor = monitor
    }

    private func setupInAppWindowHotkeyMonitor(using request: HotkeyRegistrationRequest) {
        inAppWindowHotkeyMonitor?.stop()

        let mainConfiguration = request.mainConfiguration
        let inAppConfiguration = request.inAppWindowConfiguration
        if
            mainConfiguration.primaryModifier == inAppConfiguration.primaryModifier
                && mainConfiguration.mainKey == inAppConfiguration.mainKey
        {
            RuntimeLog.info("HotKey", "skip register in-app window hotkey due conflict with main shortcut")
            inAppWindowHotkeyMonitor = nil
            return
        }

        let monitor = makeHotkeyMonitor(
            configuration: inAppConfiguration,
            signature: 0x4654574E, // "FTWN"
            forwardHotkeyID: 101,
            backwardHotkeyID: 102
        )
        monitor.onHotkeyPressed = { [weak panelController] isBackward in
            panelController?.handleInAppWindowHotkey(isBackward: isBackward)
            RuntimeLog.info(
                "HotKey",
                isBackward ? "InApp Window Backward" : "InApp Window Forward"
            )
        }
        monitor.onHotkeyReleased = { [weak panelController] _ in
            panelController?.handleInAppWindowHotkeyReleased()
            RuntimeLog.info("HotKey", "InApp Window Released")
        }
        RuntimeLog.info(
            "HotKey",
            "register in-app main=\(inAppConfiguration.mainShortcutText) backward=\(inAppConfiguration.backwardShortcutText)"
        )
        inAppWindowHotkeyMonitor = monitor
    }

    private func installHotkeyObserver() {
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .flowTabReRegisterHotkeys,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let postedRequest = notification.userInfo.flatMap(HotkeyRegistrationRequest.init)
            let sendingDelegateID = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if Self.shared !== self {
                    if let postedRequest {
                        RuntimeLog.info(
                            "HotKey",
                            "re-register ignored source=notification_stale_delegate requestID=\(postedRequest.requestID.uuidString)"
                        )
                    } else {
                        RuntimeLog.info(
                            "HotKey",
                            "re-register ignored source=notification_stale_delegate requestID=missing_payload"
                        )
                    }
                    return
                }
                if sendingDelegateID == ObjectIdentifier(self) {
                    if let postedRequest {
                        RuntimeLog.info(
                            "HotKey",
                            "re-register ignored source=notification_self requestID=\(postedRequest.requestID.uuidString)"
                        )
                    } else {
                        RuntimeLog.info(
                            "HotKey",
                            "re-register ignored source=notification_self requestID=missing_payload"
                        )
                    }
                    return
                }
                guard let postedRequest else {
                    RuntimeLog.info(
                        "HotKey",
                        "re-register ignored source=notification_missing_payload"
                    )
                    return
                }
                RuntimeLog.info(
                    "HotKey",
                    "re-register requested source=notification_payload requestID=\(postedRequest.requestID.uuidString) main=\(postedRequest.mainConfiguration.mainShortcutText) inApp=\(postedRequest.inAppWindowConfiguration.mainShortcutText)"
                )
                self.applyHotkeyReload(postedRequest, source: "notification_payload")
            }
        }
    }

    private func installAppVisibilityObserver() {
        if let appVisibilityObserver {
            NotificationCenter.default.removeObserver(appVisibilityObserver)
        }
        appVisibilityObserver = NotificationCenter.default.addObserver(
            forName: .flowTabAppVisibilityPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyActivationPolicyFromPreferences()
            }
        }
    }

    private func installLanguageObserver() {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
        languageObserver = NotificationCenter.default.addObserver(
            forName: .flowTabLanguagePreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.installStatusItem()
            }
        }
    }

    private func applyActivationPolicyFromPreferences() {
        let showInCommandTab = AppVisibilityPreferencesStore.loadShowInCommandTab(
            userDefaults: resolvedUserDefaults
        )
        let targetPolicy: NSApplication.ActivationPolicy = showInCommandTab ? .regular : .accessory
        guard NSApp.activationPolicy() != targetPolicy else { return }

        NSApp.setActivationPolicy(targetPolicy)
        RuntimeLog.info(
            "App",
            "activationPolicy=\(showInCommandTab ? "regular" : "accessory")"
        )
    }

    private func installStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.length = NSStatusItem.squareLength
        item.menu = nil
        if let button = item.button {
            let icon = (NSImage(named: "MenuBarIcon")?.copy() as? NSImage)
                ?? (NSApp.applicationIconImage.copy() as? NSImage)
                ?? NSImage(named: NSImage.applicationIconName)
                ?? NSImage()
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            button.title = ""
            button.image = icon
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("FlowTab")
            button.target = self
            button.action = #selector(openAppFromStatusItem)
            button.sendAction(on: [.leftMouseUp])
        }
        statusItem = item
    }

    @objc
    private func openAppFromStatusItem() {
        handleStatusItemOpenAction(application: NSApp)
    }

    func handleStatusItemOpenAction(application: any AppWindowOpeningApplication) {
        AppWindowCoordinator.activateMainWindowOrOpenHomeScene(application: application)
    }
}
