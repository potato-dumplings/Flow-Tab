#if FLOWTAB_TESTING
import AppKit
import Foundation

@MainActor
enum FlowTabUITestBootstrapper {
    private static var hotkeyReloadDiagnosticsObserver: NSObjectProtocol?
    private static var switcherTriggerObservers: [SwitcherTriggerNotificationObserver] = []
    private static var switcherCommandObservers: [SwitcherCommandNotificationObserver] = []
    static var initialPanelOcclusionStalenessOwner:
        FlowTabUITestInitialPanelOcclusionStalenessOwner?
    private static var mockWindowPreviewLatencyGeneration:
        UInt64 = 0
    private static var mockWindowPreviewLatencyOwner:
        FlowTabUITestMockWindowPreviewLatencyOwner?
    private static var mockWindowPreviewLatencyCaptureReset:
        (() -> Void)?
    static var initialPresentationObservationOwner:
        FlowTabUITestInitialPresentationObservationOwner?

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
        static let runtimeLogProbe = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test.switcher-command.runtime-log-probe"
        )
    }

    static func prepareIfNeeded(userDefaults: UserDefaults = .standard) {
        stopInitialPanelOcclusionStalenessInjection()
        stopMockWindowPreviewLatencyInjection()
        stopInitialUIPresentationObservation()
        if FlowTabTestLaunchOptions.isRunningUITests {
            RuntimeWindowRecencyTracker.shared.removeAll()
        }

        installMockRuntimeProjectionServiceIfNeeded()
        installFrontmostRuntimeProjectionOverrideIfNeeded()
        FlowTabUITestProjectionAcknowledgementBootstrap
            .prepareIfNeeded(
                service: resolvedRuntimeProjectionService
            )

        if FlowTabTestLaunchOptions.resetsUserDefaultsOnLaunch {
            AppPreferenceKeys.allKeys.forEach { userDefaults.removeObject(forKey: $0) }
            userDefaults.removeObject(forKey: CommandTabTakeoverController.takeoverMarkerKey)
            HomeTabState.shared.selectedTab = .home
            RuntimeDiagnostics.shared.clear()
            FlowPresentationState.shared.refreshFromStoredPreferences()
        }

        if FlowTabTestLaunchOptions.enablesMockHotkeyEffects {
            FlowTabUITestMockRuntimeEffects.reset()
        }

        if let runtimeLogLevelRaw = FlowTabTestLaunchOptions.runtimeLogLevelOverrideRawValue {
            let resolved = RuntimeLogPreferencesStore.resolve(rawValue: runtimeLogLevelRaw)
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        }

        if FlowTabTestLaunchOptions.enablesVerboseRuntimeLogs {
            RuntimeDiagnosticSessionStore.start(userDefaults: userDefaults)
        }

        installHotkeyReloadDiagnosticsIfNeeded()
        seedWindowRecencyIfNeeded()

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

    static var resolvedRuntimeProjectionService: any RuntimeProjectionServing {
        AppDelegate.testHooks.runtimeProjectionService ?? sharedRuntimeProjectionService
    }

    static func synchronizeFrontmostAppOverrideIfNeeded() {
        guard let bundleIdentifier = FlowTabTestLaunchOptions.frontmostBundleIdentifierOverride else {
            return
        }
        guard let target = RuntimeUITestFrontmostAppTarget.resolve(bundleIdentifier: bundleIdentifier) else {
            RuntimeLog.info(
                "UITest",
                "frontmost bundle override result=missing bundleID=\(bundleIdentifier)"
            )
            return
        }

        SystemAppMRUTracker.shared.recordActivation(of: target.pid)
        let service = resolvedRuntimeProjectionService
        service.requestAppSwitcherProjectionMaintenance(reason: .appLifecycleRefresh)
        if let overrideService = service as? RuntimeUITestFrontmostProjectionService {
            overrideService.waitForMaintenanceQueueForTesting()
        } else {
            (service as? RuntimeProjectionService)?.waitForMaintenanceQueueForTesting()
        }
        RuntimeLog.info(
            "UITest",
            "frontmost bundle override result=applied bundleID=\(bundleIdentifier) pid=\(target.pid)"
        )
    }

    private static func installFrontmostRuntimeProjectionOverrideIfNeeded() {
        guard !FlowTabTestLaunchOptions.usesMockRuntimeProjection else { return }
        guard let bundleIdentifier = FlowTabTestLaunchOptions.frontmostBundleIdentifierOverride else {
            return
        }
        guard AppDelegate.testHooks.runtimeProjectionService == nil else { return }
        AppDelegate.testHooks.runtimeProjectionService = RuntimeUITestFrontmostProjectionService(
            baseService: sharedRuntimeProjectionService,
            bundleIdentifier: bundleIdentifier
        )
    }

    private static func installMockRuntimeProjectionServiceIfNeeded() {
        guard FlowTabTestLaunchOptions.usesMockRuntimeProjection else { return }
        guard AppDelegate.testHooks.runtimeProjectionService == nil else { return }
        let service = RuntimeProjectionService(
            label: "FlowTab.UITest.MockRuntimeProjectionService",
            appDirectoryProvider: RuntimeUITestProjectionAppDirectoryProvider()
        )
        AppDelegate.testHooks.runtimeProjectionService = service
        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()

        if AccessibilityPermissionChecker.isTrusted(),
           let dataset = FlowTabUITestRuntimeProjectionDataset.current() {
            for entry in dataset.appDirectoryEntries {
                service.signalAppWindowsChanged(appID: entry.appID, pid: entry.pid)
            }
            service.waitForMaintenanceQueueForTesting()
        }

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        service.waitForMaintenanceQueueForTesting()
    }

    private static func seedWindowRecencyIfNeeded() {
        guard let seed = FlowTabTestLaunchOptions.seededWindowRecency else { return }
        guard let payload = FlowTabUITestRuntimeProjectionDataset
            .current()?
            .currentAppWindowPayloadsByAppID[seed.appID]
        else {
            RuntimeLog.info(
                "UITest",
                "failed to seed window recency appID=\(seed.appID) windowID=\(seed.windowID) reason=missing_ui_test_projection_payload"
            )
            return
        }
        RuntimeWindowRecencyTracker.shared.record(
            appID: seed.appID,
            windowID: seed.windowID,
            context: payload.context
        )
        RuntimeLog.info(
            "UITest",
            "seeded window recency appID=\(seed.appID) windowID=\(seed.windowID)"
        )
    }

    static func configurePanelControllerIfNeeded(panelController: SwitcherPanelController) {
        installMockWindowPreviewsIfNeeded(panelController: panelController)

        if FlowTabTestLaunchOptions.suppressesPanelApplicationActivation {
            panelController.activateApplicationIgnoringOtherAppsOverride = {
                RuntimeLog.info("UITest", "suppressed panel application activation")
            }
        }

        installSwitcherTriggerNotificationsIfNeeded(panelController: panelController)
        installSwitcherCommandNotificationsIfNeeded(panelController: panelController)

        guard FlowTabTestLaunchOptions.enablesMockHotkeyEffects else { return }

        panelController.modelForTesting.terminateRequestOverride = { [weak panelController] appID in
            let pid = FlowTabUITestMockRuntimeEffects.recordTerminateRequest(appID: appID)
            RuntimeLog.info("UITest", "mock terminate request appID=\(appID) pid=\(pid)")
            Task { @MainActor [weak panelController] in
                panelController?.handleWorkspaceApplicationTerminatedForTesting(appID: appID, pid: pid)
            }
            return (sent: true, pid: pid)
        }
    }

    private static func installMockWindowPreviewsIfNeeded(
        panelController: SwitcherPanelController
    ) {
        stopMockWindowPreviewLatencyInjection()
        let model = panelController.modelForTesting
        model.previewCaptureOverride = nil
        model.previewCaptureBatchOverride = nil
        guard FlowTabTestLaunchOptions.usesMockWindowPreviews else { return }
        if let rawDelay = FlowTabTestLaunchOptions.mockWindowPreviewDelayMilliseconds {
            let policy =
                FlowTabUITestMockWindowPreviewLatencyPolicy(
                    rawMilliseconds: rawDelay
                )
            mockWindowPreviewLatencyGeneration &+= 1
            let owner =
                FlowTabUITestMockWindowPreviewLatencyOwner(
                    generation:
                        mockWindowPreviewLatencyGeneration,
                    policy: policy
                ) { evidence in
                    RuntimeLog.info(
                        "UITest",
                        "mock window preview latency "
                            + evidence.logFields
                    )
                }
            mockWindowPreviewLatencyOwner = owner
            let previewImage = makeMockWindowPreviewImage(
                title: "Delayed Preview",
                cgWindowID: nil
            )
            model.previewCaptureBatchOverride = {
                [weak owner] requests in
                guard let owner else {
                    return Array(
                        repeating: nil,
                        count: requests.count
                    )
                }
                let evidence = owner.waitBeforeCapture(
                    requestCount: requests.count
                )
                guard evidence.outcome == .elapsed else {
                    return Array(
                        repeating: nil,
                        count: requests.count
                    )
                }
                return requests.map { request in
                    RuntimeWindowPreviewProvider.CaptureResult(
                        image: previewImage,
                        resolvedWindowID: request.preferredWindowID
                            ?? stableMockWindowID(title: request.preferredTitle),
                        titleBarStyle: request.inferTitleBarStyle ? .dark : nil
                    )
                }
            }
            mockWindowPreviewLatencyCaptureReset = {
                [weak model] in
                model?.previewCaptureBatchOverride = nil
            }
            return
        }
        model.previewCaptureOverride = { cgWindowID, _, title, inferTitleBarStyle in
            (
                image: makeMockWindowPreviewImage(
                    title: title ?? "Window",
                    cgWindowID: cgWindowID
                ),
                resolvedWindowID: cgWindowID ?? stableMockWindowID(title: title),
                titleBarStyle: inferTitleBarStyle ? .dark : nil
            )
        }
    }

    static func stopMockWindowPreviewLatencyInjection() {
        mockWindowPreviewLatencyOwner?.cancel()
        mockWindowPreviewLatencyOwner = nil
        mockWindowPreviewLatencyCaptureReset?()
        mockWindowPreviewLatencyCaptureReset = nil
    }

    static var mockWindowPreviewLatencyGenerationForTesting:
        UInt64
    {
        mockWindowPreviewLatencyGeneration
    }

    static var isMockWindowPreviewLatencyInjectionActiveForTesting:
        Bool
    {
        mockWindowPreviewLatencyOwner != nil
    }

    private static func makeMockWindowPreviewImage(
        title: String,
        cgWindowID: CGWindowID?
    ) -> NSImage {
        let size = NSSize(width: 240, height: 150)
        let image = NSImage(size: size)
        image.lockFocus()
        let hueSeed = Double(Self.deterministicHash64(title) % 360) / 360.0
        NSColor(calibratedHue: hueSeed, saturation: 0.45, brightness: 0.82, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor.black.withAlphaComponent(0.24).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: size.height - 26, width: size.width, height: 26)).fill()
        let label = cgWindowID.map { "CG \($0)" } ?? title
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]
        (label as NSString).draw(
            in: NSRect(x: 12, y: size.height - 21, width: size.width - 24, height: 18),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
    }

    nonisolated static func deterministicMockWindowIDForTesting(title: String?) -> CGWindowID {
        stableMockWindowID(title: title)
    }

    nonisolated private static func stableMockWindowID(title: String?) -> CGWindowID {
        let seed = UInt32(Self.deterministicHash64(normalizedMockWindowTitle(title)) % 100_000)
        return CGWindowID(900_000 + seed)
    }

    nonisolated private static func deterministicHash64(_ value: String) -> UInt64 {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    nonisolated private static func normalizedMockWindowTitle(_ title: String?) -> String {
        let normalized = (title ?? "Window").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Window" : normalized
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
            ),
            SwitcherCommandNotificationObserver(
                name: SwitcherCommandNotification.runtimeLogProbe,
                panelController: panelController,
                command: .runtimeLogProbe
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
        FlowTabUITestBootstrapper.installInitialPanelOcclusionStaleOverrideIfNeeded(
            panelController: panelController
        )
        switch trigger {
        case .global:
            return panelController.presentGlobalHotkeySessionForTesting()
        case .inApp:
            FlowTabUITestBootstrapper.synchronizeFrontmostAppOverrideIfNeeded()
            return panelController.presentInAppWindowHotkeySessionForTesting()
        case .search:
            return panelController.presentSearchHotkeySessionForTesting()
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
        case runtimeLogProbe
    }

    private let name: Notification.Name
    private weak var panelController: SwitcherPanelController?
    private let command: Command
    private let hotkeyInputSourceID = HotkeyInputSourceID()
    private var hotkeyInputSequence: UInt64 = 0

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
        Task { @MainActor [weak self, panelController, notificationName, command] in
            guard let self else { return }
            RuntimeLog.info(
                "UITest",
                "received switcher command notification name=\(notificationName) command=\(command.rawValue)"
            )
            self.perform(command, panelController: panelController)
            RuntimeLog.info(
                "UITest",
                "completed switcher command notification name=\(notificationName) command=\(command.rawValue)"
            )
        }
    }

    @MainActor
    private func perform(
        _ command: Command,
        panelController: SwitcherPanelController
    ) {
        switch command {
        case .inAppForward:
            hotkeyInputSequence &+= 1
            panelController.registerHotkeyInputSource(
                hotkeyInputSourceID,
                for: .inAppWindowSwitcher
            )
            panelController.inAppPrimaryModifierPressedOverride = true
            panelController.handleInAppWindowHotkeyInput(
                HotkeyInputEvent(
                    identity: HotkeyInputEventIdentity(
                        sourceID: hotkeyInputSourceID,
                        sequence: hotkeyInputSequence
                    ),
                    phase: .pressed,
                    isBackward: false
                )
            )
            panelController.inAppPrimaryModifierPressedOverride = nil
        case .advanceDown:
            panelController.advance(.downArrow)
        case .advanceRight:
            panelController.advance(.rightArrow)
        case .searchQuery:
            guard let query = Self.switcherCommandPayload() else { return }
            panelController.modelForTesting.synchronizeSearchInput(
                query: query,
                cursorPosition: query.count
            )
        case .selectApp:
            guard
                let appID = Self.switcherCommandPayload()?
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
                let resultID = Self.switcherCommandPayload()?
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
        case .runtimeLogProbe:
            RuntimeDiagnostics.shared.log(
                level: .info,
                category: "UITest",
                message: "runtime log observation probe"
            )
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
#endif
