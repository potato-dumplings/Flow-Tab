import Combine
import XCTest
@testable import FlowTab

private enum AppVisibilityReloadWatchdogPolicy {
    static let eventDelivery: TimeInterval = 5
}

extension FlowTabTests {
    func testAppVisibilityInventoryReadinessAccessibilityIdentifiersAreStable() {
        XCTAssertEqual(
            AppVisibilityInventoryReadiness.idle.accessibilityIdentifier,
            "flowtab.settings.app-visibility.inventory.idle"
        )
        XCTAssertEqual(
            AppVisibilityInventoryReadiness.loading.accessibilityIdentifier,
            "flowtab.settings.app-visibility.inventory.loading"
        )
        XCTAssertEqual(
            AppVisibilityInventoryReadiness.ready.accessibilityIdentifier,
            "flowtab.settings.app-visibility.inventory.ready"
        )
    }

    @MainActor
    func testAppVisibilityQueryProjectionGenerationTracksCommittedChanges() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        let model = AppVisibilityManagerModel(userDefaults: userDefaults)
        var observedQueries: [String] = []
        var observedGenerations: [UInt64] = []
        let queryObservation = model.$query.sink {
            observedQueries.append($0)
        }
        let generationObservation = model.$queryProjectionGeneration.sink {
            observedGenerations.append($0)
        }
        defer {
            queryObservation.cancel()
            generationObservation.cancel()
        }

        XCTAssertEqual(
            AppVisibilityQueryProjectionAccessibility.identifierPrefix,
            "flowtab.settings.app-visibility.list.query-generation."
        )
        XCTAssertEqual(
            AppVisibilityQueryProjectionAccessibility.identifier(generation: 0),
            "flowtab.settings.app-visibility.list.query-generation.0"
        )

        model.updateQuery("Mail")
        model.updateQuery("Mail")
        model.updateQuery("ceshi")

        XCTAssertEqual(model.query, "ceshi")
        XCTAssertEqual(model.queryProjectionGeneration, 2)
        XCTAssertEqual(observedQueries, ["", "Mail", "ceshi"])
        XCTAssertEqual(observedGenerations, [0, 1, 2])
    }

    @MainActor
    func testAppVisibilityFilterProjectionGenerationTracksCommittedChanges() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        let model = AppVisibilityManagerModel(userDefaults: userDefaults)
        var observedFilters: [AppVisibilityManagerModel.Filter] = []
        var observedGenerations: [UInt64] = []
        let filterObservation = model.$filter.sink {
            observedFilters.append($0)
        }
        let generationObservation = model.$filterProjectionGeneration.sink {
            observedGenerations.append($0)
        }
        defer {
            filterObservation.cancel()
            generationObservation.cancel()
        }

        XCTAssertEqual(
            AppVisibilityFilterProjectionAccessibility.identifierPrefix,
            "flowtab.settings.app-visibility.filter-projection."
        )
        XCTAssertEqual(
            AppVisibilityFilterProjectionAccessibility.identifier(
                filterRawValue: "all",
                generation: 0
            ),
            "flowtab.settings.app-visibility.filter-projection.all.generation.0"
        )

        model.updateFilter(.hidden)
        model.updateFilter(.hidden)
        model.updateFilter(.running)

        XCTAssertEqual(model.filter, .running)
        XCTAssertEqual(model.filterProjectionGeneration, 2)
        XCTAssertEqual(observedFilters, [.all, .hidden, .running])
        XCTAssertEqual(observedGenerations, [0, 1, 2])
    }

    func testAppVisibilityReloadWatchdogPolicyPreservesEventDeliveryBound() {
        let eventDelivery =
            AppVisibilityReloadWatchdogPolicy.eventDelivery

        XCTAssertEqual(eventDelivery, 5)
        XCTAssertTrue(eventDelivery.isFinite)
        XCTAssertGreaterThan(eventDelivery, 0)
    }

    @MainActor
    func testAppVisibilityManagerShowsStoredHiddenAppIDsMissingFromInventory() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let missingAppID = "com.flowtab.hidden.missing"
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        AppVisibilityPreferencesStore.saveHiddenAppIDs(
            [missingAppID],
            userDefaults: userDefaults
        )

        await withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let model = AppVisibilityManagerModel(userDefaults: userDefaults)
            model.updateFilter(.hidden)
            let reloadCompleted = expectation(
                description:
                    "unmetCondition=hiddenAppInventoryLoadingTransitionCompleted expectedVisibleAppIDs=\(missingAppID)"
            )
            reloadCompleted.assertForOverFulfill = true
            var observedLoadingStates: [Bool] = []
            var observedReadinessStates:
                [AppVisibilityInventoryReadiness] = []
            var completionCount = 0
            var lastVisibleAppIDs: [String] = []
            var lastSelectedAppID: String?
            var lastHiddenCount = 0
            let loadingObservation = model.$isLoading
                .sink { isLoading in
                    XCTAssertTrue(Thread.isMainThread)
                    observedLoadingStates.append(isLoading)
                }
            let readinessObservation = model.$inventoryReadiness
                .sink { readiness in
                    XCTAssertTrue(Thread.isMainThread)
                    observedReadinessStates.append(readiness)
                    guard Array(observedReadinessStates.suffix(2))
                        == [.loading, .ready]
                    else {
                        return
                    }
                    completionCount += 1
                    lastVisibleAppIDs =
                        model.visibleApps.map(\.id)
                    lastSelectedAppID = model.selectedApp?.id
                    lastHiddenCount = model.hiddenCount
                    reloadCompleted.fulfill()
                }
            defer {
                loadingObservation.cancel()
                readinessObservation.cancel()
            }

            XCTAssertEqual(observedLoadingStates, [false])
            XCTAssertEqual(observedReadinessStates, [.idle])
            XCTAssertEqual(completionCount, 0)
            XCTAssertTrue(lastVisibleAppIDs.isEmpty)
            XCTAssertNil(lastSelectedAppID)
            XCTAssertEqual(lastHiddenCount, 0)

            model.reload()
            await fulfillment(
                of: [reloadCompleted],
                timeout:
                    AppVisibilityReloadWatchdogPolicy
                        .eventDelivery
            )

            XCTAssertFalse(model.isLoading)
            XCTAssertEqual(model.inventoryReadiness, .ready)
            XCTAssertEqual(
                observedLoadingStates,
                [false, true, false],
                "unmetCondition=singleHiddenAppInventoryLoadingTransition "
                    + "finalLoadingStates=\(observedLoadingStates) "
                    + "finalVisibleAppIDs=\(lastVisibleAppIDs) "
                    + "finalSelectedAppID=\(lastSelectedAppID ?? "nil") "
                    + "finalHiddenCount=\(lastHiddenCount)"
            )
            XCTAssertEqual(
                observedReadinessStates,
                [.idle, .loading, .ready]
            )
            XCTAssertEqual(completionCount, 1)
            XCTAssertEqual(lastHiddenCount, 1)
            XCTAssertEqual(lastVisibleAppIDs, [missingAppID])
            XCTAssertEqual(lastSelectedAppID, missingAppID)
            XCTAssertEqual(model.hiddenCount, 1)
            XCTAssertEqual(model.visibleApps.map(\.id), [missingAppID])
            XCTAssertEqual(model.selectedApp?.id, missingAppID)
        }
    }

    @MainActor
    func testAppVisibilityManagerSearchUsesSharedPinyinMatching() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        await withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let model = AppVisibilityManagerModel(userDefaults: userDefaults)
            model.updateQuery("ceshi")
            let reloadCompleted = expectation(
                description:
                    "unmetCondition=searchableAppInventoryLoadingTransitionCompleted expectedVisibleAppIDs=com.xxx.test"
            )
            reloadCompleted.assertForOverFulfill = true
            var observedLoadingStates: [Bool] = []
            var observedReadinessStates:
                [AppVisibilityInventoryReadiness] = []
            var completionCount = 0
            var lastVisibleAppIDs: [String] = []
            var lastSelectedAppID: String?
            let loadingObservation = model.$isLoading
                .sink { isLoading in
                    XCTAssertTrue(Thread.isMainThread)
                    observedLoadingStates.append(isLoading)
                }
            let readinessObservation = model.$inventoryReadiness
                .sink { readiness in
                    XCTAssertTrue(Thread.isMainThread)
                    observedReadinessStates.append(readiness)
                    guard Array(observedReadinessStates.suffix(2))
                        == [.loading, .ready]
                    else {
                        return
                    }
                    completionCount += 1
                    lastVisibleAppIDs =
                        model.visibleApps.map(\.id)
                    lastSelectedAppID = model.selectedApp?.id
                    reloadCompleted.fulfill()
                }
            defer {
                loadingObservation.cancel()
                readinessObservation.cancel()
            }

            XCTAssertEqual(observedLoadingStates, [false])
            XCTAssertEqual(observedReadinessStates, [.idle])
            XCTAssertEqual(completionCount, 0)
            XCTAssertTrue(lastVisibleAppIDs.isEmpty)
            XCTAssertNil(lastSelectedAppID)

            model.reload()
            await fulfillment(
                of: [reloadCompleted],
                timeout:
                    AppVisibilityReloadWatchdogPolicy
                        .eventDelivery
            )

            XCTAssertFalse(model.isLoading)
            XCTAssertEqual(model.inventoryReadiness, .ready)
            XCTAssertEqual(
                observedLoadingStates,
                [false, true, false],
                "unmetCondition=singleSearchableAppInventoryLoadingTransition "
                    + "finalLoadingStates=\(observedLoadingStates) "
                    + "finalVisibleAppIDs=\(lastVisibleAppIDs) "
                    + "finalSelectedAppID=\(lastSelectedAppID ?? "nil")"
            )
            XCTAssertEqual(
                observedReadinessStates,
                [.idle, .loading, .ready]
            )
            XCTAssertEqual(completionCount, 1)
            XCTAssertEqual(lastVisibleAppIDs, ["com.xxx.test"])
            XCTAssertEqual(lastSelectedAppID, "com.xxx.test")
            XCTAssertEqual(model.visibleApps.map(\.id), ["com.xxx.test"])
            XCTAssertEqual(model.selectedApp?.id, "com.xxx.test")
        }
    }
}
