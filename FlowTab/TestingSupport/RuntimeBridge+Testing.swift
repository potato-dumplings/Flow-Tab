import AppKit
import Foundation
import FlowTabCore

enum FlowTabUITestMockRuntimeEffects {
    private static let lock = NSLock()
    private static var terminatedAppIDs: Set<String> = []
    private static var pidByAppID: [String: pid_t] = [:]
    private static var appIDByPID: [pid_t: String] = [:]
    private static var nextPID: pid_t = 72_000

    static func reset() {
        lock.lock()
        terminatedAppIDs = []
        pidByAppID = [:]
        appIDByPID = [:]
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
        appIDByPID[pid] = appID
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
            appIDByPID[pid] = appID
        }
        terminatedAppIDs.insert(appID)
        return pid
    }

    static func isProcessRunning(pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let appID = appIDByPID[pid] else { return true }
        return !terminatedAppIDs.contains(appID)
    }

    static func isTerminated(appID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return terminatedAppIDs.contains(appID)
    }
}

extension RuntimeSnapshotProvider {
    struct UITestRuntimeDataset {
        let snapshot: RuntimeSnapshot
        let summaries: [RuntimeHomeAppSummary]
        let repairPayloadsByAppID: [String: RuntimeAppWindowRepairPayload]
    }

    private typealias UITestAppDefinition = (
        appID: String,
        name: String,
        windows: [WindowCandidate],
        rank: Int,
        bundleURL: URL?
    )

    private static func uiTestAppDefinitions(
        variant: String?
    ) -> [UITestAppDefinition] {
        switch variant {
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

    static func uiTestRuntimeDataset() -> UITestRuntimeDataset? {
        guard FlowTabTestLaunchOptions.usesMockRuntimeSnapshot else { return nil }

        let runningApp = NSRunningApplication.current
        let availableAppDefinitions = uiTestAppDefinitions(variant: FlowTabTestLaunchOptions.mockRuntimeVariant)
            .filter { definition in
                !FlowTabTestLaunchOptions.enablesMockHotkeyEffects
                    || !FlowTabUITestMockRuntimeEffects.isTerminated(appID: definition.appID)
            }
        let candidateAppBundlePaths = Set(
            availableAppDefinitions.compactMap { standardizedAppBundlePath(for: $0.bundleURL) }
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
                        windowsByID: windowContexts
                    )
                )
            }
        )

        let repairPayloadsByAppID = Dictionary(
            uniqueKeysWithValues: appDefinitions.enumerated().map { index, definition in
                let windowContexts = Dictionary(uniqueKeysWithValues: definition.windows.map { window in
                    (
                        window.id,
                        RuntimeWindowContext(
                            id: window.id,
                            title: window.title,
                            isMinimized: window.isMinimized,
                            ownerPID: runningApp.processIdentifier,
                            cgWindowID: mockCGWindowID(from: window.id),
                            inferredTitleBarStyle: nil,
                            allowsPublicAXRecovery: mockCGWindowID(from: window.id) != nil
                        )
                    )
                })
                let context = RuntimeAppContext(
                    appID: definition.appID,
                    runningApp: runningApp,
                    windowsByID: windowContexts
                )
                let repairPayload = RuntimeAppWindowRepairPayload(
                    summary: summaries[index],
                    candidate: candidates[index],
                    context: context
                )
                return (definition.appID, repairPayload)
            }
        )

        return UITestRuntimeDataset(
            snapshot: RuntimeSnapshot(
                apps: candidates,
                contextsByID: FlowTabTestLaunchOptions.enablesMockHotkeyEffects ? contextsByAppID : [:]
            ),
            summaries: summaries,
            repairPayloadsByAppID: repairPayloadsByAppID
        )
    }

    private static func uiTestSummaryPID(
        for definition: UITestAppDefinition,
        runningApp: NSRunningApplication,
        fallbackIndex: Int
    ) -> pid_t {
        if definition.appID == baseAppID(for: runningApp) {
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
        if definition.appID == baseAppID(for: runningApp) {
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
        guard !shouldHideZeroWindowNestedApp(
            hasWindows: !definition.windows.isEmpty,
            bundleURL: definition.bundleURL,
            candidateAppBundlePaths: candidateAppBundlePaths
        ) else {
            return false
        }
        return shouldIncludeAppInAppLayer(
            hasWindows: !definition.windows.isEmpty,
            hasVisibleWindow: hasVisibleWindow,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        )
    }
}
