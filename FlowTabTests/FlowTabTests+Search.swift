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

}
