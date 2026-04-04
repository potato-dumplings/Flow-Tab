import AppKit
import Foundation
import FlowTabCore

extension RuntimeSnapshotProvider {
    struct UITestRuntimeDataset {
        let snapshot: RuntimeSnapshot
        let summaries: [RuntimeHomeAppSummary]
        let snapshotsByAppID: [String: RuntimeHomeAppSnapshot]
    }

    static func uiTestRuntimeDataset() -> UITestRuntimeDataset? {
        guard FlowTabTestLaunchOptions.usesMockRuntimeSnapshot else { return nil }

        let runningApp = NSRunningApplication.current
        let appDefinitions: [(appID: String, name: String, windows: [WindowCandidate], rank: Int)] = [
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
                            cgWindowID: nil,
                            inferredTitleBarStyle: nil
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
}
