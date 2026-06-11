import AppKit
import FlowTabCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    static let statusItemIdentifier = "flowtab.status-item"
    static let statusItemQuitMenuItemIdentifier = "flowtab.status-item.quit"

    private(set) var panelController: SwitcherPanelController?
    private(set) var hotkeyMonitor: (any HotkeyMonitoring)?
    private(set) var inAppWindowHotkeyMonitor: (any HotkeyMonitoring)?
    private lazy var commandTabTakeoverController: any CommandTabTakeoverControlling = {
        Self.testHooks.commandTabTakeoverController ?? CommandTabTakeoverController()
    }()
    private lazy var launchAtLoginManager: any LaunchAtLoginManaging = {
        resolvedLaunchAtLoginManager
    }()
    private(set) var statusItem: NSStatusItem?
    private(set) var hotkeyObserver: NSObjectProtocol?
    private(set) var appVisibilityObserver: NSObjectProtocol?
    private(set) var languageObserver: NSObjectProtocol?
    private(set) var workspaceLifecycleObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        FlowTabUITestBootstrapper.prepareIfNeeded(userDefaults: resolvedUserDefaults)
        applyActivationPolicyFromPreferences(application: resolvedActivationPolicyApplication)
        syncLaunchAtLoginPreferenceOnLaunch()

        let panelController = makePanelController()
        self.panelController = panelController
        FlowTabUITestBootstrapper.configurePanelControllerIfNeeded(panelController: panelController)

        setupHotkeyMonitors(using: HotkeyRegistrationRequest.load(userDefaults: resolvedUserDefaults))
        installHotkeyObserver()
        installAppVisibilityObserver()
        installLanguageObserver()
        installWorkspaceLifecycleObserver()

        installStatusItem()
        requestAccessibilityPermissionIfNeeded()
        if !FlowTabTestLaunchOptions.suppressesHomeWindowOnLaunch {
            AppWindowCoordinator.openHomeInCurrentProcess()
        }
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
        if let workspaceLifecycleObserver {
            resolvedWorkspaceNotificationCenter.removeObserver(workspaceLifecycleObserver)
            self.workspaceLifecycleObserver = nil
        }
        hotkeyMonitor?.stop()
        inAppWindowHotkeyMonitor?.stop()
        commandTabTakeoverController.restoreSystemShortcutsIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @discardableResult
    func setLaunchAtLoginAllowed(_ allowed: Bool, source: String) -> LaunchAtLoginStatus {
        do {
            try launchAtLoginManager.reconcile(allowed: allowed)
            let currentStatus = launchAtLoginManager.status
            RuntimeLog.info(
                .permission,
                "launchAtLogin allowed=\(allowed) status=\(currentStatus.logValue) source=\(source)"
            )
            return currentStatus
        } catch {
            let currentStatus = launchAtLoginManager.status
            RuntimeLog.error(
                .permission,
                "launchAtLogin failed allowed=\(allowed) status=\(currentStatus.logValue) source=\(source) error=\(error.localizedDescription)"
            )
            return currentStatus
        }
    }

    func requestHotkeyReload(using request: HotkeyRegistrationRequest, source: String) {
        RuntimeLog.info(
            .hotKey,
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
            .hotKey,
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
            RuntimeLog.info(.hotKey, "fallback to Option+Tab because Command+Tab takeover failed")
        }

        let monitor = makeHotkeyMonitor(
            configuration: hotkeyConfiguration,
            signature: 0x46544142, // "FTAB"
            forwardHotkeyID: 1,
            backwardHotkeyID: 2
        )
        monitor.onHotkeyPressed = { [weak panelController] isBackward in
            panelController?.handleGlobalHotkey(isBackward: isBackward)
            RuntimeLog.debug(
                .hotKey,
                isBackward ? "HotKey Backward" : "HotKey Forward"
            )
        }
        monitor.onHotkeyReleased = { [weak panelController] isBackward in
            panelController?.handleGlobalHotkeyReleased()
            RuntimeLog.debug(
                .hotKey,
                isBackward ? "HotKey Backward Released" : "HotKey Forward Released"
            )
        }
        RuntimeLog.info(
            .hotKey,
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
            RuntimeLog.info(.hotKey, "skip register in-app window hotkey due conflict with main shortcut")
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
            RuntimeLog.debug(
                .hotKey,
                isBackward ? "InApp Window Backward" : "InApp Window Forward"
            )
        }
        monitor.onHotkeyReleased = { [weak panelController] _ in
            panelController?.handleInAppWindowHotkeyReleased()
            RuntimeLog.debug(.hotKey, "InApp Window Released")
        }
        RuntimeLog.info(
            .hotKey,
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
                        RuntimeLog.debug(
                            .hotKey,
                            "re-register ignored source=notification_stale_delegate requestID=\(postedRequest.requestID.uuidString)"
                        )
                    } else {
                        RuntimeLog.warning(
                            .hotKey,
                            "re-register ignored source=notification_stale_delegate requestID=missing_payload"
                        )
                    }
                    return
                }
                if sendingDelegateID == ObjectIdentifier(self) {
                    if let postedRequest {
                        RuntimeLog.debug(
                            .hotKey,
                            "re-register ignored source=notification_self requestID=\(postedRequest.requestID.uuidString)"
                        )
                    } else {
                        RuntimeLog.warning(
                            .hotKey,
                            "re-register ignored source=notification_self requestID=missing_payload"
                        )
                    }
                    return
                }
                guard let postedRequest else {
                    RuntimeLog.warning(
                        .hotKey,
                        "re-register ignored source=notification_missing_payload"
                    )
                    return
                }
                RuntimeLog.info(
                    .hotKey,
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

    private func installWorkspaceLifecycleObserver() {
        if let workspaceLifecycleObserver {
            resolvedWorkspaceNotificationCenter.removeObserver(workspaceLifecycleObserver)
        }
        workspaceLifecycleObserver = resolvedWorkspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let appID = RuntimeSnapshotProvider.baseAppID(for: app)
            self.resolvedRuntimeSnapshotService.signalAppTerminated(
                appID: appID,
                pid: app.processIdentifier
            )
        }
    }

    func applyActivationPolicyFromPreferences() {
        applyActivationPolicyFromPreferences(application: resolvedActivationPolicyApplication)
    }

    func applyActivationPolicyFromPreferences(application: any AppActivationPolicyApplying) {
        let showInCommandTab = AppVisibilityPreferencesStore.loadShowInCommandTab(
            userDefaults: resolvedUserDefaults
        )
        let targetPolicy: NSApplication.ActivationPolicy = showInCommandTab ? .regular : .accessory
        guard application.flowTabActivationPolicy != targetPolicy else { return }

        application.setFlowTabActivationPolicy(targetPolicy)
        RuntimeLog.info(
            .app,
            "activationPolicy=\(showInCommandTab ? "regular" : "accessory")"
        )
    }

    private func syncLaunchAtLoginPreferenceOnLaunch() {
        let allowed = LaunchAtLoginPreferencesStore.loadAllowLaunchAtLogin(
            userDefaults: resolvedUserDefaults
        )
        setLaunchAtLoginAllowed(allowed, source: "launch")
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
            button.toolTip = "FlowTab"
            button.setAccessibilityLabel("FlowTab")
            button.setFlowTabTestingIdentifier(Self.statusItemIdentifier)
            button.target = self
            button.action = #selector(handleStatusItemButtonAction(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        statusItem = item
    }

    @objc
    private func handleStatusItemButtonAction(_: NSStatusBarButton) {
        if isStatusItemMenuEvent(NSApp.currentEvent) {
            showStatusItemMenu()
        } else {
            handleStatusItemOpenAction(application: NSApp)
        }
    }

    func handleStatusItemOpenAction(application: any AppWindowOpeningApplication) {
        let activationPolicyApplication = statusItemActivationPolicyApplication(for: application)
        let shouldTemporarilyUseRegularActivation =
            activationPolicyApplication != nil
            && !AppVisibilityPreferencesStore.loadShowInCommandTab(userDefaults: resolvedUserDefaults)
        AppWindowCoordinator.activateMainWindowOrOpenHomeScene(
            application: application,
            activationPolicyApplication: activationPolicyApplication,
            temporarilyUseRegularActivation: shouldTemporarilyUseRegularActivation
        )
    }

    private func statusItemActivationPolicyApplication(
        for application: any AppWindowOpeningApplication
    ) -> (any AppActivationPolicyApplying)? {
        if let activationPolicyApplication = application as? any AppActivationPolicyApplying {
            return activationPolicyApplication
        }
        if Self.testHooks.activationPolicyApplication != nil {
            return resolvedActivationPolicyApplication
        }
        return nil
    }

    func handleStatusItemQuitAction(application: any AppTerminationRequesting) {
        application.terminate(nil)
    }

    func makeStatusItemMenu() -> NSMenu {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: AppStrings.text(
                .menuQuit,
                language: FlowPresentationState.shared.context.appLanguage
            ),
            action: #selector(quitFromStatusItem),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.identifier = NSUserInterfaceItemIdentifier(Self.statusItemQuitMenuItemIdentifier)
        menu.addItem(quitItem)
        return menu
    }

    private func showStatusItemMenu() {
        statusItem?.popUpMenu(makeStatusItemMenu())
    }

    private func isStatusItemMenuEvent(_ event: NSEvent?) -> Bool {
        guard let event else { return false }

        switch event.type {
        case .rightMouseDown, .rightMouseUp:
            return true
        case .leftMouseDown, .leftMouseUp:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    @objc
    private func quitFromStatusItem() {
        handleStatusItemQuitAction(application: NSApp)
    }
}
