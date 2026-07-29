import AppKit
import Carbon
import FlowTabCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    static let statusItemIdentifier = "flowtab.status-item"
    static let statusItemQuitMenuItemIdentifier = "flowtab.status-item.quit"

    private(set) var panelController: SwitcherPanelController?
    private(set) var hotkeyMonitor: (any HotkeyMonitoring)?
    private(set) var inAppWindowHotkeyMonitor: (any HotkeyMonitoring)?
    private(set) var latestHotkeyRegistrationEvidence: HotkeyRegistrationEvidence?
    private var hotkeyRegistrationGeneration: UInt64 = 0
    private lazy var commandTabTakeoverController: any CommandTabTakeoverControlling = {
#if FLOWTAB_TESTING
        Self.testHooks.commandTabTakeoverController ?? CommandTabTakeoverController()
#else
        CommandTabTakeoverController()
#endif
    }()
    private lazy var launchAtLoginManager: any LaunchAtLoginManaging = {
        resolvedLaunchAtLoginManager
    }()
    private(set) var statusItem: NSStatusItem?
    private(set) var hotkeyObserver: NSObjectProtocol?
    private(set) var appVisibilityObserver: NSObjectProtocol?
    private(set) var languageObserver: NSObjectProtocol?
    private(set) var workspaceLifecycleObservers: [NSObjectProtocol] = []
    private var appLaunchWindowEvidenceCoordinator:
        (any RuntimeAppLaunchWindowEvidenceCoordinating)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
#if FLOWTAB_TESTING
        FlowTabUITestBootstrapper.prepareIfNeeded(userDefaults: resolvedUserDefaults)
#endif
        applyActivationPolicyFromPreferences(application: resolvedActivationPolicyApplication)
        syncLaunchAtLoginPreferenceOnLaunch()

        let panelController = makePanelController()
        self.panelController = panelController
#if FLOWTAB_TESTING
        FlowTabUITestBootstrapper.configurePanelControllerIfNeeded(panelController: panelController)
#endif

        setupHotkeyMonitors(using: HotkeyRegistrationRequest.load(userDefaults: resolvedUserDefaults))
        installHotkeyObserver()
        installAppVisibilityObserver()
        installLanguageObserver()
        appLaunchWindowEvidenceCoordinator = makeAppLaunchWindowEvidenceCoordinator()
        installWorkspaceLifecycleObserver()

        installStatusItem()
        requestAccessibilityPermissionIfNeeded()
#if FLOWTAB_TESTING
        if !FlowTabTestLaunchOptions.suppressesHomeWindowOnLaunch {
            AppWindowCoordinator.openHomeInCurrentProcess()
        }
        resolvedStressRunner.startIfNeeded()
        FlowTabUITestBootstrapper.presentInitialUIIfNeeded(panelController: panelController)
#else
        AppWindowCoordinator.openHomeInCurrentProcess()
#endif
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
        if !workspaceLifecycleObservers.isEmpty {
            for observer in workspaceLifecycleObservers {
                resolvedWorkspaceNotificationCenter.removeObserver(observer)
            }
            workspaceLifecycleObservers.removeAll()
        }
        appLaunchWindowEvidenceCoordinator?.stop()
        appLaunchWindowEvidenceCoordinator = nil
        hotkeyMonitor?.stop()
        inAppWindowHotkeyMonitor?.stop()
#if FLOWTAB_TESTING
        resolvedStressRunner.stop()
        FlowTabUITestBootstrapper
            .stopInitialPanelOcclusionStalenessInjection()
        FlowTabUITestBootstrapper
            .stopMockWindowPreviewLatencyInjection()
        FlowTabUITestBootstrapper
            .stopInitialUIPresentationObservation()
        FlowTabUITestProjectionAcknowledgementBootstrap.stop()
#endif
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

    @discardableResult
    func requestHotkeyReload(
        using request: HotkeyRegistrationRequest,
        source: String
    ) -> HotkeyRegistrationEvidence {
        RuntimeLog.info(
            .hotKey,
            "re-register requested source=\(source) requestID=\(request.requestID.uuidString) main=\(request.mainConfiguration.mainShortcutText) inApp=\(request.inAppWindowConfiguration.mainShortcutText)"
        )
        let evidence = applyHotkeyReload(request, source: source)
        NotificationCenter.default.post(
            name: .flowTabReRegisterHotkeys,
            object: self,
            userInfo: request.notificationUserInfo
        )
        return evidence
    }

    @discardableResult
    private func setupHotkeyMonitors(
        using request: HotkeyRegistrationRequest
    ) -> HotkeyRegistrationEvidence {
        let commandTabTakeoverActive = setupHotkeyMonitor(using: request)
        setupInAppWindowHotkeyMonitor(using: request)
        hotkeyRegistrationGeneration &+= 1
        let evidence = HotkeyRegistrationEvidence(
            generation: hotkeyRegistrationGeneration,
            request: request,
            commandTabTakeoverActive: commandTabTakeoverActive
        )
        latestHotkeyRegistrationEvidence = evidence
        RuntimeLog.info(
            .hotKey,
            "registration evidence generation=\(evidence.generation) requestID=\(evidence.requestID.uuidString) commandTabTakeoverActive=\(evidence.commandTabTakeoverActive)"
        )
        NotificationCenter.default.post(
            name: .flowTabHotkeyRegistrationEvidenceDidChange,
            object: self,
            userInfo: evidence.notificationUserInfo
        )
        return evidence
    }

    @discardableResult
    private func applyHotkeyReload(
        _ request: HotkeyRegistrationRequest,
        source: String
    ) -> HotkeyRegistrationEvidence {
        RuntimeLog.info(
            .hotKey,
            "re-register applying source=\(source) requestID=\(request.requestID.uuidString)"
        )
        return setupHotkeyMonitors(using: request)
    }

    private func setupHotkeyMonitor(using request: HotkeyRegistrationRequest) -> Bool {
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
        panelController?.registerHotkeyInputSource(
            monitor.inputSourceID,
            for: .globalAppSwitcher
        )
        monitor.onHotkeyEvent = { [weak panelController] event in
            panelController?.handleGlobalHotkeyInput(event)
            let direction = event.isBackward ? "Backward" : "Forward"
            let phase = event.phase == .pressed ? "" : " Released"
            RuntimeLog.debug(
                .hotKey,
                "HotKey \(direction)\(phase)"
            )
        }
        hotkeyMonitor = monitor
        monitor.start()
        RuntimeLog.info(
            .hotKey,
            "register main=\(hotkeyConfiguration.mainShortcutText) backward=\(hotkeyConfiguration.backwardShortcutText) quit=\(hotkeyConfiguration.quitShortcutText)"
        )
        return (mainUsesCommandTab || inAppUsesCommandTab) && takeoverReady
    }

    private func setupInAppWindowHotkeyMonitor(using request: HotkeyRegistrationRequest) {
        inAppWindowHotkeyMonitor?.stop()

        let mainConfiguration = request.mainConfiguration
        let inAppConfiguration = request.inAppWindowConfiguration
        if
            mainConfiguration.primaryModifier == inAppConfiguration.primaryModifier
                && mainConfiguration.mainKey == inAppConfiguration.mainKey
        {
            panelController?.unregisterHotkeyInputSource(
                for: .inAppWindowSwitcher
            )
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
        panelController?.registerHotkeyInputSource(
            monitor.inputSourceID,
            for: .inAppWindowSwitcher
        )
        monitor.onHotkeyEvent = { [weak panelController] event in
            panelController?.handleInAppWindowHotkeyInput(event)
            let direction = event.isBackward ? "Backward" : "Forward"
            let phase = event.phase == .pressed ? "" : " Released"
            RuntimeLog.debug(
                .hotKey,
                "InApp Window \(direction)\(phase)"
            )
        }
        inAppWindowHotkeyMonitor = monitor
        monitor.start()
        RuntimeLog.info(
            .hotKey,
            "register in-app main=\(inAppConfiguration.mainShortcutText) backward=\(inAppConfiguration.backwardShortcutText)"
        )
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
            MainActor.assumeIsolated {
                self?.handleHotkeyReloadNotification(notification)
            }
        }
    }

    private func handleHotkeyReloadNotification(_ notification: Notification) {
        let postedRequest =
            notification.userInfo.flatMap(HotkeyRegistrationRequest.init)
        let sendingDelegateID =
            (notification.object as AnyObject?).map(ObjectIdentifier.init)
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
        applyHotkeyReload(postedRequest, source: "notification_payload")
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
        if !workspaceLifecycleObservers.isEmpty {
            for observer in workspaceLifecycleObservers {
                resolvedWorkspaceNotificationCenter.removeObserver(observer)
            }
            workspaceLifecycleObservers.removeAll()
        }
        let didLaunchObserver = resolvedWorkspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let appID = RuntimeAppIdentity.appID(for: app)
            self.appLaunchWindowEvidenceCoordinator?.prepareObservation(
                appID: appID,
                pid: app.processIdentifier
            )
            self.resolvedRuntimeProjectionService.signalAppLaunched(
                appID: appID,
                pid: app.processIdentifier,
                appDirectoryEntry: RuntimeAppDirectoryEntry(app: app)
            )
        }
        let didTerminateObserver = resolvedWorkspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let appID = RuntimeAppIdentity.appID(for: app)
            self.appLaunchWindowEvidenceCoordinator?.cancelObservation(
                appID: appID,
                pid: app.processIdentifier
            )
            self.resolvedRuntimeProjectionService.signalAppTerminated(
                appID: appID,
                pid: app.processIdentifier
            )
        }
        workspaceLifecycleObservers = [didLaunchObserver, didTerminateObserver]
    }

    func makeDefaultAppLaunchWindowEvidenceCoordinator()
        -> any RuntimeAppLaunchWindowEvidenceCoordinating
    {
        RuntimeAppLaunchWindowEvidenceCoordinator(
            onAppWindowChanged: { [weak self] appID, pid in
                self?.resolvedRuntimeProjectionService.signalAppWindowsChanged(
                    appID: appID,
                    pid: pid
                )
            },
            onAXWindowDestroyed: { [weak self] appID, pid, axWindowID in
                self?.resolvedRuntimeProjectionService.signalAXWindowDestroyed(
                    appID: appID,
                    pid: pid,
                    axWindowID: axWindowID
                )
            }
        )
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
#if FLOWTAB_TESTING
        if Self.testHooks.activationPolicyApplication != nil {
            return resolvedActivationPolicyApplication
        }
#endif
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
}
#endif
