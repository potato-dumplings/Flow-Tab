import AppKit
import Foundation
import FlowTabCore

extension RuntimeSnapshotProvider {
    struct UITestRuntimeDataset {
        let snapshot: RuntimeSnapshot
        let summaries: [RuntimeHomeAppSummary]
        let snapshotsByAppID: [String: RuntimeHomeAppSnapshot]
    }

    private static func uiTestAppDefinitions(
        variant: String?
    ) -> [(appID: String, name: String, windows: [WindowCandidate], rank: Int)] {
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
                    rank: item - 1
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
                    rank: 0
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
                    rank: 0
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
                    rank: 0
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
                    rank: 0
                ),
                (
                    appID: "com.flowtab.mock.browser",
                    name: "Mock Browser",
                    windows: [
                        WindowCandidate(id: "mock-browser-docs", title: "Docs", isMinimized: false, lastActiveAt: 290)
                    ],
                    rank: 1
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
                    rank: 2
                ),
                (
                    appID: "com.xxx.test",
                    name: "测试",
                    windows: [
                        WindowCandidate(id: "mock-test-cases", title: "用例", isMinimized: false, lastActiveAt: 280)
                    ],
                    rank: 3
                ),
                (
                    appID: "com.xxx.csgo",
                    name: "CSGO",
                    windows: [
                        WindowCandidate(id: "mock-csgo-dust2", title: "Dust2", isMinimized: false, lastActiveAt: 270)
                    ],
                    rank: 4
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
                    rank: 5
                )
            ]
        }
    }

    static func uiTestRuntimeDataset() -> UITestRuntimeDataset? {
        guard FlowTabTestLaunchOptions.usesMockRuntimeSnapshot else { return nil }

        let runningApp = NSRunningApplication.current
        let appDefinitions = uiTestAppDefinitions(variant: FlowTabTestLaunchOptions.mockRuntimeVariant)

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
                pid: pid_t(10_000 + index)
            )
        }

        let snapshotsByAppID = Dictionary(
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
                let snapshot = RuntimeHomeAppSnapshot(
                    summary: summaries[index],
                    candidate: candidates[index],
                    context: context
                )
                return (definition.appID, snapshot)
            }
        )

        return UITestRuntimeDataset(
            snapshot: RuntimeSnapshot(apps: candidates, contextsByID: [:]),
            summaries: summaries,
            snapshotsByAppID: snapshotsByAppID
        )
    }

    private static func mockCGWindowID(from windowID: String) -> CGWindowID? {
        let parts = windowID.split(separator: ":")
        guard parts.count == 3, parts[0] == "cg", let rawWindowID = UInt32(parts[2]) else {
            return nil
        }
        return CGWindowID(rawWindowID)
    }
}
