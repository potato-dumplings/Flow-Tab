import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

extension FlowTabTests {
    func testSwitcherPointerSelectionGateIgnoresInitialHoverUntilPointerMoves() {
        var gate = SwitcherPointerSelectionGate(movementThreshold: 1)

        gate.reset(currentLocation: CGPoint(x: 10, y: 10))

        XCTAssertFalse(gate.isArmed)
        XCTAssertFalse(gate.recordPointerMoved(to: CGPoint(x: 10.5, y: 10.5)))
        XCTAssertFalse(gate.isArmed)

        XCTAssertTrue(gate.recordPointerMoved(to: CGPoint(x: 11, y: 10)))
        XCTAssertTrue(gate.isArmed)
    }

    func testSwitcherPointerSelectionGateResetRequiresFreshMovement() {
        var gate = SwitcherPointerSelectionGate(movementThreshold: 1)

        gate.reset(currentLocation: CGPoint(x: 0, y: 0))
        XCTAssertTrue(gate.recordPointerMoved(to: CGPoint(x: 2, y: 0)))
        XCTAssertTrue(gate.isArmed)

        gate.reset(currentLocation: CGPoint(x: 2, y: 0))

        XCTAssertFalse(gate.isArmed)
        XCTAssertFalse(gate.recordPointerMoved(to: CGPoint(x: 2.5, y: 0)))
        XCTAssertTrue(gate.recordPointerMoved(to: CGPoint(x: 3.1, y: 0)))
    }

    func testSwitcherPointerAppStripHitTestMapsGlobalHoverToTile() {
        let appIDs = ["browser", "mail", "notes"]
        let frame = CGRect(x: 100, y: 200, width: 300, height: 72)

        XCTAssertEqual(
            SwitcherPointerAppStripHitTest.appID(
                at: CGPoint(x: 250, y: 236),
                in: frame,
                appIDs: appIDs,
                tileSize: 48,
                spacing: 12
            ),
            "mail"
        )
        XCTAssertNil(
            SwitcherPointerAppStripHitTest.appID(
                at: CGPoint(x: 220, y: 236),
                in: frame,
                appIDs: appIDs,
                tileSize: 48,
                spacing: 12
            )
        )
    }

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

    func testSearchSelectResultByIDMovesFocusToResults() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.selectResult(withID: "app:com.flowtab.search"))

        XCTAssertFalse(coordinator.state.isInputFocused)
        XCTAssertEqual(coordinator.state.selectedResult?.kind, .app(appID: "com.flowtab.search"))
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

    func testSearchMatchesEnglishCodeLikeSubsequence() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("vce"))
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

    func testSearchCanMatchChinesePinyinInitialPrefixBeyondExactInitials() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("wjc"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["文件传输助手"])
    }

    func testSearchIndexedCandidatesTreatSingleTermEmptyCoarseFilterAsCompleteMiss() {
        let apps = searchSampleApps()
        let entries = apps.map { app in
            SwitcherSearchCoordinator.AppEntry(
                appID: app.id,
                appDisplayName: app.displayName,
                searchIndex: SwitcherSearchCoordinator.buildSearchIndex(
                    for: app.displayName,
                    identifier: app.id
                )
            )
        }
        let invertedIndex = SwitcherSearchCoordinator.buildScopeInvertedIndex(
            from: entries.map(\.searchIndex)
        )

        let candidates = SwitcherSearchCoordinator.indexedCandidates(
            query: SwitcherSearchCoordinator.buildSearchKey(from: "qxz"),
            invertedIndex: invertedIndex,
            totalCount: entries.count
        )

        XCTAssertTrue(candidates.isEmpty)
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

        let model = LiveSwitcherModel(
            snapshotService: RecordingRuntimeSnapshotService(
                appSwitcherApps: terminateScenarioApps()
            )
        )

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

    @MainActor
    func testShowInCommandTabFiltersCurrentAppFromSwitcherAppLayerAndSearchIndex() {
        let defaults = UserDefaults.standard
        let previousHiddenAppIDs = defaults.object(forKey: AppPreferenceKeys.hiddenAppIDs)
        let previousShowInCommandTab = defaults.object(forKey: AppPreferenceKeys.showInCommandTab)
        let previousSearchEnabled = defaults.object(forKey: AppPreferenceKeys.searchEnabled)
        let previousSearchDefaultScope = defaults.object(forKey: AppPreferenceKeys.searchDefaultScope)
        defer {
            restoreUserDefaultsValue(
                previousHiddenAppIDs,
                forKey: AppPreferenceKeys.hiddenAppIDs,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousShowInCommandTab,
                forKey: AppPreferenceKeys.showInCommandTab,
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

        let currentAppID = Bundle.main.bundleIdentifier ?? "pid:\(ProcessInfo.processInfo.processIdentifier)"
        defaults.removeObject(forKey: AppPreferenceKeys.hiddenAppIDs)
        defaults.set(false, forKey: AppPreferenceKeys.showInCommandTab)
        defaults.set(true, forKey: AppPreferenceKeys.searchEnabled)
        defaults.set(SwitcherSearchScope.app.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)

        let currentApp = AppSwitchCandidate(
            id: currentAppID,
            displayName: "FlowTab",
            groupID: "flowtab",
            lastActiveAt: 400,
            windows: [
                WindowCandidate(id: "flowtab-home", title: "FlowTab Home", isMinimized: false, lastActiveAt: 400)
            ]
        )
        let browserApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "browser",
            lastActiveAt: 300,
            windows: [
                WindowCandidate(id: "browser-main", title: "Browser Main", isMinimized: false, lastActiveAt: 300)
            ]
        )
        let model = LiveSwitcherModel(
            snapshotService: RecordingRuntimeSnapshotService(
                appSwitcherApps: [currentApp, browserApp]
            )
        )

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.session?.apps.map(\.id), ["com.example.browser"])

        XCTAssertTrue(model.enterSearchMode())
        XCTAssertTrue(model.searchCoordinator.replaceQueryWithoutRebuild("FlowTab", cursorPosition: 7))
        model.searchCoordinator.rebuildResults(resetSelection: true)
        model.publishSearchStateIfNeeded()
        XCTAssertTrue(model.searchViewState.results.isEmpty)
    }

    @MainActor
    func testLiveSwitcherModelSearchReadsCommittedRuntimeIndexInsteadOfSessionApps() {
        let defaults = UserDefaults.standard
        let previousSearchEnabled = defaults.object(forKey: AppPreferenceKeys.searchEnabled)
        let previousSearchDefaultScope = defaults.object(forKey: AppPreferenceKeys.searchDefaultScope)
        defer {
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

        defaults.set(true, forKey: AppPreferenceKeys.searchEnabled)
        defaults.set(SwitcherSearchScope.window.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)

        let sessionOnlyApp = AppSwitchCandidate(
            id: "com.example.session-only",
            displayName: "Session Only",
            groupID: "session",
            lastActiveAt: 100,
            windows: []
        )
        let committedSearchApp = AppSwitchCandidate(
            id: "com.example.committed",
            displayName: "Committed Browser",
            groupID: "committed",
            lastActiveAt: 90,
            windows: [
                WindowCandidate(
                    id: "committed-docs",
                    title: "Runtime Committed Docs",
                    isMinimized: false,
                    lastActiveAt: 90
                )
            ]
        )
        let model = LiveSwitcherModel(
            snapshotService: RecordingRuntimeSnapshotService(
                appSwitcherApps: [sessionOnlyApp],
                committedSearchApps: [committedSearchApp]
            )
        )

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.session?.apps.map(\.id), ["com.example.session-only"])
        XCTAssertTrue(model.enterSearchMode())
        XCTAssertTrue(
            model.searchCoordinator.replaceQueryWithoutRebuild(
                "docs",
                cursorPosition: 4
            )
        )
        model.searchCoordinator.rebuildResults(resetSelection: true)
        model.publishSearchStateIfNeeded()

        XCTAssertEqual(
            model.searchViewState.results.map(\.kind),
            [.window(appID: "com.example.committed", windowID: "committed-docs")]
        )
    }

    @MainActor
    func testLiveSwitcherModelSearchUsesStaleCommittedIndexAndRequestsFreshnessBarrier() {
        let defaults = UserDefaults.standard
        let previousSearchEnabled = defaults.object(forKey: AppPreferenceKeys.searchEnabled)
        let previousSearchDefaultScope = defaults.object(forKey: AppPreferenceKeys.searchDefaultScope)
        defer {
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

        defaults.set(true, forKey: AppPreferenceKeys.searchEnabled)
        defaults.set(SwitcherSearchScope.window.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)

        let sessionApp = AppSwitchCandidate(
            id: "com.example.session",
            displayName: "Session",
            groupID: "session",
            lastActiveAt: 100,
            windows: []
        )
        let committedSearchApp = AppSwitchCandidate(
            id: "com.example.committed",
            displayName: "Committed Browser",
            groupID: "committed",
            lastActiveAt: 90,
            windows: [
                WindowCandidate(
                    id: "committed-stale-docs",
                    title: "Runtime Stale Docs",
                    isMinimized: false,
                    lastActiveAt: 90
                )
            ]
        )
        let store = RuntimeReadModelStore()
        store.commitAppSwitcherProjection(
            apps: [committedSearchApp],
            contextsByID: [:],
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: committedSearchApp.id,
            pid: 42_300,
            pendingScope: "appWindows:\(committedSearchApp.id)"
        )
        let staleSearchProjection = store.readCommittedSearchIndexForSearch().projection
        let snapshotService = RecordingRuntimeSnapshotService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [sessionApp],
                contextsByID: [:],
                freshness: RuntimeProjectionFreshness(
                    generatedAt: 10,
                    sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                    dirtyAppIDs: [],
                    dirtyPIDs: [],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes: [],
                    isCompleteForScope: true
                )
            ),
            committedSearchIndexProjection: staleSearchProjection
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.enterSearchMode())
        XCTAssertEqual(model.lastSearchIndexReadDiagnostic?.readiness, .stale)
        XCTAssertEqual(
            snapshotService.searchIndexFreshnessBarrierRequestsRecorded(),
            [.searchFreshnessBarrier]
        )
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)

        XCTAssertTrue(
            model.searchCoordinator.replaceQueryWithoutRebuild(
                "docs",
                cursorPosition: 4
            )
        )
        model.searchCoordinator.rebuildResults(resetSelection: true)
        model.publishSearchStateIfNeeded()

        XCTAssertEqual(
            model.searchViewState.results.map(\.kind),
            [.window(appID: "com.example.committed", windowID: "committed-stale-docs")]
        )
    }

    @MainActor
    func testLiveSwitcherModelSearchDoesNotFallbackToSessionAppsWithoutCommittedIndex() {
        let defaults = UserDefaults.standard
        let previousSearchEnabled = defaults.object(forKey: AppPreferenceKeys.searchEnabled)
        defer {
            restoreUserDefaultsValue(
                previousSearchEnabled,
                forKey: AppPreferenceKeys.searchEnabled,
                userDefaults: defaults
            )
        }
        defaults.set(true, forKey: AppPreferenceKeys.searchEnabled)

        let searchableSessionApp = AppSwitchCandidate(
            id: "com.example.session-searchable",
            displayName: "Session Searchable",
            groupID: "session",
            lastActiveAt: 100,
            windows: [
                WindowCandidate(
                    id: "session-window",
                    title: "Session Window",
                    isMinimized: false,
                    lastActiveAt: 100
                )
            ]
        )
        let model = LiveSwitcherModel(
            snapshotService: RecordingRuntimeSnapshotService(
                appSwitcherProjection: RuntimeAppSwitcherProjection(
                    apps: [searchableSessionApp],
                    contextsByID: [:],
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: 10,
                        sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                        dirtyAppIDs: [],
                        dirtyPIDs: [],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: [],
                        isCompleteForScope: true
                    )
                )
            )
        )

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertFalse(model.enterSearchMode())
        XCTAssertFalse(model.isSearchActive)
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
        let queryCoordinator = SwitcherSearchCoordinator()
        queryCoordinator.rebuildIndex(with: apps)
        _ = queryCoordinator.activate(defaultScope: .window)
        let queryNanos = measureNanos {
            runBaselineQueries(queries, on: queryCoordinator, rounds: rounds)
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

        let queryCoordinator = SwitcherSearchCoordinator()
        queryCoordinator.rebuildIndex(with: apps)
        _ = queryCoordinator.activate(defaultScope: .window)
        let queryNanos = measureNanos {
            runBaselineQueries(queries, on: queryCoordinator, rounds: rounds)
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

    @MainActor
    func testLiveSwitcherModelSearchPressureReadsReadyCommittedIndexWithoutSampling() {
        let defaults = UserDefaults.standard
        let previousSearchEnabled = defaults.object(forKey: AppPreferenceKeys.searchEnabled)
        let previousSearchDefaultScope = defaults.object(forKey: AppPreferenceKeys.searchDefaultScope)
        defer {
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

        defaults.set(true, forKey: AppPreferenceKeys.searchEnabled)
        defaults.set(SwitcherSearchScope.window.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)

        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let windowCount = apps.reduce(0) { $0 + $1.windows.count }
        let snapshotService = RecordingRuntimeSnapshotService(appSwitcherApps: apps)
        let model = LiveSwitcherModel(snapshotService: snapshotService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))

        let enterStart = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(model.enterSearchMode())
        let enterMs = nanosToMilliseconds(DispatchTime.now().uptimeNanoseconds - enterStart)

        XCTAssertEqual(model.lastSearchIndexReadDiagnostic?.readiness, .ready)
        XCTAssertEqual(model.lastSearchIndexReadDiagnostic?.appCount, apps.count)
        XCTAssertEqual(model.lastSearchIndexReadDiagnostic?.windowCount, windowCount)
        XCTAssertEqual(model.lastSearchIndexReadDiagnostic?.requestedFreshnessBarrier, false)
        XCTAssertTrue(model.lastSearchIndexReadDiagnostic?.isCompleteForScope ?? false)
        XCTAssertEqual(snapshotService.searchIndexFreshnessBarrierRequestsRecorded(), [])
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)

        let queries = benchmarkQueries()
        let rounds = 3
        let queryStart = DispatchTime.now().uptimeNanoseconds
        runBaselineQueries(queries, on: model.searchCoordinator, rounds: rounds)
        let queryMs = nanosToMilliseconds(DispatchTime.now().uptimeNanoseconds - queryStart)
        let queryCount = queries.count * rounds
        let qps = Double(queryCount) / max(0.001, queryMs / 1000.0)

        print(
            String(
                format: "[CommittedSearchIndexPressure] dataset=%d apps / %d windows, rounds=%d, enter=%.2fms, query=%.2fms, queries=%d, throughput=%.2f qps, snapshotCalls=%d, lightweightCalls=%d, freshnessBarrierRequests=%d",
                apps.count,
                windowCount,
                rounds,
                enterMs,
                queryMs,
                queryCount,
                qps,
                snapshotService.snapshotRequestCount(),
                snapshotService.lightweightSnapshotRequestCount(),
                snapshotService.searchIndexFreshnessBarrierRequestsRecorded().count
            )
        )

        XCTAssertFalse(searchResultIDs(query: "weixin", on: model.searchCoordinator).isEmpty)
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.searchIndexFreshnessBarrierRequestsRecorded(), [])
    }

    func testSearchPressureWindowScopeSegmentedQueries() {
        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let queries = segmentedBenchmarkQueries()
        let rounds = 3

        let buildNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
        }

        let queryCoordinator = SwitcherSearchCoordinator()
        queryCoordinator.rebuildIndex(with: apps)
        _ = queryCoordinator.activate(defaultScope: .window)
        let queryNanos = measureNanos {
            runBaselineQueries(queries, on: queryCoordinator, rounds: rounds)
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

    func testSearchPressureWindowScopeQueryWorkloadMatrix() {
        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let windowCount = apps.reduce(0) { $0 + $1.windows.count }
        let workloads = searchPressureWorkloadMatrix(windowCount: windowCount)
        let rounds = 3

        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: apps)
        _ = coordinator.activate(defaultScope: .window)

        for workload in workloads {
            if let warmupQuery = workload.warmupQuery {
                _ = coordinator.replaceQueryWithoutRebuild(warmupQuery, cursorPosition: warmupQuery.count)
                coordinator.rebuildResults(resetSelection: true)
            }

            let queryNanos = measureNanos {
                runBaselineQueries(workload.queries, on: coordinator, rounds: rounds)
            }
            let queryMs = nanosToMilliseconds(queryNanos)
            let queryCount = workload.queries.count * rounds
            let qps = Double(queryCount) / max(0.001, queryMs / 1000.0)

            print(
                String(
                    format: "[SearchPressureWorkloadMatrix] workload=%@ dataset=%d apps / %d windows, rounds=%d, query=%.2fms, queries=%d, throughput=%.2f qps",
                    workload.name,
                    apps.count,
                    windowCount,
                    rounds,
                    queryMs,
                    queryCount,
                    qps
                )
            )

            for query in workload.expectedHits {
                XCTAssertFalse(
                    searchResultIDs(query: query, on: coordinator).isEmpty,
                    "Expected workload \(workload.name) query \(query) to return at least one result"
                )
            }
            for query in workload.expectedMisses {
                XCTAssertTrue(
                    searchResultIDs(query: query, on: coordinator).isEmpty,
                    "Expected workload \(workload.name) query \(query) to return no results"
                )
            }
            if let expectedFinalResultCount = workload.expectedFinalResultCount {
                XCTAssertEqual(
                    coordinator.state.results.count,
                    expectedFinalResultCount,
                    "Expected workload \(workload.name) final result count to match the full window dataset"
                )
            }
            _ = coordinator.replaceQueryWithoutRebuild("", cursorPosition: 0)
            coordinator.rebuildResults(resetSelection: true)
        }
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
        let runtimeService = RecordingRuntimeSnapshotService(appSwitcherApps: apps)
        let model = LiveSwitcherModel(snapshotService: runtimeService)
        model.frontmostApplicationOverride = { nil }

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
                format: "[OptionTabFastStartPressure] dataset=%d apps, iterations=%d, p50=%.2fms, p95=%.2fms, max=%.2fms, maintenanceRequests=%d",
                apps.count,
                iterations,
                summary.p50,
                summary.p95,
                summary.max,
                runtimeService.appSwitcherMaintenanceRequestsRecorded().count
            )
        )

        XCTAssertEqual(runtimeService.appSwitcherMaintenanceRequestsRecorded().count, iterations)
        XCTAssertLessThan(summary.p95, 100)
    }

    @MainActor
    func testOptionTabFastStartPressureIgnoresLargeFrontmostWindowSet() {
        let selectedWindowCount = 1_000
        let projectionSeed = makeOptionTabWindowScaleProjectionSeed(
            selectedWindowCount: selectedWindowCount,
            extraAppCount: 120,
            largeWindowAppIndex: 0,
            includeRuntimeContexts: false
        )
        let runtimeService = RecordingRuntimeSnapshotService(
            appSwitcherApps: appOnlyAppSwitcherApps(from: projectionSeed.apps)
        )
        let model = LiveSwitcherModel(snapshotService: runtimeService)
        model.frontmostApplicationOverride = { nil }

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
                format: "[OptionTabFrontmostWindowScalePressure] apps=%d, frontmostWindows=%d, iterations=%d, p50=%.2fms, p95=%.2fms, max=%.2fms, maintenanceRequests=%d",
                projectionSeed.apps.count,
                selectedWindowCount,
                iterations,
                summary.p50,
                summary.p95,
                summary.max,
                runtimeService.appSwitcherMaintenanceRequestsRecorded().count
            )
        )

        XCTAssertEqual(runtimeService.appSwitcherMaintenanceRequestsRecorded().count, iterations)
        XCTAssertLessThan(summary.p95, 100)
    }

    @MainActor
    func testControlTabFocusedProjectionFastStartPressureIgnoresFocusedSnapshotBridge() {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeSnapshotProvider.baseAppID(for: runningApp)
        let windowCount = 1_000
        let windows = (0..<windowCount).map { index in
            WindowCandidate(
                id: "focused-projection-window-\(index)",
                title: "Focused Projection Document \(index)",
                isMinimized: false,
                lastActiveAt: TimeInterval(windowCount - index)
            )
        }
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: runningApp.localizedName ?? "Focused Projection App",
            groupID: "focused-projection",
            lastActiveAt: TimeInterval(windowCount),
            windows: windows
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: Dictionary(
                uniqueKeysWithValues: windows.enumerated().map { index, window in
                    (
                        window.id,
                        RuntimeWindowContext(
                            id: window.id,
                            title: window.title,
                            isMinimized: window.isMinimized,
                            ownerPID: runningApp.processIdentifier,
                            cgWindowID: CGWindowID(20_000 + index)
                        )
                    )
                }
            )
        )
        let snapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: candidate.displayName,
                groupID: candidate.groupID,
                lastActiveAt: candidate.lastActiveAt,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: context
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    snapshot: snapshot,
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: 30,
                        sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                        dirtyAppIDs: [],
                        dirtyPIDs: [],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: [],
                        isCompleteForScope: true
                    )
                )
            ]
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.frontmostApplicationOverride = { runningApp }

        let iterations = 80
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0)
            XCTAssertEqual(model.session?.selectedApp.windows.count ?? -1, windowCount)
            model.cancelSelection()
        }

        let summary = latencySummary(samples: samples)
        print(
            String(
                format: "[ControlTabFocusedProjectionFastStartPressure] windows=%d, iterations=%d, p50=%.2fms, p95=%.2fms, max=%.2fms, snapshotCalls=%d",
                windowCount,
                iterations,
                summary.p50,
                summary.p95,
                summary.max,
                snapshotService.snapshotRequestCount()
            )
        )

        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertLessThan(summary.p95, 100)
    }

    @MainActor
    func testLiveSwitcherModelSnapshotInvalidationRecordTracksReasonAndScope() {
        let model = LiveSwitcherModel()

        model.invalidateRuntimeProjectionMaintenanceRequest(reason: .commitSelection)

        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.reason, .commitSelection)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.scope, .runtimeProjectionMaintenance)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.maintenanceGeneration, 1)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.selectedAppWindowGeneration, 0)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.clearedDeferredMaintenanceRequest, false)
        XCTAssertTrue(
            model.lastSnapshotInvalidationRecord?.logMessage.contains("reason=commitSelection") ?? false
        )

        model.invalidateSelectedAppWindowSnapshot(reason: .resetRuntimeState)

        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.reason, .resetRuntimeState)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.scope, .selectedAppWindowSnapshot)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.maintenanceGeneration, 1)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.selectedAppWindowGeneration, 1)
        XCTAssertEqual(model.lastSnapshotInvalidationRecord?.clearedDeferredMaintenanceRequest, false)
    }

    @MainActor
    func testLiveSwitcherModelMaintenanceDiagnosticTracksGenerationReasonWithoutApply() {
        let appID = "com.flowtab.tests.maintenance-diagnostic"
        let fastApp = AppSwitchCandidate(
            id: appID,
            displayName: "Maintenance Diagnostic",
            groupID: "current",
            lastActiveAt: 100,
            windows: []
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [fastApp],
                contextsByID: [:],
                freshness: RuntimeProjectionFreshness(
                    generatedAt: 10,
                    sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                    dirtyAppIDs: [],
                    dirtyPIDs: [],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes: [],
                    isCompleteForScope: true
                )
            )
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        let generation = model.runtimeProjectionMaintenanceGeneration

        let diagnostic = model.lastRuntimeProjectionMaintenanceDiagnostic
        XCTAssertEqual(diagnostic?.result, "maintenanceRequested")
        XCTAssertEqual(diagnostic?.generation, generation)
        XCTAssertEqual(diagnostic?.currentGeneration, generation)
        XCTAssertEqual(diagnostic?.reason, .startSession)
        XCTAssertEqual(diagnostic?.trigger, CycleDirection.forward.debugName)
        XCTAssertEqual(diagnostic?.applyGeneration, nil)
        XCTAssertTrue(diagnostic?.logMessage.contains("reason=startSession") ?? false)
        XCTAssertTrue(diagnostic?.logMessage.contains("applyGeneration=nil") ?? false)
        XCTAssertEqual(snapshotService.appSwitcherMaintenanceRequestsRecorded(), [.switcherSessionStarted])
    }

    @MainActor
    func testOptionTabWindowScalePressureKeepsSelectedAppApplyAndPreviewCaptureBounded() {
        let selectedWindowCount = 1_000
        let projectionSeed = makeOptionTabWindowScaleProjectionSeed(
            selectedWindowCount: selectedWindowCount,
            extraAppCount: 80,
            largeWindowAppIndex: 1,
            includeRuntimeContexts: true
        )
        let model = LiveSwitcherModel(
            snapshotService: RecordingRuntimeSnapshotService(
                appSwitcherApps: appOnlyAppSwitcherApps(from: projectionSeed.apps)
            )
        )
        model.frontmostApplicationOverride = { nil }
        model.runtimeProjectionMaintenanceEnabled = false
        var previewCaptureCalls = 0
        model.previewCaptureOverride = { _, _, _, _ in
            previewCaptureCalls += 1
            return nil
        }

        let iterations = 60
        var selectedAppApplySamples: [Double] = []
        var windowLayerEntrySamples: [Double] = []
        var visiblePreviewItemSamples: [Double] = []
        selectedAppApplySamples.reserveCapacity(iterations)
        windowLayerEntrySamples.reserveCapacity(iterations)
        visiblePreviewItemSamples.reserveCapacity(iterations)
        var visibleWindowCount = 0

        for _ in 0..<iterations {
            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertEqual(model.session?.selectedApp.windows.count ?? -1, 0)
            guard
                let selectedAppID = model.session?.selectedApp.id,
                let selectedApp = projectionSeed.apps.first(where: { $0.id == selectedAppID }),
                let selectedContext = projectionSeed.contextsByID[selectedAppID]
            else {
                XCTFail("missing selected app context")
                return
            }
            let selectedSnapshot = RuntimeHomeAppSnapshot(
                summary: RuntimeHomeAppSummary(
                    appID: selectedApp.id,
                    displayName: selectedApp.displayName,
                    groupID: selectedApp.groupID,
                    lastActiveAt: selectedApp.lastActiveAt,
                    windowCount: selectedApp.windows.count,
                    pid: selectedContext.runningApp.processIdentifier
                ),
                candidate: selectedApp,
                context: selectedContext
            )

            let applyStart = DispatchTime.now().uptimeNanoseconds
            let applyStartMs = LiveSwitcherModel.monotonicMilliseconds()
            model.completeSelectedAppWindowSnapshot(
                selectedSnapshot,
                appID: selectedAppID,
                generation: model.selectedAppWindowSnapshotGeneration,
                startMs: applyStartMs,
                snapshotReadMs: applyStartMs
            )
            selectedAppApplySamples.append(
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

        let selectedAppApply = latencySummary(samples: selectedAppApplySamples)
        let windowLayerEntry = latencySummary(samples: windowLayerEntrySamples)
        let previewItems = latencySummary(samples: visiblePreviewItemSamples)
        print(
            String(
                format: "[OptionTabWindowScalePressure] apps=%d, selectedWindows=%d, visibleWindows=%d, iterations=%d, selectedAppApplyP95=%.2fms, enterP95=%.2fms, previewItemsP95=%.2fms, previewCaptureCalls=%d",
                projectionSeed.apps.count,
                selectedWindowCount,
                visibleWindowCount,
                iterations,
                selectedAppApply.p95,
                windowLayerEntry.p95,
                previewItems.p95,
                previewCaptureCalls
            )
        )

        XCTAssertLessThan(selectedAppApply.p95, 50)
        XCTAssertLessThan(windowLayerEntry.p95, 50)
        XCTAssertLessThan(previewItems.p95, 50)
        XCTAssertLessThanOrEqual(previewCaptureCalls, iterations * max(visibleWindowCount, 1))
    }

    private func makeOptionTabWindowScaleProjectionSeed(
        selectedWindowCount: Int,
        extraAppCount: Int,
        largeWindowAppIndex: Int,
        includeRuntimeContexts: Bool
    ) -> (apps: [AppSwitchCandidate], contextsByID: [String: RuntimeAppContext]) {
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
            return (apps, [:])
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
        return (apps, [largeWindowApp.id: selectedContext])
    }

    private func appOnlyAppSwitcherApps(from apps: [AppSwitchCandidate]) -> [AppSwitchCandidate] {
        apps.map { app in
            AppSwitchCandidate(
                id: app.id,
                displayName: app.displayName,
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt,
                windows: []
            )
        }
    }

}
