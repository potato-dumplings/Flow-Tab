#if FLOWTAB_TESTING
import AppKit
import Foundation
import FlowTabCore

enum FlowTabUITestMockRuntimeEffects {
    private static let lock = NSLock()
    private static var terminatedAppIDs: Set<String> = []
    private static var pidByAppID: [String: pid_t] = [:]
    private static var nextPID: pid_t = 72_000

    static func reset() {
        lock.lock()
        terminatedAppIDs = []
        pidByAppID = [:]
        nextPID = 72_000
        lock.unlock()
    }

    static func pid(for appID: String) -> pid_t {
        lock.lock()
        defer { lock.unlock() }

        if let existingPID = pidByAppID[appID] {
            return existingPID
        }

        let pid = nextPID
        nextPID += 1
        pidByAppID[appID] = pid
        return pid
    }

    static func recordTerminateRequest(appID: String) -> pid_t {
        lock.lock()
        defer { lock.unlock() }

        let pid: pid_t
        if let existingPID = pidByAppID[appID] {
            pid = existingPID
        } else {
            pid = nextPID
            nextPID += 1
            pidByAppID[appID] = pid
        }
        terminatedAppIDs.insert(appID)
        return pid
    }

    static func isTerminated(appID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return terminatedAppIDs.contains(appID)
    }
}

struct FlowTabUITestRuntimeProjectionDataset {
    let appSwitcherApps: [AppSwitchCandidate]
    let appSwitcherContextsByID: [String: RuntimeAppContext]
    let currentAppWindowPayloadsByAppID: [String: RuntimeCurrentAppWindowPayload]
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]

    private typealias UITestAppDefinition = (
        appID: String,
        name: String,
        windows: [WindowCandidate],
        rank: Int,
        bundleURL: URL?
    )

    private static let appPanelPressureCacheLock = NSLock()
    private static var appPanelPressureCache:
        [String: FlowTabUITestRuntimeProjectionDataset] = [:]
    private static var appPanelPressureBuildCount = 0

    private static func uiTestAppDefinitions(
        variant: String?
    ) -> [UITestAppDefinition] {
        switch variant {
        case FlowTabUITestAppPanelPressureFixture.realisticVariant:
            return appPanelPressureDefinitions(
                appCount:
                    FlowTabUITestAppPanelPressureFixture
                        .realisticAppCount,
                defaultWindowCount:
                    FlowTabUITestAppPanelPressureFixture
                        .realisticWindowCount,
                selectedAppWindowCount: nil
            )
        case FlowTabUITestAppPanelPressureFixture.extremeVariant:
            return appPanelPressureDefinitions(
                appCount:
                    FlowTabUITestAppPanelPressureFixture
                        .extremeAppCount,
                defaultWindowCount:
                    FlowTabUITestAppPanelPressureFixture
                        .extremeWindowCount,
                selectedAppWindowCount:
                    FlowTabUITestAppPanelPressureFixture
                        .extremeSelectedAppWindowCount
            )
        case FlowTabUITestApplicationMembershipFixture.variant:
            return [
                (
                    appID: FlowTabUITestApplicationMembershipFixture.stableAppID,
                    name: "Membership Stable",
                    windows: [
                        WindowCandidate(
                            id: "membership-stable-window",
                            title: "Stable Document",
                            isMinimized: false,
                            lastActiveAt: 400
                        )
                    ],
                    rank: 0,
                    bundleURL: nil
                ),
                (
                    appID: FlowTabUITestApplicationMembershipFixture.finalAccessoryAppID,
                    name: "Membership Final Accessory",
                    windows: [
                        WindowCandidate(
                            id: "membership-accessory-window",
                            title: "Stale Accessory Window",
                            isMinimized: false,
                            lastActiveAt: 399
                        )
                    ],
                    rank: 1,
                    bundleURL: nil
                )
            ]
        case FlowTabUITestAppVisibilityIdentityFixture.closedVariant,
             FlowTabUITestAppVisibilityIdentityFixture.accessoryVariant:
            return [
                (
                    appID: FlowTabUITestAppVisibilityIdentityFixture.configurableAppID,
                    name: "Identity Editor",
                    windows: [
                        WindowCandidate(
                            id: "identity-editor-main",
                            title: "Identity Document",
                            isMinimized: false,
                            lastActiveAt: 400
                        )
                    ],
                    rank: 0,
                    bundleURL: nil
                )
            ]
        case FlowTabUITestAppVisibilityIdentityFixture.regularVariant:
            return [
                (
                    appID: FlowTabUITestAppVisibilityIdentityFixture.configurableAppID,
                    name: "Identity Editor",
                    windows: [
                        WindowCandidate(
                            id: "identity-editor-main",
                            title: "Identity Document",
                            isMinimized: false,
                            lastActiveAt: 400
                        )
                    ],
                    rank: 0,
                    bundleURL: nil
                ),
                (
                    appID: FlowTabUITestAppVisibilityIdentityFixture.dynamicAppID,
                    name: "Identity Dynamic",
                    windows: [
                        WindowCandidate(
                            id: "identity-dynamic-main",
                            title: "Dynamic Document",
                            isMinimized: false,
                            lastActiveAt: 399
                        )
                    ],
                    rank: 1,
                    bundleURL: nil
                )
            ]
        case "search-wrap":
            return (1...10).map { item in
                let suffix = String(format: "%02d", item)
                let lastActiveAt = TimeInterval(401 - item)
                return (
                    appID: "com.flowtab.mock.wrap.\(suffix)",
                    name: "Mock Wrap \(suffix)",
                    windows: [
                        WindowCandidate(
                            id: "mock-wrap-\(suffix)-primary",
                            title: "MockWrap\(suffix)Window",
                            isMinimized: false,
                            lastActiveAt: lastActiveAt
                        )
                    ],
                    rank: item - 1,
                    bundleURL: nil
                )
            }
        case "single-app-five-windows":
            return [
                (
                    appID: "com.flowtab.mock.browser",
                    name: "Mock Browser",
                    windows: [
                        WindowCandidate(id: "mock-browser-normal-1", title: "Normal 1", isMinimized: false, lastActiveAt: 300),
                        WindowCandidate(id: "mock-browser-normal-2", title: "Normal 2", isMinimized: false, lastActiveAt: 299),
                        WindowCandidate(
                            id: "mock-browser-fullscreen-1",
                            title: "Fullscreen 1",
                            isMinimized: false,
                            lastActiveAt: 298
                        ),
                        WindowCandidate(
                            id: "mock-browser-fullscreen-2",
                            title: "Fullscreen 2",
                            isMinimized: false,
                            lastActiveAt: 297
                        ),
                        WindowCandidate(
                            id: "mock-browser-fullscreen-3",
                            title: "Fullscreen 3",
                            isMinimized: false,
                            lastActiveAt: 296
                        )
                    ],
                    rank: 0,
                    bundleURL: nil
                )
            ]
        case "single-app-many-windows":
            let windows = (0..<100).map { index in
                WindowCandidate(
                    id: String(format: "mock-many-window-%02d", index),
                    title: String(format: "Many Window %02d", index),
                    isMinimized: false,
                    lastActiveAt: TimeInterval(400 - index)
                )
            }
            return [
                (
                    appID: "com.flowtab.mock.many-windows",
                    name: "Mock Many Windows",
                    windows: windows,
                    rank: 0,
                    bundleURL: nil
                )
            ]
        case "focused-current-app":
            let currentAppID = Bundle.main.bundleIdentifier
                ?? "pid:\(ProcessInfo.processInfo.processIdentifier)"
            let currentAppName = ProcessInfo.processInfo.processName
            return [
                (
                    appID: currentAppID,
                    name: currentAppName,
                    windows: [
                        WindowCandidate(
                            id: "mock-current-primary",
                            title: "Current Primary",
                            isMinimized: false,
                            lastActiveAt: 300
                        ),
                        WindowCandidate(
                            id: "mock-current-secondary",
                            title: "Current Secondary",
                            isMinimized: false,
                            lastActiveAt: 299
                        )
                    ],
                    rank: 0,
                    bundleURL: nil
                )
            ]
        case "minimized-window-behavior":
            return [
                (
                    appID: "com.flowtab.mock.mail",
                    name: "Mock Mail",
                    windows: [
                        WindowCandidate(id: "mock-mail-inbox", title: "Inbox", isMinimized: false, lastActiveAt: 300),
                        WindowCandidate(id: "mock-mail-draft", title: "Draft", isMinimized: false, lastActiveAt: 299)
                    ],
                    rank: 0,
                    bundleURL: nil
                ),
                (
                    appID: "com.flowtab.mock.minimized-notes",
                    name: "Mock Minimized Notes",
                    windows: [
                        WindowCandidate(
                            id: "mock-minimized-notes-daily",
                            title: "Daily Notes",
                            isMinimized: true,
                            lastActiveAt: 290
                        ),
                        WindowCandidate(
                            id: "mock-minimized-notes-archive",
                            title: "Archive",
                            isMinimized: true,
                            lastActiveAt: 289
                        )
                    ],
                    rank: 1,
                    bundleURL: nil
                )
            ]
        case "nested-zero-window-apps":
            return [
                (
                    appID: "com.tencent.xinWeChat",
                    name: "WeChat",
                    windows: [
                        WindowCandidate(id: "mock-wechat-main", title: "微信", isMinimized: false, lastActiveAt: 300),
                        WindowCandidate(
                            id: "mock-wechat-app-ex-window",
                            title: "微信（窗口）",
                            isMinimized: false,
                            lastActiveAt: 299
                        ),
                        WindowCandidate(
                            id: "mock-wechat-mini-program",
                            title: "Mock Mini Program Window",
                            isMinimized: false,
                            lastActiveAt: 298
                        )
                    ],
                    rank: 0,
                    bundleURL: URL(fileURLWithPath: "/Applications/WeChat.app")
                ),
                (
                    appID: "com.tencent.flue.WeChatAppEx",
                    name: "WeChat",
                    windows: [],
                    rank: 1,
                    bundleURL: URL(fileURLWithPath: "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app")
                ),
                (
                    appID: "com.tencent.flue.WeApp",
                    name: "Mini Program",
                    windows: [],
                    rank: 2,
                    bundleURL: URL(fileURLWithPath: "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app")
                ),
                (
                    appID: "com.flowtab.mock.top-level-zero-window",
                    name: "Mock Top Level Zero Window",
                    windows: [],
                    rank: 3,
                    bundleURL: URL(fileURLWithPath: "/Applications/Mock Top Level Zero Window.app")
                )
            ]
        case "single-app-five-windows-cg-offspace":
            return [
                (
                    appID: "com.flowtab.mock.browser",
                    name: "Mock Browser",
                    windows: [
                        WindowCandidate(id: "cg:100:240001", title: "Normal 1", isMinimized: false, lastActiveAt: 300),
                        WindowCandidate(id: "cg:100:240002", title: "Normal 2", isMinimized: false, lastActiveAt: 299),
                        WindowCandidate(id: "cg:100:243747", title: "Window #3", isMinimized: false, lastActiveAt: 298),
                        WindowCandidate(id: "cg:100:243679", title: "Window #4", isMinimized: false, lastActiveAt: 297),
                        WindowCandidate(id: "cg:100:240029", title: "Window #5", isMinimized: false, lastActiveAt: 296)
                    ],
                    rank: 0,
                    bundleURL: nil
                )
            ]
        case "single-app-five-windows-cg-offspace-titled":
            return [
                (
                    appID: "com.flowtab.mock.browser",
                    name: "Mock Browser",
                    windows: [
                        WindowCandidate(id: "cg:100:240001", title: "Normal 1", isMinimized: false, lastActiveAt: 300),
                        WindowCandidate(id: "cg:100:240002", title: "Normal 2", isMinimized: false, lastActiveAt: 299),
                        WindowCandidate(id: "cg:100:243747", title: "Fullscreen 3", isMinimized: false, lastActiveAt: 298),
                        WindowCandidate(id: "cg:100:243679", title: "Fullscreen 4", isMinimized: false, lastActiveAt: 297),
                        WindowCandidate(id: "cg:100:240029", title: "Fullscreen 5", isMinimized: false, lastActiveAt: 296)
                    ],
                    rank: 0,
                    bundleURL: nil
                )
            ]
        default:
            return [
                (
                    appID: "com.flowtab.mock.mail",
                    name: "Mock Mail",
                    windows: [
                        WindowCandidate(id: "mock-mail-inbox", title: "Inbox", isMinimized: false, lastActiveAt: 300),
                        WindowCandidate(id: "mock-mail-draft", title: "Draft", isMinimized: false, lastActiveAt: 299)
                    ],
                    rank: 0,
                    bundleURL: nil
                ),
                (
                    appID: "com.flowtab.mock.browser",
                    name: "Mock Browser",
                    windows: [
                        WindowCandidate(id: "mock-browser-docs", title: "Docs", isMinimized: false, lastActiveAt: 290)
                    ],
                    rank: 1,
                    bundleURL: nil
                ),
                (
                    appID: "com.flowtab.mock.flow-search",
                    name: "FlowTabSearch",
                    windows: [
                        WindowCandidate(
                            id: "mock-flow-search-guide",
                            title: "FlowTabSearchGuide",
                            isMinimized: false,
                            lastActiveAt: 285
                        )
                    ],
                    rank: 2,
                    bundleURL: nil
                ),
                (
                    appID: "com.xxx.test",
                    name: "测试",
                    windows: [
                        WindowCandidate(id: "mock-test-cases", title: "用例", isMinimized: false, lastActiveAt: 280)
                    ],
                    rank: 3,
                    bundleURL: nil
                ),
                (
                    appID: "com.xxx.csgo",
                    name: "CSGO",
                    windows: [
                        WindowCandidate(id: "mock-csgo-dust2", title: "Dust2", isMinimized: false, lastActiveAt: 270)
                    ],
                    rank: 4,
                    bundleURL: nil
                ),
                (
                    appID: "com.flowtab.mock.file-transfer-assistant",
                    name: "文件传输助手",
                    windows: [
                        WindowCandidate(
                            id: "mock-file-transfer-assistant",
                            title: "最近文件",
                            isMinimized: false,
                            lastActiveAt: 260
                        )
                    ],
                    rank: 5,
                    bundleURL: nil
                )
            ]
        }
    }

    private static func appPanelPressureDefinitions(
        appCount: Int,
        defaultWindowCount: Int,
        selectedAppWindowCount: Int?
    ) -> [UITestAppDefinition] {
        (0..<appCount).map { appIndex in
            let windowCount = appIndex == 1
                ? selectedAppWindowCount
                    ?? defaultWindowCount
                : defaultWindowCount
            let windows = (0..<windowCount).map { windowIndex in
                WindowCandidate(
                    id: String(
                        format:
                            "app-panel-pressure-%04d-window-%04d",
                        appIndex,
                        windowIndex
                    ),
                    title: String(
                        format:
                            "Pressure App %04d Window %04d",
                        appIndex,
                        windowIndex
                    ),
                    isMinimized: false,
                    lastActiveAt:
                        TimeInterval(
                            1_000_000
                                - appIndex * 10_000
                                - windowIndex
                        )
                )
            }
            return (
                appID:
                    FlowTabUITestAppPanelPressureFixture
                        .appID(index: appIndex),
                name: String(
                    format: "Pressure App %04d",
                    appIndex
                ),
                windows: windows,
                rank: appIndex,
                bundleURL: nil
            )
        }
    }

    static func current() -> FlowTabUITestRuntimeProjectionDataset? {
        guard FlowTabTestLaunchOptions.usesMockRuntimeProjection else { return nil }

        let variant = FlowTabTestLaunchOptions.mockRuntimeVariant
        if !FlowTabTestLaunchOptions.enablesMockHotkeyEffects,
           FlowTabUITestAppPanelPressureFixture
            .contains(variant),
           let variant
        {
            return cachedAppPanelPressureDataset(
                variant: variant
            )
        }
        return buildCurrent(variant: variant)
    }

    static func resetAppPanelPressureCacheForTesting() {
        appPanelPressureCacheLock.lock()
        appPanelPressureCache = [:]
        appPanelPressureBuildCount = 0
        appPanelPressureCacheLock.unlock()
    }

    static var appPanelPressureBuildCountForTesting: Int {
        appPanelPressureCacheLock.lock()
        defer { appPanelPressureCacheLock.unlock() }
        return appPanelPressureBuildCount
    }

    private static func cachedAppPanelPressureDataset(
        variant: String
    ) -> FlowTabUITestRuntimeProjectionDataset {
        appPanelPressureCacheLock.lock()
        defer { appPanelPressureCacheLock.unlock() }
        if let cached = appPanelPressureCache[variant] {
            return cached
        }
        let dataset = buildCurrent(variant: variant)
        appPanelPressureCache[variant] = dataset
        appPanelPressureBuildCount += 1
        return dataset
    }

    private static func buildCurrent(
        variant: String?
    ) -> FlowTabUITestRuntimeProjectionDataset {

        let runningApp = NSRunningApplication.current
        let availableAppDefinitions = uiTestAppDefinitions(
            variant: variant
        )
            .filter { definition in
                !FlowTabTestLaunchOptions.enablesMockHotkeyEffects
                    || !FlowTabUITestMockRuntimeEffects.isTerminated(appID: definition.appID)
            }
        let candidateAppBundlePaths = Set(
            availableAppDefinitions.compactMap {
                RuntimeAppDirectory.standardizedAppBundlePath(for: $0.bundleURL)
            }
        )
        let appDefinitions = availableAppDefinitions
            .filter { definition in
                shouldIncludeUITestAppDefinitionInAppLayer(
                    definition,
                    candidateAppBundlePaths: candidateAppBundlePaths
                )
            }

        let candidates = appDefinitions.map { definition in
            AppSwitchCandidate(
                id: definition.appID,
                displayName: definition.name,
                groupID: "mock",
                lastActiveAt: -Double(max(definition.rank, 0)),
                windows: definition.windows
            )
        }

        let summaries = appDefinitions.enumerated().map { index, definition in
            RuntimeHomeAppSummary(
                appID: definition.appID,
                displayName: definition.name,
                groupID: "mock",
                lastActiveAt: -Double(max(definition.rank, 0)),
                windowCount: definition.windows.count,
                pid: uiTestSummaryPID(
                    for: definition,
                    runningApp: runningApp,
                    fallbackIndex: index
                )
            )
        }
        let appDirectoryEntries = appDefinitions.enumerated().map { index, definition in
            RuntimeAppDirectoryEntry(
                pid: summaries[index].pid,
                appID: definition.appID,
                bundleIdentifier: definition.appID,
                localizedName: definition.name,
                launchDate: nil,
                activationRank: index
            )
        }

        let contextsByAppID = Dictionary(
            uniqueKeysWithValues: appDefinitions.map { definition in
                let ownerPID = uiTestContextOwnerPID(
                    for: definition,
                    runningApp: runningApp
                )
                let windowContexts = Dictionary(uniqueKeysWithValues: definition.windows.map { window in
                    (
                        window.id,
                        RuntimeWindowContext(
                            id: window.id,
                            title: window.title,
                            isMinimized: window.isMinimized,
                            ownerPID: ownerPID,
                            cgWindowID: mockCGWindowID(from: window.id),
                            inferredTitleBarStyle: nil,
                            allowsPublicAXRecovery: mockCGWindowID(from: window.id) != nil
                        )
                    )
                })
                return (
                    definition.appID,
                    RuntimeAppContext(
                        appID: definition.appID,
                        runningApp: runningApp,
                        ownerPID: ownerPID,
                        windowsByID: windowContexts
                    )
                )
            }
        )

        let currentAppWindowPayloadsByAppID = Dictionary(
            uniqueKeysWithValues: appDefinitions.enumerated().map { index, definition in
                let windowContexts = Dictionary(uniqueKeysWithValues: definition.windows.map { window in
                    let ownerPID = uiTestContextOwnerPID(
                        for: definition,
                        runningApp: runningApp
                    )
                    return (
                        window.id,
                        RuntimeWindowContext(
                            id: window.id,
                            title: window.title,
                            isMinimized: window.isMinimized,
                            ownerPID: ownerPID,
                            cgWindowID: mockCGWindowID(from: window.id),
                            inferredTitleBarStyle: nil,
                            allowsPublicAXRecovery: mockCGWindowID(from: window.id) != nil
                        )
                    )
                })
                let context = RuntimeAppContext(
                    appID: definition.appID,
                    runningApp: runningApp,
                    ownerPID: appDirectoryEntries[index].pid,
                    windowsByID: windowContexts
                )
                let currentAppWindowPayload = RuntimeCurrentAppWindowPayload(
                    summary: summaries[index],
                    candidate: candidates[index],
                    context: context,
                    appDirectoryEntries: [appDirectoryEntries[index]]
                )
                return (definition.appID, currentAppWindowPayload)
            }
        )

        return FlowTabUITestRuntimeProjectionDataset(
            appSwitcherApps: candidates,
            appSwitcherContextsByID: FlowTabTestLaunchOptions.enablesMockHotkeyEffects ? contextsByAppID : [:],
            currentAppWindowPayloadsByAppID: currentAppWindowPayloadsByAppID,
            appDirectoryEntries: appDirectoryEntries
        )
    }

    func seedWindowRecordCoverage(
        in windowRecordStore: RuntimeWindowRecordStore
    ) -> RuntimeFullRepairWindowRecordRefreshEvidence {
        guard AccessibilityPermissionChecker.isTrusted() else {
            for entry in appDirectoryEntries {
                windowRecordStore.setState(
                    RuntimeWindowMappingState(hasRecordedWindowCollection: true),
                    for: entry.pid
                )
            }
            return RuntimeFullRepairWindowRecordRefreshEvidence(
                runningAppCount: appDirectoryEntries.count,
                projectedWindowPIDCount: appDirectoryEntries.count,
                projectedWindowCount: 0
            )
        }

        let seededAt = Date.timeIntervalSinceReferenceDate
        var seededPIDs: Set<pid_t> = []
        var projectedWindowCount = 0
        for payload in currentAppWindowPayloadsByAppID.values {
            var recordsByCGWindowID: [CGWindowID: RuntimeWindowRecord] = [:]
            var currentAXToCG: [String: CGWindowID] = [:]
            let ownerAXElement = AXUIElementCreateApplication(
                payload.context.runningApp.processIdentifier
            )
            for (index, window) in payload.candidate.windows.enumerated() {
                let context = payload.context.windowsByID[window.id]
                var cgWindowID = context?.cgWindowID ?? Self.syntheticCGWindowID(
                    appID: payload.summary.appID,
                    windowID: window.id
                )
                while recordsByCGWindowID[cgWindowID] != nil {
                    cgWindowID &+= 1
                }
                let axWindowID = context?.activationHandleID
                    ?? "ui-test:\(payload.summary.appID)#\(window.id)"
                let observedAt = seededAt - Double(index)
                var record = RuntimeWindowRecord(
                    cgWindowID: cgWindowID,
                    stableWindowID: window.id,
                    firstSeenAt: observedAt
                )
                record.lastKnownCGTitle = window.title
                record.lastKnownCGFrame = context?.frame
                record.lastKnownCGIsOnscreen = !window.isMinimized
                record.lastKnownDisplayTitle = window.title
                record.currentAXAttachment = RuntimeCurrentAXAttachment(
                    axWindowID: axWindowID,
                    axWindow: context?.axWindow ?? ownerAXElement,
                    title: window.title,
                    frame: context?.frame,
                    state: RuntimeAXWindowState(
                        isMinimized: window.isMinimized,
                        isFocused: index == 0,
                        isMain: index == 0
                    )
                )
                record.lastExactAXWindowID = axWindowID
                record.lastExactAXWindow = context?.axWindow ?? ownerAXElement
                record.lastConfirmationSource = .publicExactMatch
                record.lastExactConfirmedAt = observedAt
                recordsByCGWindowID[cgWindowID] = record
                currentAXToCG[axWindowID] = cgWindowID
            }
            windowRecordStore.setState(
                RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: recordsByCGWindowID,
                    currentAXToCG: currentAXToCG,
                    validCGWindowIDs: Set(recordsByCGWindowID.keys),
                    lastAXWindowIDs: Set(currentAXToCG.keys),
                    hasRecordedWindowCollection: true,
                    hasObservedAXWindowHandle: !recordsByCGWindowID.isEmpty
                ),
                for: payload.summary.pid
            )
            seededPIDs.insert(payload.summary.pid)
            projectedWindowCount += recordsByCGWindowID.count
        }
        for entry in appDirectoryEntries where !seededPIDs.contains(entry.pid) {
            windowRecordStore.setState(
                RuntimeWindowMappingState(hasRecordedWindowCollection: true),
                for: entry.pid
            )
        }
        return RuntimeFullRepairWindowRecordRefreshEvidence(
            runningAppCount: appDirectoryEntries.count,
            projectedWindowPIDCount: appDirectoryEntries.count,
            projectedWindowCount: projectedWindowCount
        )
    }

    private static func syntheticCGWindowID(appID: String, windowID: String) -> CGWindowID {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(appID)#\(windowID)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        let base: UInt64 = 900_000
        let range = UInt64(UInt32.max) - base
        return CGWindowID(base + (hash % range))
    }

    private static func uiTestSummaryPID(
        for definition: UITestAppDefinition,
        runningApp: NSRunningApplication,
        fallbackIndex: Int
    ) -> pid_t {
        if definition.appID == RuntimeAppIdentity.appID(for: runningApp) {
            return runningApp.processIdentifier
        }
        if FlowTabTestLaunchOptions.enablesMockHotkeyEffects {
            return FlowTabUITestMockRuntimeEffects.pid(for: definition.appID)
        }
        return pid_t(10_000 + fallbackIndex)
    }

    private static func uiTestContextOwnerPID(
        for definition: UITestAppDefinition,
        runningApp: NSRunningApplication
    ) -> pid_t {
        if definition.appID == RuntimeAppIdentity.appID(for: runningApp) {
            return runningApp.processIdentifier
        }
        return FlowTabTestLaunchOptions.enablesMockHotkeyEffects
            ? FlowTabUITestMockRuntimeEffects.pid(for: definition.appID)
            : runningApp.processIdentifier
    }

    private static func mockCGWindowID(from windowID: String) -> CGWindowID? {
        let parts = windowID.split(separator: ":")
        guard parts.count == 3, parts[0] == "cg", let rawWindowID = UInt32(parts[2]) else {
            return nil
        }
        return CGWindowID(rawWindowID)
    }

    private static func shouldIncludeUITestAppDefinitionInAppLayer(
        _ definition: UITestAppDefinition,
        candidateAppBundlePaths: Set<String>
    ) -> Bool {
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        let hasVisibleWindow = definition.windows.contains { !$0.isMinimized }
        guard !RuntimeAppDirectory.shouldHideZeroWindowNestedApp(
            hasWindows: !definition.windows.isEmpty,
            bundleURL: definition.bundleURL,
            candidateAppBundlePaths: candidateAppBundlePaths
        ) else {
            return false
        }
        return RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
            hasWindows: !definition.windows.isEmpty,
            hasVisibleWindow: hasVisibleWindow,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        )
    }
}

final class RuntimeUITestProjectionAppDirectoryProvider: RuntimeAppDirectoryProviding {
    private let lock = NSLock()
    private let sourceID = UUID()
    private let runningApplication: NSRunningApplication?
    private var revision: UInt64 = 0
    private var hasCapturedPresentationEvidence = false

    init(attachesRunningApplication: Bool = true) {
        runningApplication = attachesRunningApplication ? .current : nil
    }

    func appDirectoryEntriesForRuntimeMaintenance() -> [RuntimeAppDirectoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entriesForCurrentMembershipLocked()
    }

    func appDirectorySnapshotEvidenceForPresentation() -> RuntimeAppDirectorySnapshotEvidence {
        lock.lock()
        defer { lock.unlock() }
        hasCapturedPresentationEvidence = true
        return makeEvidenceLocked()
    }

    func appDirectorySnapshotEvidenceForRuntimeMaintenance() -> RuntimeAppDirectorySnapshotEvidence {
        lock.lock()
        defer { lock.unlock() }
        return makeEvidenceLocked()
    }

    private func makeEvidenceLocked() -> RuntimeAppDirectorySnapshotEvidence {
        revision &+= 1
        let entries = entriesForCurrentMembershipLocked()
        var identities = entries.map { entry in
            RuntimeAppProcessIdentity(
                appID: entry.appID,
                pid: entry.pid,
                isDirectoryMember: true,
                isSwitcherEligible: true
            )
        }
        if hasCapturedPresentationEvidence,
           FlowTabTestLaunchOptions.mockRuntimeVariant
                == FlowTabUITestApplicationMembershipFixture.variant,
           let excludedEntry = allRuntimeEntriesLocked().first(where: {
               $0.appID == FlowTabUITestApplicationMembershipFixture.finalAccessoryAppID
           }) {
            identities.append(
                RuntimeAppProcessIdentity(
                    appID: excludedEntry.appID,
                    pid: excludedEntry.pid,
                    isDirectoryMember: false,
                    isSwitcherEligible: false
                )
            )
        }
        return RuntimeAppDirectorySnapshotEvidence(
            sourceID: sourceID,
            revision: revision,
            capturedAt: Date.timeIntervalSinceReferenceDate,
            processIdentities: identities,
            entries: entries
        )
    }

    private func entriesForCurrentMembershipLocked() -> [RuntimeAppDirectoryEntry] {
        let entries = allRuntimeEntriesLocked()
        guard hasCapturedPresentationEvidence,
              FlowTabTestLaunchOptions.mockRuntimeVariant
                == FlowTabUITestApplicationMembershipFixture.variant
        else { return entries }
        return entries.filter {
            $0.appID != FlowTabUITestApplicationMembershipFixture.finalAccessoryAppID
        }
    }

    private func allRuntimeEntriesLocked() -> [RuntimeAppDirectoryEntry] {
        guard let dataset = FlowTabUITestRuntimeProjectionDataset.current() else { return [] }
        return dataset.appDirectoryEntries.map { entry in
            RuntimeAppDirectoryEntry(
                pid: entry.pid,
                appID: entry.appID,
                bundleIdentifier: entry.bundleIdentifier,
                localizedName: entry.localizedName,
                bundleURL: entry.bundleURL,
                launchDate: entry.launchDate,
                activationRank: entry.activationRank,
                runningApplication: runningApplication
            )
        }
    }
}
#endif
