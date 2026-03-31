import XCTest
@testable import FlowTabApp
import FlowTabCore

final class FlowTabAppTests: XCTestCase {
    func testResolveKeepsCommandWhenMainShortcutIsCommandTab() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: SwitcherPrimaryModifier.command.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            quitKeyRaw: SwitcherHotkeyKey.q.rawValue
        )

        XCTAssertEqual(configuration.primaryModifier, .command)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
    }

    func testResolveFallsBackQuitKeyWhenQuitEqualsMainKey() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.q.rawValue,
            quitKeyRaw: SwitcherHotkeyKey.q.rawValue
        )

        XCTAssertEqual(configuration.mainKey, .q)
        XCTAssertEqual(configuration.quitKey, .w)
    }

    func testLoadPersistsNormalizedHotkeyValues() {
        let suiteName = "FlowTabAppTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults suite")
            return
        }

        userDefaults.set(
            SwitcherPrimaryModifier.command.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.hotkeyMainKey
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )

        let configuration = SwitcherHotkeyPreferencesStore.load(userDefaults: userDefaults)

        XCTAssertEqual(configuration.primaryModifier, .command)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyPrimaryModifier),
            SwitcherPrimaryModifier.command.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyMainKey),
            SwitcherHotkeyKey.tab.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey),
            SwitcherHotkeyKey.q.rawValue
        )

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testSearchMatchesAppByPartialName() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("fari"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Safari"])
    }

    func testSearchQuerySupportsMiddleInsertionViaCursorMovement() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("abcd"))
        XCTAssertTrue(coordinator.moveQueryCursor(by: -1))
        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("e"))

        XCTAssertEqual(coordinator.state.query, "abced")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 4)
    }

    func testSearchDeleteBackwardRespectsCursorPosition() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("abced"))
        XCTAssertTrue(coordinator.moveQueryCursor(by: -2))
        XCTAssertTrue(coordinator.deleteBackwardInQueryWithoutRebuild())

        XCTAssertEqual(coordinator.state.query, "abed")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 2)
    }

    func testSearchAppendWhileResultsFocusedUsesQueryTail() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("abcd"))
        XCTAssertTrue(coordinator.moveQueryCursor(by: -2))
        XCTAssertTrue(coordinator.focusResults())
        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("e"))

        XCTAssertEqual(coordinator.state.query, "abcde")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 5)
    }

    func testSearchDeleteWhileResultsFocusedUsesQueryTail() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("abcd"))
        XCTAssertTrue(coordinator.moveQueryCursor(by: -2))
        XCTAssertTrue(coordinator.focusResults())
        XCTAssertTrue(coordinator.deleteBackwardInQueryWithoutRebuild())

        XCTAssertEqual(coordinator.state.query, "abc")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 3)
    }

    func testSearchReplaceQueryWithoutRebuildUpdatesQueryAndCursor() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.replaceQueryWithoutRebuild("微信", cursorPosition: 1))

        XCTAssertEqual(coordinator.state.query, "微信")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 1)
    }

    func testSearchMatchesChineseAppByPinyinInitialsAndFullSpelling() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("wx"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])

        _ = coordinator.handleEscape()
        XCTAssertTrue(coordinator.appendQueryText("weixin"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])
    }

    func testSearchMatchesEnglishAbbreviation() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("vsc"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Visual Studio Code"])
    }

    func testSearchMatchesByBundleIDButNotGenericComPrefix() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("wechat"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])

        _ = coordinator.handleEscape()
        XCTAssertTrue(coordinator.appendQueryText("com"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertTrue(coordinator.state.results.isEmpty)
    }

    func testSearchRecoversResultsWhenIncrementalCandidateCacheMisses() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchCacheMissSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("t"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Tool"])

        XCTAssertTrue(coordinator.appendQueryText("e"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertTrue(
            coordinator.state.results.map(\.primaryText).contains("终端"),
            "Expected te to recover 终端 via full-scan fallback, got \(coordinator.state.results.map(\.primaryText))"
        )
    }

    func testWindowSearchCanMatchByAppNamePinyinInitials() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .window))

        XCTAssertTrue(coordinator.appendQueryText("wx"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.secondaryText), ["微信", "微信"])
    }

    func testSearchPerformanceWindowScope() {
        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let queries = benchmarkQueries()

        let buildNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
            _ = coordinator.activate(defaultScope: .window)
        }

        let rounds = 3
        let queryNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
            _ = coordinator.activate(defaultScope: .window)
            runBaselineQueries(queries, on: coordinator, rounds: rounds)
        }
        let buildMs = nanosToMilliseconds(buildNanos)
        let queryMs = nanosToMilliseconds(queryNanos)
        let queryCount = queries.count * rounds
        let qps = Double(queryCount) / max(0.001, queryMs / 1000.0)

        print(
            String(
                format: "[SearchPerformanceWindowScope] dataset=%d apps / %d windows, rounds=%d, build=%.2fms, query=%.2fms, queries=%d, throughput=%.2f qps",
                apps.count,
                apps.reduce(0) { $0 + $1.windows.count },
                rounds,
                buildMs,
                queryMs,
                queryCount,
                qps
            )
        )

        let probe = runBaselineProbe(query: "weixin", apps: apps, scope: .window)
        XCTAssertFalse(probe.isEmpty)
    }

    func testSearchPressureWindowScopeUnified() {
        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let queries = benchmarkQueries()
        let rounds = 3

        let buildNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
        }

        let queryNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
            _ = coordinator.activate(defaultScope: .window)
            runBaselineQueries(queries, on: coordinator, rounds: rounds)
        }

        let buildMs = nanosToMilliseconds(buildNanos)
        let queryMs = nanosToMilliseconds(queryNanos)
        let queryCount = queries.count * rounds
        let qps = Double(queryCount) / max(0.001, queryMs / 1000.0)

        print(
            String(
                format: "[SearchPressureUnified] dataset=%d apps / %d windows, rounds=%d, build=%.2fms, query=%.2fms, queries=%d, throughput=%.2f qps",
                apps.count,
                apps.reduce(0) { $0 + $1.windows.count },
                rounds,
                buildMs,
                queryMs,
                queryCount,
                qps
            )
        )

        let probe = runBaselineProbe(query: "weixin", apps: apps, scope: .window)
        XCTAssertFalse(probe.isEmpty)
    }

    private func searchSampleApps() -> [AppSwitchCandidate] {
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
                        title: "FlowTabApp - SwitcherSearchCoordinator.swift",
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
            )
        ]
    }

    private func makeBenchmarkApps(appCount: Int, windowsPerApp: Int) -> [AppSwitchCandidate] {
        precondition(appCount > 0)
        precondition(windowsPerApp > 0)

        let windowTopics = ["dashboard", "meeting", "design", "review", "bugfix", "roadmap", "notes"]
        var apps: [AppSwitchCandidate] = []
        apps.reserveCapacity(appCount)

        for appIndex in 0..<appCount {
            let app: (name: String, bundleID: String)
            switch appIndex % 5 {
            case 0:
                app = ("微信\(appIndex)", "com.tencent.xinWeChat\(appIndex)")
            case 1:
                app = ("Visual Studio Code \(appIndex)", "com.microsoft.VSCode\(appIndex)")
            case 2:
                app = ("Safari \(appIndex)", "com.apple.Safari\(appIndex)")
            case 3:
                app = ("Chrome \(appIndex)", "com.google.Chrome\(appIndex)")
            default:
                app = ("Notion \(appIndex)", "notion.id.\(appIndex)")
            }

            var windows: [WindowCandidate] = []
            windows.reserveCapacity(windowsPerApp)
            for windowIndex in 0..<windowsPerApp {
                let topic = windowTopics[(appIndex + windowIndex) % windowTopics.count]
                let title = "\(app.name) - \(topic) - w\(windowIndex)"
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

    private func benchmarkQueries() -> [String] {
        [
            "w", "wx", "we", "wei", "weix", "weixi", "weixin", "weixi", "wei", "we",
            "vs", "vsc", "vscode", "vscode 1", "vscode",
            "sa", "saf", "safa", "safari", "safari 2",
            "de", "des", "desi", "design", "design w2",
            "com", "tencent", "chrome", "road", "review",
            "wx9", "wx", "not", "notion", "meeting",
            "bug", "bugf", "bugfix", "notes", ""
        ]
    }

    private func searchCacheMissSampleApps() -> [AppSwitchCandidate] {
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

    private func runBaselineQueries(
        _ queries: [String],
        on coordinator: SwitcherSearchCoordinator,
        rounds: Int
    ) {
        var currentQuery = ""
        for _ in 0..<rounds {
            for query in queries {
                let prefixLength = commonPrefixLength(currentQuery, query)
                let deletes = currentQuery.count - prefixLength
                if deletes > 0 {
                    for _ in 0..<deletes {
                        _ = coordinator.deleteBackwardInQuery()
                    }
                }

                let suffix = String(query.dropFirst(prefixLength))
                if !suffix.isEmpty {
                    _ = coordinator.appendQueryText(suffix)
                } else if query.isEmpty && !coordinator.state.query.isEmpty {
                    while coordinator.deleteBackwardInQuery() {}
                }
                drainPendingSearchRebuild(on: coordinator)

                currentQuery = query
            }
        }
    }

    private func runBaselineProbe(
        query: String,
        apps: [AppSwitchCandidate],
        scope: SwitcherSearchScope
    ) -> [String] {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: apps)
        _ = coordinator.activate(defaultScope: scope)
        _ = coordinator.appendQueryText(query)
        drainPendingSearchRebuild(on: coordinator)
        return coordinator.state.results.prefix(10).map(\.id)
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
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

    private func measureNanos(_ block: () -> Void) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return DispatchTime.now().uptimeNanoseconds - start
    }

    private func nanosToMilliseconds(_ nanos: UInt64) -> Double {
        Double(nanos) / 1_000_000.0
    }

    private func drainPendingSearchRebuild(on coordinator: SwitcherSearchCoordinator) {
        coordinator.flushPendingRebuild()
    }
}
