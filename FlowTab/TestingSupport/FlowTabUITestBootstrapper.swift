import AppKit
import Foundation

@MainActor
enum FlowTabUITestBootstrapper {
    private static var hotkeyReloadDiagnosticsObserver: NSObjectProtocol?
    private static var switcherTriggerObservers: [SwitcherTriggerNotificationObserver] = []
    private static var switcherCommandObservers: [SwitcherCommandNotificationObserver] = []

    private enum SwitcherTriggerNotification {
        static let global = Notification.Name("io.github.potato-dumplings.flowtab.ui-test.open-global-switcher")
        static let inApp = Notification.Name("io.github.potato-dumplings.flowtab.ui-test.open-in-app-window-switcher")
        static let search = Notification.Name("io.github.potato-dumplings.flowtab.ui-test.open-window-search")
    }

    private enum SwitcherCommandNotification {
        static let inAppForward = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.in-app-forward"
        )
        static let advanceDown = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.advance-down"
        )
        static let advanceRight = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.advance-right"
        )
        static let searchQuery = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.search-query"
        )
        static let selectApp = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.select-app"
        )
        static let selectSearchResult = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.select-search-result"
        )
        static let searchConfirm = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.search-confirm"
        )
        static let confirm = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.confirm"
        )
    }

    static func prepareIfNeeded(userDefaults: UserDefaults = .standard) {
        if FlowTabTestLaunchOptions.resetsUserDefaultsOnLaunch {
            AppPreferenceKeys.allKeys.forEach { userDefaults.removeObject(forKey: $0) }
            userDefaults.removeObject(forKey: CommandTabTakeoverController.takeoverMarkerKey)
            HomeTabState.shared.selectedTab = .home
            RuntimeDiagnostics.shared.clear()
        }

        if FlowTabTestLaunchOptions.enablesMockHotkeyEffects {
            FlowTabUITestMockRuntimeEffects.reset()
        }

        if let runtimeLogLevelRaw = FlowTabTestLaunchOptions.runtimeLogLevelOverrideRawValue {
            let resolved = RuntimeLogPreferencesStore.resolve(rawValue: runtimeLogLevelRaw)
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        }

        if FlowTabTestLaunchOptions.enablesVerboseRuntimeLogs {
            userDefaults.set(true, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        }

        installHotkeyReloadDiagnosticsIfNeeded()

        if let seededLogCount = FlowTabTestLaunchOptions.seededLogCount {
            RuntimeDiagnostics.shared.clear()
            if seededLogCount > 0 {
                let seededLevels: [RuntimeLogLevel] = [.debug, .info, .warning, .error]
                for index in 1...seededLogCount {
                    let level = seededLevels[(index - 1) % seededLevels.count]
                    RuntimeDiagnostics.shared.log(
                        level: level,
                        category: "UITest",
                        message: "seeded-\(level.rawValue.lowercased())-log-\(index)"
                    )
                }
            }
        }
    }

    static func configurePanelControllerIfNeeded(panelController: SwitcherPanelController) {
        if let bundleIdentifier = FlowTabTestLaunchOptions.frontmostBundleIdentifierOverride {
            panelController.modelForTesting.frontmostApplicationOverride = {
                NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundleIdentifier)
                    .first { !$0.isTerminated }
            }
        }

        if FlowTabTestLaunchOptions.suppressesPanelApplicationActivation {
            panelController.activateApplicationIgnoringOtherAppsOverride = {
                RuntimeLog.info("UITest", "suppressed panel application activation")
            }
        }

        installSwitcherTriggerNotificationsIfNeeded(panelController: panelController)
        installSwitcherCommandNotificationsIfNeeded(panelController: panelController)

        guard FlowTabTestLaunchOptions.enablesMockHotkeyEffects else { return }

        panelController.modelForTesting.terminateRequestOverride = { appID in
            let pid = FlowTabUITestMockRuntimeEffects.recordTerminateRequest(appID: appID)
            RuntimeLog.info("UITest", "mock terminate request appID=\(appID) pid=\(pid)")
            return (sent: true, pid: pid)
        }
        panelController.modelForTesting.isProcessRunningOverride = { pid in
            FlowTabUITestMockRuntimeEffects.isProcessRunning(pid: pid)
        }
    }

    private static func installSwitcherTriggerNotificationsIfNeeded(
        panelController: SwitcherPanelController
    ) {
        guard FlowTabTestLaunchOptions.listensForSwitcherTriggerNotifications else { return }
        RuntimeLog.info("UITest", "installing switcher trigger Darwin notification observers")

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        switcherTriggerObservers.forEach { $0.uninstall(from: center) }
        switcherTriggerObservers = [
            SwitcherTriggerNotificationObserver(
                name: SwitcherTriggerNotification.global,
                panelController: panelController,
                trigger: .global
            ),
            SwitcherTriggerNotificationObserver(
                name: SwitcherTriggerNotification.inApp,
                panelController: panelController,
                trigger: .inApp
            ),
            SwitcherTriggerNotificationObserver(
                name: SwitcherTriggerNotification.search,
                panelController: panelController,
                trigger: .search
            )
        ]
        switcherTriggerObservers.forEach { $0.install(in: center) }
    }

    private static func installSwitcherCommandNotificationsIfNeeded(
        panelController: SwitcherPanelController
    ) {
        guard FlowTabTestLaunchOptions.listensForSwitcherTriggerNotifications else { return }
        RuntimeLog.info("UITest", "installing switcher command Darwin notification observers")

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        switcherCommandObservers.forEach { $0.uninstall(from: center) }
        switcherCommandObservers = [
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.inAppForward,
                panelController: panelController,
                command: .inAppForward
            ),
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.advanceDown,
                panelController: panelController,
                command: .advanceDown
            ),
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.advanceRight,
                panelController: panelController,
                command: .advanceRight
            ),
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.searchQuery,
                panelController: panelController,
                command: .searchQuery
            ),
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.selectApp,
                panelController: panelController,
                command: .selectApp
            ),
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.selectSearchResult,
                panelController: panelController,
                command: .selectSearchResult
            ),
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.searchConfirm,
                panelController: panelController,
                command: .searchConfirm
            ),
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.confirm,
                panelController: panelController,
                command: .confirm
            )
        ]
        switcherCommandObservers.forEach { $0.install(in: center) }
    }

    private static func installHotkeyReloadDiagnosticsIfNeeded() {
        guard FlowTabTestLaunchOptions.recordsHotkeyReloadDiagnostics else { return }
        if let hotkeyReloadDiagnosticsObserver {
            NotificationCenter.default.removeObserver(hotkeyReloadDiagnosticsObserver)
        }
        hotkeyReloadDiagnosticsObserver = NotificationCenter.default.addObserver(
            forName: .flowTabReRegisterHotkeys,
            object: nil,
            queue: .main
        ) { notification in
            guard let request = notification.userInfo.flatMap(HotkeyRegistrationRequest.init) else {
                RuntimeDiagnostics.shared.log(
                    level: .info,
                    category: "UITest",
                    message: "hotkeyReloadNotification sender=unknown payload=missing"
                )
                return
            }
            let sender = notification.object is AppDelegate ? "AppDelegate" : "notification-only"
            RuntimeDiagnostics.shared.log(
                level: .info,
                category: "UITest",
                message: "hotkeyReloadNotification sender=\(sender) main=\(request.mainConfiguration.mainShortcutText) inApp=\(request.inAppWindowConfiguration.mainShortcutText)"
            )
        }
    }

    static func presentInitialUIIfNeeded(panelController: SwitcherPanelController) {
        guard FlowTabTestLaunchOptions.opensSwitcherOnLaunch else { return }
        panelController.setModifierReleaseConfirmationSuppressedForTesting(true)

        Task { @MainActor in
            let retrySleepNanoseconds: UInt64 = 150_000_000
            let maxAttempts = 20
            let requiredStableSnapshotCount = 2
            var lastObservedSnapshotSignature: [String] = []
            var stableSnapshotCount = 0

            for attempt in 0..<maxAttempts {
                if presentLaunchSwitcher(panelController: panelController) {
                    let snapshotSignature = launchSwitcherSnapshotSignature(
                        panelController: panelController
                    )
                    if snapshotSignature == lastObservedSnapshotSignature {
                        stableSnapshotCount += 1
                    } else {
                        lastObservedSnapshotSignature = snapshotSignature
                        stableSnapshotCount = 1
                    }

                    if stableSnapshotCount >= requiredStableSnapshotCount {
                        if FlowTabTestLaunchOptions.entersSearchOnLaunch {
                            _ = panelController.enterSearchModeIfPossible()
                        }
                        return
                    }

                    panelController.cancelSelectionForTesting()
                } else {
                    lastObservedSnapshotSignature = []
                    stableSnapshotCount = 0
                }

                guard attempt < maxAttempts - 1 else { return }
                try? await Task.sleep(nanoseconds: retrySleepNanoseconds)
            }
        }
    }

    private static func presentLaunchSwitcher(panelController: SwitcherPanelController) -> Bool {
        if FlowTabTestLaunchOptions.opensInAppWindowSwitcherOnLaunch {
            return panelController.presentInAppWindowHotkeySessionForTesting()
        }
        return panelController.presentGlobalHotkeySessionForTesting()
    }

    private static func launchSwitcherSnapshotSignature(
        panelController: SwitcherPanelController
    ) -> [String] {
        guard let session = panelController.modelForTesting.session else { return [] }
        if FlowTabTestLaunchOptions.opensInAppWindowSwitcherOnLaunch {
            return session.apps.flatMap { app in
                [app.id] + app.windows.map(\.id)
            }
        }
        return session.apps.map(\.id)
    }
}

private final class SwitcherTriggerNotificationObserver: NSObject {
    enum Trigger: Sendable {
        case global
        case inApp
        case search
    }

    private let name: Notification.Name
    private weak var panelController: SwitcherPanelController?
    private let trigger: Trigger

    init(
        name: Notification.Name,
        panelController: SwitcherPanelController,
        trigger: Trigger
    ) {
        self.name = name
        self.panelController = panelController
        self.trigger = trigger
        super.init()
    }

    func install(in center: CFNotificationCenter?) {
        CFNotificationCenterAddObserver(
            center,
            UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            Self.handleDarwinNotification,
            name.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }

    func uninstall(from center: CFNotificationCenter?) {
        let notificationName = CFNotificationName(name.rawValue as CFString)
        CFNotificationCenterRemoveObserver(
            center,
            UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            notificationName,
            nil
        )
    }

    private static let handleDarwinNotification: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer else { return }
        let notificationObserver = Unmanaged<SwitcherTriggerNotificationObserver>
            .fromOpaque(observer)
            .takeUnretainedValue()
        notificationObserver.handleDarwinNotification(name: name.map { $0.rawValue as String })
    }

    private func handleDarwinNotification(name receivedName: String?) {
        guard let panelController else { return }
        let notificationName = receivedName ?? name.rawValue
        let trigger = trigger
        Task { @MainActor [panelController, notificationName, trigger] in
            panelController.setModifierReleaseConfirmationSuppressedForTesting(true)
            RuntimeLog.info("UITest", "received switcher trigger notification name=\(notificationName)")
            let presented = Self.presentSwitcher(trigger, panelController: panelController)
            RuntimeLog.info(
                "UITest",
                "completed switcher trigger notification name=\(notificationName) presented=\(presented ? 1 : 0)"
            )
        }
    }

    @MainActor
    private static func presentSwitcher(
        _ trigger: Trigger,
        panelController: SwitcherPanelController
    ) -> Bool {
        switch trigger {
        case .global:
            return panelController.presentGlobalHotkeySessionForTesting()
        case .inApp:
            return panelController.presentInAppWindowHotkeySessionForTesting()
        case .search:
            guard panelController.presentGlobalHotkeySessionForTesting() else { return false }
            _ = panelController.enterSearchModeIfPossible()
            return true
        }
    }
}

private final class SwitcherCommandNotificationObserver: NSObject {
    enum Command: String, Sendable {
        case inAppForward
        case advanceDown
        case advanceRight
        case searchQuery
        case selectApp
        case selectSearchResult
        case searchConfirm
        case confirm
    }

    private let name: Notification.Name
    private weak var panelController: SwitcherPanelController?
    private let command: Command

    init(
        name: Notification.Name,
        panelController: SwitcherPanelController,
        command: Command
    ) {
        self.name = name
        self.panelController = panelController
        self.command = command
        super.init()
    }

    func install(in center: CFNotificationCenter?) {
        CFNotificationCenterAddObserver(
            center,
            UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            Self.handleDarwinNotification,
            name.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }

    func uninstall(from center: CFNotificationCenter?) {
        let notificationName = CFNotificationName(name.rawValue as CFString)
        CFNotificationCenterRemoveObserver(
            center,
            UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            notificationName,
            nil
        )
    }

    private static let handleDarwinNotification: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer else { return }
        let notificationObserver = Unmanaged<SwitcherCommandNotificationObserver>
            .fromOpaque(observer)
            .takeUnretainedValue()
        notificationObserver.handleDarwinNotification(name: name.map { $0.rawValue as String })
    }

    private func handleDarwinNotification(name receivedName: String?) {
        guard let panelController else { return }
        let notificationName = receivedName ?? name.rawValue
        let command = command
        Task { @MainActor [panelController, notificationName, command] in
            RuntimeLog.info(
                "UITest",
                "received switcher command notification name=\(notificationName) command=\(command.rawValue)"
            )
            Self.perform(command, panelController: panelController)
            RuntimeLog.info(
                "UITest",
                "completed switcher command notification name=\(notificationName) command=\(command.rawValue)"
            )
        }
    }

    @MainActor
    private static func perform(
        _ command: Command,
        panelController: SwitcherPanelController
    ) {
        switch command {
        case .inAppForward:
            panelController.inAppPrimaryModifierPressedOverride = true
            panelController.handleInAppWindowHotkey(isBackward: false)
            panelController.inAppPrimaryModifierPressedOverride = nil
        case .advanceDown:
            panelController.advance(.downArrow)
        case .advanceRight:
            panelController.advance(.rightArrow)
        case .searchQuery:
            guard let query = switcherCommandPayload() else { return }
            panelController.modelForTesting.synchronizeSearchInput(
                query: query,
                cursorPosition: query.count
            )
        case .selectApp:
            guard
                let appID = switcherCommandPayload()?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !appID.isEmpty,
                var session = panelController.modelForTesting.session
            else {
                return
            }
            guard session.selectApp(withID: appID) else {
                RuntimeLog.info("UITest", "select app command missed appID=\(appID)")
                return
            }
            panelController.modelForTesting.session = session
            panelController.syncPanelAccessibilityAnchors()
            panelController.updatePanelSize()
            RuntimeLog.info("UITest", "select app command applied appID=\(appID)")
        case .selectSearchResult:
            guard
                let resultID = switcherCommandPayload()?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !resultID.isEmpty
            else {
                return
            }
            guard panelController.modelForTesting.selectSearchResult(withID: resultID) else {
                RuntimeLog.info("UITest", "select search result command missed resultID=\(resultID)")
                return
            }
            panelController.syncPanelAccessibilityAnchors()
            panelController.updatePanelSize()
            RuntimeLog.info("UITest", "select search result command applied resultID=\(resultID)")
        case .searchConfirm:
            if panelController.modelForTesting.isSearchActive {
                guard panelController.modelForTesting.applySelectedSearchResultToSession() else {
                    return
                }
            }
            panelController.finishSelection()
        case .confirm:
            panelController.finishSelection()
        }
    }

    private static func switcherCommandPayload() -> String? {
        guard let path = FlowTabTestLaunchOptions.switcherCommandPayloadPath else {
            RuntimeLog.info("UITest", "missing switcher command payload path")
            return nil
        }
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            RuntimeLog.info(
                "UITest",
                "failed to read switcher command payload path=\(path) error=\(error.localizedDescription)"
            )
            return nil
        }
    }
}
