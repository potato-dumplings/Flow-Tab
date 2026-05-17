import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

extension FlowTabTests {
    func testSearchMatchesAppByPartialName() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("fari"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Safari"])
    }

    func testSearchDebouncedRebuildIgnoresStaleGeneration() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("fari"))
        let pendingRebuild = coordinator.pendingRebuildWorkItem
        coordinator.pendingRebuildGeneration &+= 1

        pendingRebuild?.perform()

        XCTAssertNotNil(coordinator.pendingRebuildWorkItem)
        XCTAssertNotEqual(coordinator.state.results.map(\.primaryText), ["Safari"])

        coordinator.flushPendingRebuild()

        XCTAssertNil(coordinator.pendingRebuildWorkItem)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Safari"])
    }

    func testSearchMatchesCamelCaseAppBySegmentedWords() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("flow search"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["FlowTabSearch"])
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

    func testSearchSelectionWrapsFromLastResultBackToFirstResult() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))
        XCTAssertTrue(coordinator.focusResults())

        XCTAssertTrue(coordinator.moveSelection(by: -1))
        XCTAssertEqual(coordinator.state.selectedResultIndex, coordinator.state.results.count - 1)
        XCTAssertEqual(coordinator.state.selectedResult?.primaryText, "文件传输助手")

        XCTAssertTrue(coordinator.moveSelection(by: 1))
        XCTAssertEqual(coordinator.state.selectedResultIndex, 0)
        XCTAssertEqual(coordinator.state.selectedResult?.primaryText, "微信")
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

    func testSearchMatchesChineseCompoundAppBySegmentedQueryWithoutSpaces() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("文件助手"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["文件传输助手"])
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

    func testSearchLocksChineseTestAppByPinyinInitials() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("c"))
        XCTAssertTrue(coordinator.appendQueryText("s"))
        drainPendingSearchRebuild(on: coordinator)

        XCTAssertEqual(coordinator.state.results.first?.primaryText, "测试")
        XCTAssertEqual(coordinator.state.selectedResult?.primaryText, "测试")
        XCTAssertEqual(coordinator.state.selectedResult?.kind, .app(appID: "com.xxx.test"))
    }

    func testSearchLocksChineseTestAppByBundleIDPrefixes() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        let expectedKind = SwitcherSearchResultKind.app(appID: "com.xxx.test")
        XCTAssertTrue(coordinator.appendQueryText("t"))
        drainPendingSearchRebuild(on: coordinator)
        let firstStepResults = Set(coordinator.state.results.map(\.primaryText))
        XCTAssertTrue(firstStepResults.contains("FlowTabSearch"), "Query \(coordinator.state.query)")
        XCTAssertTrue(firstStepResults.contains("测试"), "Query \(coordinator.state.query)")

        for suffix in ["e", "s", "t"] {
            XCTAssertTrue(coordinator.appendQueryText(suffix))
            drainPendingSearchRebuild(on: coordinator)
            XCTAssertEqual(coordinator.state.results.first?.primaryText, "测试", "Query \(coordinator.state.query)")
            XCTAssertEqual(coordinator.state.selectedResult?.primaryText, "测试", "Query \(coordinator.state.query)")
            XCTAssertEqual(coordinator.state.selectedResult?.kind, expectedKind, "Query \(coordinator.state.query)")
        }
    }

    func testSearchQueryCsMatchesBothCSGOAndChineseTestApp() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleAppsForSharedCSQuery())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("c"))
        XCTAssertTrue(coordinator.appendQueryText("s"))
        drainPendingSearchRebuild(on: coordinator)

        XCTAssertEqual(
            Set(coordinator.state.results.map(\.primaryText)),
            Set(["CSGO", "测试"])
        )
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

    func testWindowSearchMatchesCamelCaseTitleBySegmentedWords() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .window))

        XCTAssertTrue(coordinator.appendQueryText("search coordinator"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(
            coordinator.state.results.map(\.primaryText),
            ["FlowTab - SwitcherSearchCoordinator.swift"]
        )
    }

    @MainActor
    func testHiddenAppIDsFilterSwitcherAppLayerAndSearchIndex() {
        let defaults = UserDefaults.standard
        let previousHiddenAppIDs = defaults.object(forKey: AppPreferenceKeys.hiddenAppIDs)
        let previousSearchEnabled = defaults.object(forKey: AppPreferenceKeys.searchEnabled)
        let previousSearchDefaultScope = defaults.object(forKey: AppPreferenceKeys.searchDefaultScope)
        defer {
            restoreUserDefaultsValue(
                previousHiddenAppIDs,
                forKey: AppPreferenceKeys.hiddenAppIDs,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousSearchEnabled,
                forKey: AppPreferenceKeys.searchEnabled,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousSearchDefaultScope,
                forKey: AppPreferenceKeys.searchDefaultScope,
                userDefaults: defaults
            )
        }

        defaults.set([" com.example.mail ", "com.example.mail", ""], forKey: AppPreferenceKeys.hiddenAppIDs)
        defaults.set(true, forKey: AppPreferenceKeys.searchEnabled)
        defaults.set(SwitcherSearchScope.app.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)

        let model = LiveSwitcherModel()
        model.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.terminateScenarioApps(), contextsByID: [:])
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.session?.apps.map(\.id), ["com.example.code", "com.example.browser"])
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == "com.example.mail" }) ?? true)

        XCTAssertTrue(model.enterSearchMode())
        XCTAssertTrue(model.searchCoordinator.replaceQueryWithoutRebuild("Mail", cursorPosition: 4))
        model.searchCoordinator.rebuildResults(resetSelection: true)
        model.publishSearchStateIfNeeded()
        XCTAssertTrue(model.searchViewState.results.isEmpty)

        XCTAssertTrue(model.searchCoordinator.replaceQueryWithoutRebuild("Inbox", cursorPosition: 5))
        XCTAssertTrue(model.toggleSearchScope())
        model.searchCoordinator.rebuildResults(resetSelection: true)
        model.publishSearchStateIfNeeded()
        XCTAssertEqual(model.searchScope, .window)
        XCTAssertTrue(model.searchViewState.results.isEmpty)
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

    func testSearchPressureWindowScopeSegmentedQueries() {
        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let queries = segmentedBenchmarkQueries()
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
                format: "[SearchPressureSegmented] dataset=%d apps / %d windows, rounds=%d, build=%.2fms, query=%.2fms, queries=%d, throughput=%.2f qps",
                apps.count,
                apps.reduce(0) { $0 + $1.windows.count },
                rounds,
                buildMs,
                queryMs,
                queryCount,
                qps
            )
        )

        XCTAssertFalse(runBaselineProbe(query: "flow search", apps: apps, scope: .window).isEmpty)
        XCTAssertFalse(runBaselineProbe(query: "文件助手", apps: apps, scope: .window).isEmpty)
    }

    @MainActor
    func testOptionTabFastStartPressureStaysUnderHundredMilliseconds() {
        let apps = makeBenchmarkApps(appCount: 600, windowsPerApp: 1).map { app in
            AppSwitchCandidate(
                id: app.id,
                displayName: app.displayName,
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt,
                windows: []
            )
        }
        let snapshot = RuntimeSnapshot(apps: apps, contextsByID: [:])
        let model = LiveSwitcherModel()
        model.frontmostApplicationOverride = { nil }
        model.fastAppSnapshotProviderOverride = { snapshot }
        var fullSnapshotCalls = 0
        model.snapshotProviderOverride = {
            fullSnapshotCalls += 1
            Thread.sleep(forTimeInterval: 0.2)
            return snapshot
        }

        let iterations = 120
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0)
            model.cancelSelection()
        }

        let summary = latencySummary(samples: samples)

        print(
            String(
                format: "[OptionTabFastStartPressure] dataset=%d apps, iterations=%d, p50=%.2fms, p95=%.2fms, max=%.2fms, fullSnapshotCalls=%d",
                apps.count,
                iterations,
                summary.p50,
                summary.p95,
                summary.max,
                fullSnapshotCalls
            )
        )

        XCTAssertEqual(fullSnapshotCalls, 0)
        XCTAssertLessThan(summary.p95, 100)
    }

    @MainActor
    func testOptionTabFastStartPressureIgnoresLargeFrontmostWindowSet() {
        let selectedWindowCount = 1_000
        let fullSnapshot = makeOptionTabWindowScaleSnapshot(
            selectedWindowCount: selectedWindowCount,
            extraAppCount: 120,
            largeWindowAppIndex: 0,
            includeRuntimeContexts: false
        )
        let fastSnapshot = appOnlySnapshot(from: fullSnapshot)
        let model = LiveSwitcherModel()
        model.frontmostApplicationOverride = { nil }
        model.fastAppSnapshotProviderOverride = { fastSnapshot }
        var fullSnapshotCalls = 0
        model.snapshotProviderOverride = {
            fullSnapshotCalls += 1
            Thread.sleep(forTimeInterval: 0.2)
            return fullSnapshot
        }

        let iterations = 80
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0)
            XCTAssertEqual(model.session?.selectedApp.windows.count ?? -1, 0)
            model.cancelSelection()
        }

        let summary = latencySummary(samples: samples)
        print(
            String(
                format: "[OptionTabFrontmostWindowScalePressure] apps=%d, frontmostWindows=%d, iterations=%d, p50=%.2fms, p95=%.2fms, max=%.2fms, fullSnapshotCalls=%d",
                fullSnapshot.apps.count,
                selectedWindowCount,
                iterations,
                summary.p50,
                summary.p95,
                summary.max,
                fullSnapshotCalls
            )
        )

        XCTAssertEqual(fullSnapshotCalls, 0)
        XCTAssertLessThan(summary.p95, 100)
    }

    @MainActor
    func testLiveSwitcherModelSnapshotInvalidationRecordTracksReasonAndScope() {
        let model = LiveSwitcherModel()
        model.deferredBackgroundFullSnapshotRefreshRequest = LiveSwitcherModel.BackgroundFullSnapshotRefreshRequest(
            triggerDirection: .forward,
            generation: model.backgroundFullSnapshotRefreshGeneration,
            scheduledMs: 10
        )

        model.invalidateBackgroundFullSnapshotRefresh(reason: .commitSelection)

        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.reason, .commitSelection)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.scope, .backgroundFullSnapshot)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.backgroundGeneration, 1)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.selectedAppWindowGeneration, 0)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.clearedDeferredBackgroundRequest, true)
        XCTAssertTrue(
            model.lastSnapshotInvalidationRecord?.logMessage.contains("reason=commitSelection") ?? false
        )

        model.deferredBackgroundFullSnapshotRefreshRequest = LiveSwitcherModel.BackgroundFullSnapshotRefreshRequest(
            triggerDirection: .forward,
            generation: model.backgroundFullSnapshotRefreshGeneration,
            scheduledMs: 20
        )

        model.invalidateSelectedAppWindowSnapshot(reason: .resetRuntimeState)

        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.reason, .resetRuntimeState)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.scope, .selectedAppWindowSnapshot)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.backgroundGeneration, 1)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.selectedAppWindowGeneration, 1)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.clearedDeferredBackgroundRequest, true)
    }

    @MainActor
    func testLiveSwitcherModelBackgroundRefreshDiagnosticTracksGenerationReasonAndApplyGeneration() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let fastApp = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: []
        )
        let fullApp = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: [
                WindowCandidate(
                    id: "window-1",
                    title: "Window 1",
                    isMinimized: false,
                    lastActiveAt: 100
                )
            ]
        )
        let fullContext = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "window-1": RuntimeWindowContext(
                    id: "window-1",
                    title: "Window 1",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier
                )
            ]
        )
        let model = LiveSwitcherModel()
        model.backgroundFullSnapshotRefreshEnabled = false
        model.fastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: [fastApp], contextsByID: [appID: fullContext])
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        let generation = model.backgroundFullSnapshotRefreshGeneration
        let startMs = LiveSwitcherModel.monotonicMilliseconds()
        model.completeBackgroundFullSnapshotRefresh(
            RuntimeSnapshot(apps: [fullApp], contextsByID: [appID: fullContext]),
            triggerDirection: .forward,
            generation: generation,
            reason: .startSession,
            startMs: startMs,
            snapshotReadMs: startMs
        )

        let diagnostic = model.lastBackgroundFullSnapshotRefreshDiagnostic
        XCTAssertEqual(diagnostic?.result, "applied")
        XCTAssertEqual(diagnostic?.generation, generation)
        XCTAssertEqual(diagnostic?.currentGeneration, generation)
        XCTAssertEqual(diagnostic?.reason, .startSession)
        XCTAssertEqual(diagnostic?.trigger, CycleDirection.forward.debugName)
        XCTAssertEqual(diagnostic?.applyGeneration, generation)
        XCTAssertTrue(diagnostic?.logMessage.contains("reason=startSession") ?? false)
        XCTAssertTrue(diagnostic?.logMessage.contains("applyGeneration=\(generation)") ?? false)
    }

    @MainActor
    func testOptionTabWindowScalePressureKeepsBackgroundApplyAndPreviewCaptureBounded() {
        let selectedWindowCount = 1_000
        let fullSnapshot = makeOptionTabWindowScaleSnapshot(
            selectedWindowCount: selectedWindowCount,
            extraAppCount: 80,
            largeWindowAppIndex: 1,
            includeRuntimeContexts: true
        )
        let fastSnapshot = appOnlySnapshot(from: fullSnapshot)
        let model = LiveSwitcherModel()
        model.frontmostApplicationOverride = { nil }
        model.backgroundFullSnapshotRefreshEnabled = false
        model.fastAppSnapshotProviderOverride = { fastSnapshot }
        var previewCaptureCalls = 0
        model.previewCaptureOverride = { _, _, _, _ in
            previewCaptureCalls += 1
            return nil
        }

        let iterations = 60
        var backgroundApplySamples: [Double] = []
        var windowLayerEntrySamples: [Double] = []
        var visiblePreviewItemSamples: [Double] = []
        backgroundApplySamples.reserveCapacity(iterations)
        windowLayerEntrySamples.reserveCapacity(iterations)
        visiblePreviewItemSamples.reserveCapacity(iterations)
        var visibleWindowCount = 0

        for _ in 0..<iterations {
            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertEqual(model.session?.selectedApp.windows.count ?? -1, 0)

            let applyStart = DispatchTime.now().uptimeNanoseconds
            let applyStartMs = LiveSwitcherModel.monotonicMilliseconds()
            model.completeBackgroundFullSnapshotRefresh(
                fullSnapshot,
                triggerDirection: .forward,
                generation: model.backgroundFullSnapshotRefreshGeneration,
                startMs: applyStartMs,
                snapshotReadMs: applyStartMs
            )
            backgroundApplySamples.append(
                Double(DispatchTime.now().uptimeNanoseconds - applyStart) / 1_000_000.0
            )
            XCTAssertEqual(model.session?.selectedApp.windows.count ?? -1, selectedWindowCount)

            let entryStart = DispatchTime.now().uptimeNanoseconds
            XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
            windowLayerEntrySamples.append(
                Double(DispatchTime.now().uptimeNanoseconds - entryStart) / 1_000_000.0
            )

            let page = SwitcherWindowPreviewPaging.page(
                itemCount: model.windowPreviewPageSummary().itemCount,
                selectedIndex: model.windowPreviewPageSummary().selectedIndex,
                availableWidth: 800
            )
            visibleWindowCount = page.visibleRange.count
            let previewItemsStart = DispatchTime.now().uptimeNanoseconds
            let previewItems = model.windowPreviewItems(visibleRange: page.visibleRange)
            visiblePreviewItemSamples.append(
                Double(DispatchTime.now().uptimeNanoseconds - previewItemsStart) / 1_000_000.0
            )
            XCTAssertEqual(previewItems.count, page.visibleRange.count)
            XCTAssertLessThan(previewItems.count, selectedWindowCount)
            model.cancelSelection()
        }

        let backgroundApply = latencySummary(samples: backgroundApplySamples)
        let windowLayerEntry = latencySummary(samples: windowLayerEntrySamples)
        let previewItems = latencySummary(samples: visiblePreviewItemSamples)
        print(
            String(
                format: "[OptionTabWindowScalePressure] apps=%d, selectedWindows=%d, visibleWindows=%d, iterations=%d, applyP95=%.2fms, enterP95=%.2fms, previewItemsP95=%.2fms, previewCaptureCalls=%d",
                fullSnapshot.apps.count,
                selectedWindowCount,
                visibleWindowCount,
                iterations,
                backgroundApply.p95,
                windowLayerEntry.p95,
                previewItems.p95,
                previewCaptureCalls
            )
        )

        XCTAssertLessThan(backgroundApply.p95, 50)
        XCTAssertLessThan(windowLayerEntry.p95, 50)
        XCTAssertLessThan(previewItems.p95, 50)
        XCTAssertLessThanOrEqual(previewCaptureCalls, iterations * max(visibleWindowCount, 1))
    }

    private func makeOptionTabWindowScaleSnapshot(
        selectedWindowCount: Int,
        extraAppCount: Int,
        largeWindowAppIndex: Int,
        includeRuntimeContexts: Bool
    ) -> RuntimeSnapshot {
        let selectedWindows = (0..<selectedWindowCount).map { index in
            WindowCandidate(
                id: "frontmost-window-\(index)",
                title: "Frontmost Document \(index)",
                isMinimized: false,
                lastActiveAt: TimeInterval(selectedWindowCount - index)
            )
        }
        let largeWindowApp = AppSwitchCandidate(
            id: "com.flowtab.pressure.frontmost",
            displayName: "Frontmost Pressure App",
            groupID: "pressure",
            lastActiveAt: TimeInterval(selectedWindowCount + extraAppCount),
            windows: selectedWindows
        )
        var apps = makeBenchmarkApps(appCount: extraAppCount, windowsPerApp: 1)
        apps.insert(largeWindowApp, at: min(max(0, largeWindowAppIndex), apps.count))
        guard includeRuntimeContexts else {
            return RuntimeSnapshot(apps: apps, contextsByID: [:])
        }

        let runningApp = NSRunningApplication.current
        let selectedWindowContexts = Dictionary(uniqueKeysWithValues: selectedWindows.enumerated().map { index, window in
            (
                window.id,
                RuntimeWindowContext(
                    id: window.id,
                    title: window.title,
                    isMinimized: window.isMinimized,
                    ownerPID: runningApp.processIdentifier,
                    cgWindowID: CGWindowID(10_000 + index),
                    allowsPublicAXRecovery: true
                )
            )
        })
        let selectedContext = RuntimeAppContext(
            appID: largeWindowApp.id,
            runningApp: runningApp,
            windowsByID: selectedWindowContexts
        )
        return RuntimeSnapshot(
            apps: apps,
            contextsByID: [largeWindowApp.id: selectedContext]
        )
    }

    private func appOnlySnapshot(from snapshot: RuntimeSnapshot) -> RuntimeSnapshot {
        RuntimeSnapshot(
            apps: snapshot.apps.map { app in
                AppSwitchCandidate(
                    id: app.id,
                    displayName: app.displayName,
                    groupID: app.groupID,
                    lastActiveAt: app.lastActiveAt,
                    windows: []
                )
            },
            contextsByID: [:]
        )
    }

}
