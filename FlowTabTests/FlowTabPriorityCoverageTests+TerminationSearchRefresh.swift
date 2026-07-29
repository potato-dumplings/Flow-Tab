import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedPreservesSearchStateDuringRefresh() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let initialApps = self.searchScenarioApps()
            let runtimeProjectionService = RecordingRuntimeProjectionService(
                appSwitcherApps: initialApps
            )
            let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
            let refreshedApps = initialApps.filter { $0.id != "com.example.code" }
            let expectedQuery = "bro"
            let expectedResultTitles = ["Browser"]
            defer {
                model.onSearchStateChanged = nil
                model.onSessionLayoutChanged = nil
            }

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())

            let initialSearchPublished = expectation(
                description: "initial search result published before termination refresh"
            )
            initialSearchPublished.assertForOverFulfill = true
            var didObserveInitialSearch = false
            model.onSearchStateChanged = {
                guard
                    !didObserveInitialSearch,
                    model.isSearchActive,
                    model.searchViewState.scope == .app,
                    model.searchViewState.query == expectedQuery,
                    model.searchViewState.results.map(\.primaryText) == expectedResultTitles
                else {
                    return
                }
                didObserveInitialSearch = true
                initialSearchPublished.fulfill()
            }

            model.synchronizeSearchInput(
                query: expectedQuery,
                cursorPosition: expectedQuery.count
            )

            await fulfillment(of: [initialSearchPublished], timeout: 1.0)
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchViewState.scope, .app)
            XCTAssertEqual(model.searchViewState.query, expectedQuery)
            XCTAssertEqual(model.searchViewState.results.map(\.primaryText), expectedResultTitles)

            let layoutRefreshed = expectation(
                description: "layout refresh published after app termination"
            )
            layoutRefreshed.assertForOverFulfill = true
            var didObserveLayoutRefresh = false
            model.onSessionLayoutChanged = {
                guard !didObserveLayoutRefresh else { return }
                didObserveLayoutRefresh = true
                layoutRefreshed.fulfill()
            }

            let preservedSearchPublished = expectation(
                description: "preserved search result published after projection refresh"
            )
            preservedSearchPublished.assertForOverFulfill = true
            var didObservePreservedSearch = false
            model.onSearchStateChanged = {
                guard
                    !didObservePreservedSearch,
                    model.appCount == refreshedApps.count,
                    model.isSearchActive,
                    model.searchViewState.scope == .app,
                    model.searchViewState.query == expectedQuery,
                    model.searchViewState.results.map(\.primaryText) == expectedResultTitles
                else {
                    return
                }
                didObservePreservedSearch = true
                preservedSearchPublished.fulfill()
            }

            runtimeProjectionService.installAppSwitcherProjection(apps: refreshedApps)
            XCTAssertTrue(
                model.handleApplicationTerminated(
                    appID: "com.example.code",
                    pid: 42_300
                )
            )

            await fulfillment(
                of: [layoutRefreshed, preservedSearchPublished],
                timeout: 1.0
            )
            XCTAssertEqual(model.appCount, refreshedApps.count)
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchViewState.scope, .app)
            XCTAssertEqual(model.searchViewState.query, expectedQuery)
            XCTAssertEqual(model.searchViewState.results.map(\.primaryText), expectedResultTitles)
        }
    }
}
