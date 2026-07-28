import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

extension FlowTabTests {
    struct SearchPressureWorkload {
        let name: String
        let warmupQuery: String?
        let queries: [String]
        let expectedHits: [String]
        let expectedMisses: [String]
        let expectedFinalResultCount: Int?

        init(
            name: String,
            warmupQuery: String? = nil,
            queries: [String],
            expectedHits: [String] = [],
            expectedMisses: [String] = [],
            expectedFinalResultCount: Int? = nil
        ) {
            self.name = name
            self.warmupQuery = warmupQuery
            self.queries = queries
            self.expectedHits = expectedHits
            self.expectedMisses = expectedMisses
            self.expectedFinalResultCount = expectedFinalResultCount
        }
    }

    @MainActor
    func waitUntil(
        _ description: String,
        timeout: TimeInterval = 1.0,
        pollIntervalNanoseconds: UInt64 = 5_000_000,
        predicate: @MainActor @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return predicate()
    }

    func searchSampleApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.tencent.xinWeChat",
                displayName: "微信",
                groupID: "social",
                lastActiveAt: 310,
                windows: [
                    WindowCandidate(id: "wechat-1", title: "工作群", isMinimized: false, lastActiveAt: 310),
                    WindowCandidate(id: "wechat-2", title: "文件传输助手", isMinimized: false, lastActiveAt: 280)
                ]
            ),
            AppSwitchCandidate(
                id: "com.microsoft.VSCode",
                displayName: "Visual Studio Code",
                groupID: "dev",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(
                        id: "vscode-1",
                        title: "FlowTab - SwitcherSearchCoordinator.swift",
                        isMinimized: false,
                        lastActiveAt: 300
                    )
                ]
            ),
            AppSwitchCandidate(
                id: "com.apple.Safari",
                displayName: "Safari",
                groupID: "web",
                lastActiveAt: 200,
                windows: [
                    WindowCandidate(id: "safari-1", title: "Apple", isMinimized: false, lastActiveAt: 200)
                ]
            ),
            AppSwitchCandidate(
                id: "com.xxx.test",
                displayName: "测试",
                groupID: "qa",
                lastActiveAt: 190,
                windows: [
                    WindowCandidate(id: "test-1", title: "用例", isMinimized: false, lastActiveAt: 190)
                ]
            ),
            AppSwitchCandidate(
                id: "com.flowtab.search",
                displayName: "FlowTabSearch",
                groupID: "dev",
                lastActiveAt: 180,
                windows: [
                    WindowCandidate(
                        id: "flow-search-1",
                        title: "FlowTabSearchGuide",
                        isMinimized: false,
                        lastActiveAt: 180
                    )
                ]
            ),
            AppSwitchCandidate(
                id: "com.flowtab.file-transfer-assistant",
                displayName: "文件传输助手",
                groupID: "tools",
                lastActiveAt: 170,
                windows: [
                    WindowCandidate(
                        id: "file-transfer-1",
                        title: "最近文件",
                        isMinimized: false,
                        lastActiveAt: 170
                    )
                ]
            )
        ]
    }
    func searchSampleAppsForSharedCSQuery() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.xxx.csgo",
                displayName: "CSGO",
                groupID: "games",
                lastActiveAt: 200,
                windows: [
                    WindowCandidate(id: "csgo-1", title: "Dust2", isMinimized: false, lastActiveAt: 200)
                ]
            ),
            AppSwitchCandidate(
                id: "com.xxx.test",
                displayName: "测试",
                groupID: "qa",
                lastActiveAt: 190,
                windows: [
                    WindowCandidate(id: "test-1", title: "用例", isMinimized: false, lastActiveAt: 190)
                ]
            ),
            AppSwitchCandidate(
                id: "com.apple.Safari",
                displayName: "Safari",
                groupID: "web",
                lastActiveAt: 180,
                windows: [
                    WindowCandidate(id: "safari-1", title: "Apple", isMinimized: false, lastActiveAt: 180)
                ]
            )
        ]
    }
    func terminateScenarioApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: false, lastActiveAt: 300)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.code",
                displayName: "Code",
                groupID: "dev",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "code-1", title: "FlowTab", isMinimized: false, lastActiveAt: 290)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 280,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 280)
                ]
            )
        ]
    }
    func makeBenchmarkApps(appCount: Int, windowsPerApp: Int) -> [AppSwitchCandidate] {
        precondition(appCount > 0)
        precondition(windowsPerApp > 0)

        let windowTopics = ["dashboard", "meeting", "design", "review", "bugfix", "roadmap", "notes"]
        var apps: [AppSwitchCandidate] = []
        apps.reserveCapacity(appCount)

        for appIndex in 0..<appCount {
            let app: (name: String, bundleID: String, windowBaseTitle: String?)
            switch appIndex % 7 {
            case 0:
                app = ("微信\(appIndex)", "com.tencent.xinWeChat\(appIndex)", nil)
            case 1:
                app = ("Visual Studio Code \(appIndex)", "com.microsoft.VSCode\(appIndex)", nil)
            case 2:
                app = ("Safari \(appIndex)", "com.apple.Safari\(appIndex)", nil)
            case 3:
                app = ("Chrome \(appIndex)", "com.google.Chrome\(appIndex)", nil)
            case 4:
                app = (
                    "FlowTabSearch\(appIndex)",
                    "com.flowtab.search\(appIndex)",
                    "FlowTabSearchCoordinator"
                )
            case 5:
                app = (
                    "文件传输助手\(appIndex)",
                    "com.flowtab.fileTransferAssistant\(appIndex)",
                    "文件传输助手归档"
                )
            default:
                app = ("Notion \(appIndex)", "notion.id.\(appIndex)", nil)
            }

            var windows: [WindowCandidate] = []
            windows.reserveCapacity(windowsPerApp)
            for windowIndex in 0..<windowsPerApp {
                let topic = windowTopics[(appIndex + windowIndex) % windowTopics.count]
                let title: String
                if let windowBaseTitle = app.windowBaseTitle {
                    title = "\(windowBaseTitle)\(windowIndex) - \(topic)"
                } else {
                    title = "\(app.name) - \(topic) - w\(windowIndex)"
                }
                windows.append(
                    WindowCandidate(
                        id: "w-\(appIndex)-\(windowIndex)",
                        title: title,
                        isMinimized: false,
                        lastActiveAt: TimeInterval(appCount * windowsPerApp - appIndex * windowsPerApp - windowIndex)
                    )
                )
            }

            apps.append(
                AppSwitchCandidate(
                    id: app.bundleID,
                    displayName: app.name,
                    groupID: "bench-\(appIndex % 12)",
                    lastActiveAt: TimeInterval(appCount - appIndex),
                    windows: windows
                )
            )
        }
        return apps
    }
    func benchmarkQueries() -> [String] {
        [
            "w", "wx", "we", "wei", "weix", "weixi", "weixin", "weixi", "wei", "we",
            "vs", "vsc", "vscode", "vscode 1", "vscode",
            "sa", "saf", "safa", "safari", "safari 2",
            "de", "des", "desi", "design", "design w2",
            "com", "tencent", "chrome", "road", "review",
            "flow", "flow search", "文件", "文件助手",
            "wx9", "wx", "not", "notion", "meeting",
            "bug", "bugf", "bugfix", "notes", ""
        ]
    }
    func segmentedBenchmarkQueries() -> [String] {
        [
            "f", "fl", "flow", "flow ", "flow s", "flow se", "flow search",
            "flow sea", "flow", "flow search",
            "文", "文件", "文件助", "文件助手", "文件 助手",
            "文件助", "文件", "",
            "search", "search coor", "search coordinator", ""
        ]
    }
    func searchPressureWorkloadMatrix(windowCount: Int) -> [SearchPressureWorkload] {
        [
            SearchPressureWorkload(
                name: "short-prefix-cache",
                queries: [
                    "t", "te", "ten", "tenc", "tencent",
                    "te", "t", "wx", ""
                ],
                expectedHits: ["tencent", "wx"]
            ),
            SearchPressureWorkload(
                name: "high-hit",
                queries: [
                    "w", "com", "search", "review", "road", "notes", ""
                ],
                expectedHits: ["review", "notes"]
            ),
            SearchPressureWorkload(
                name: "segmented-long",
                queries: [
                    "f", "fl", "flow", "flow ",
                    "flow s", "flow se", "flow search",
                    "flow sea", "flow search coordinator", ""
                ],
                expectedHits: ["flow search", "flow search coordinator"]
            ),
            SearchPressureWorkload(
                name: "chinese",
                queries: [
                    "文", "文件", "文件助", "文件助手",
                    "文件 助手", "文件助", "文件", ""
                ],
                expectedHits: ["文件助手"]
            ),
            SearchPressureWorkload(
                name: "no-result-prefix-only",
                queries: [
                    "qxz", "qxzno", "qxznohit", "qxz-nohit-777"
                ],
                expectedMisses: ["qxz-nohit-777"]
            ),
            SearchPressureWorkload(
                name: "no-result",
                queries: [
                    "qxz", "qxzno", "qxznohit", "qxz-nohit-777", ""
                ],
                expectedMisses: ["qxz-nohit-777"]
            ),
            SearchPressureWorkload(
                name: "clear-query",
                warmupQuery: "review",
                queries: [""],
                expectedFinalResultCount: windowCount
            )
        ]
    }
    func searchCacheMissSampleApps() -> [AppSwitchCandidate] {
        var apps: [AppSwitchCandidate] = []
        apps.reserveCapacity(1_105)
        apps.append(
            AppSwitchCandidate(
                id: "com.sample.tool",
                displayName: "Tool",
                groupID: "cache-miss",
                lastActiveAt: 2_000,
                windows: []
            )
        )

        for index in 1...1_103 {
            apps.append(
                AppSwitchCandidate(
                    id: "com.sample.app\(index)",
                    displayName: "应用\(index)",
                    groupID: "cache-miss",
                    lastActiveAt: TimeInterval(2_000 - index),
                    windows: []
                )
            )
        }

        apps.append(
            AppSwitchCandidate(
                id: "com.apple.Terminal",
                displayName: "终端",
                groupID: "cache-miss",
                lastActiveAt: 1,
                windows: []
            )
        )
        return apps
    }
    func runBaselineQueries(
        _ queries: [String],
        on coordinator: SwitcherSearchCoordinator,
        rounds: Int
    ) {
        var currentQuery = coordinator.state.query
        for _ in 0..<rounds {
            for query in queries {
                let prefixLength = commonPrefixLength(currentQuery, query)
                let deletes = currentQuery.count - prefixLength
                if deletes > 0 {
                    for _ in 0..<deletes {
                        _ = coordinator.deleteBackwardInQueryWithoutRebuild()
                    }
                }

                let suffix = String(query.dropFirst(prefixLength))
                if !suffix.isEmpty {
                    _ = coordinator.appendQueryTextWithoutRebuild(suffix)
                } else if query.isEmpty && !coordinator.state.query.isEmpty {
                    while coordinator.deleteBackwardInQueryWithoutRebuild() {}
                }
                rebuildSearchResults(on: coordinator)

                currentQuery = query
            }
        }
    }
    func runBaselineProbe(
        query: String,
        apps: [AppSwitchCandidate],
        scope: SwitcherSearchScope
    ) -> [String] {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: runtimeSearchIndexProjection(from: apps))
        _ = coordinator.activate(defaultScope: scope)
        _ = coordinator.appendQueryTextWithoutRebuild(query)
        rebuildSearchResults(on: coordinator)
        return coordinator.state.results.prefix(10).map(\.id)
    }
    func runtimeSearchIndexProjection(
        from apps: [AppSwitchCandidate],
        generatedAt: TimeInterval = 1,
        sourceGeneration: RuntimeReadModelGeneration = RuntimeReadModelGeneration(projection: 1)
    ) -> RuntimeSearchIndexProjection {
        let appEntries = apps.map { app in
            RuntimeSearchAppIndexEntry(
                appID: app.id,
                appDisplayName: app.displayName,
                appGroupID: app.groupID,
                appLastActiveAt: app.lastActiveAt,
                searchIndex: SearchTextMatcher.buildIndex(for: app.displayName, identifier: app.id)
            )
        }
        let appSearchIndexes = Dictionary(uniqueKeysWithValues: appEntries.map { ($0.appID, $0.searchIndex) })
        let windowEntries = apps.flatMap { app -> [RuntimeSearchWindowIndexEntry] in
            let appSearchIndex = appSearchIndexes[app.id]
                ?? SearchTextMatcher.buildIndex(for: app.displayName, identifier: app.id)
            return app.windows.map { window in
                let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return RuntimeSearchWindowIndexEntry(
                    appID: app.id,
                    appDisplayName: app.displayName,
                    windowID: window.id,
                    windowTitle: title,
                    windowIsMinimized: window.isMinimized,
                    windowLastActiveAt: window.lastActiveAt,
                    windowSearchIndex: SearchTextMatcher.buildIndex(for: title),
                    appSearchIndex: appSearchIndex
                )
            }
        }
        return RuntimeSearchIndexProjection(
            appEntries: appEntries,
            windowEntries: windowEntries,
            freshness: RuntimeProjectionFreshness(
                generatedAt: generatedAt,
                sourceGeneration: sourceGeneration,
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: [],
                isCompleteForScope: true
            )
        )
    }
    func searchResultIDs(
        query: String,
        on coordinator: SwitcherSearchCoordinator,
        limit: Int = 10
    ) -> [String] {
        _ = coordinator.replaceQueryWithoutRebuild(query, cursorPosition: query.count)
        coordinator.rebuildResults(resetSelection: true)
        return coordinator.state.results.prefix(limit).map(\.id)
    }
    func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        for (left, right) in zip(lhs, rhs) {
            if left == right {
                count += 1
            } else {
                break
            }
        }
        return count
    }
    func measureNanos(_ block: () -> Void) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return DispatchTime.now().uptimeNanoseconds - start
    }
    func nanosToMilliseconds(_ nanos: UInt64) -> Double {
        Double(nanos) / 1_000_000.0
    }
    func latencySummary(samples: [Double]) -> (p50: Double, p95: Double, max: Double) {
        let sortedSamples = samples.sorted()
        guard !sortedSamples.isEmpty else {
            return (0, 0, 0)
        }

        func percentile(_ value: Double) -> Double {
            let index = min(
                sortedSamples.count - 1,
                Int((Double(sortedSamples.count - 1) * value).rounded())
            )
            return sortedSamples[index]
        }

        return (
            p50: percentile(0.50),
            p95: percentile(0.95),
            max: sortedSamples.last ?? 0
        )
    }
    func rebuildSearchResults(on coordinator: SwitcherSearchCoordinator) {
        coordinator.rebuildResults(resetSelection: true)
    }
    func withLaunchArgumentsForTesting(
        _ arguments: [String],
        environment: [String: String]? = [
            FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                FlowTabTestLaunchOptions.uiTestingEnvironmentValue
        ],
        _ body: () -> Void
    ) {
        let previousArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
        FlowTabTestLaunchOptions.argumentsOverrideForTesting = arguments
        FlowTabTestLaunchOptions.environmentOverrideForTesting = environment
        defer {
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousArguments
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousEnvironment
        }
        body()
    }
    func withLaunchArgumentsForTesting(
        _ arguments: [String],
        environment: [String: String]? = [
            FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                FlowTabTestLaunchOptions.uiTestingEnvironmentValue
        ],
        _ body: () async -> Void
    ) async {
        let previousArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
        FlowTabTestLaunchOptions.argumentsOverrideForTesting = arguments
        FlowTabTestLaunchOptions.environmentOverrideForTesting = environment
        defer {
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousArguments
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousEnvironment
        }
        await body()
    }
    func makeIsolatedUserDefaults() -> UserDefaults? {
        let suiteName = "FlowTabTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults suite")
            return nil
        }
        userDefaults.set(suiteName, forKey: "FlowTabTestsSuiteName")
        return userDefaults
    }
    func clearIsolatedUserDefaults(_ userDefaults: UserDefaults) {
        guard let suiteName = userDefaults.string(forKey: "FlowTabTestsSuiteName") else { return }
        userDefaults.removePersistentDomain(forName: suiteName)
    }
    func restoreUserDefaultsValue(
        _ value: Any?,
        forKey key: String,
        userDefaults: UserDefaults
    ) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
    func resetRuntimeLogsForTest() async {
        RuntimeDiagnostics.shared.clear()
        _ = await RuntimeDiagnostics.shared.makeReadSnapshot()
    }
}
