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
                model.cancelPendingSearchComputation()
                model.onSearchStateChanged = nil
                model.onSessionLayoutChanged = nil
            }

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())

            let initialSearchPublished = expectation(
                description:
                    "unmetCondition=initialSearchComputationPublishedExactQueryResults"
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

            await fulfillment(
                of: [initialSearchPublished],
                timeout:
                    FlowTabPriorityCoverageWatchdogPolicy
                        .searchComputationPublication
            )
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchViewState.scope, .app)
            XCTAssertEqual(model.searchViewState.query, expectedQuery)
            XCTAssertEqual(model.searchViewState.results.map(\.primaryText), expectedResultTitles)

            var layoutPublicationCount = 0
            model.onSessionLayoutChanged = {
                layoutPublicationCount += 1
            }

            runtimeProjectionService.installAppSwitcherProjection(apps: refreshedApps)
            XCTAssertEqual(layoutPublicationCount, 0)
            XCTAssertTrue(
                model.handleApplicationTerminated(
                    appID: "com.example.code",
                    pid: 42_300
                )
            )
            XCTAssertEqual(layoutPublicationCount, 1)

            XCTAssertEqual(layoutPublicationCount, 1)
            XCTAssertEqual(model.appCount, refreshedApps.count)
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchViewState.scope, .app)
            XCTAssertEqual(model.searchViewState.query, expectedQuery)
            XCTAssertEqual(model.searchViewState.results.map(\.primaryText), expectedResultTitles)
        }
    }
}
