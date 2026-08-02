import Combine
import XCTest
@testable import FlowTab

private enum AppVisibilityReloadWatchdogPolicy {
    static let eventDelivery: TimeInterval = 5
}

extension FlowTabTests {
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
            model.filter = .hidden
            let reloadCompleted = expectation(
                description:
                    "unmetCondition=hiddenAppInventoryLoadingTransitionCompleted expectedVisibleAppIDs=\(missingAppID)"
            )
            reloadCompleted.assertForOverFulfill = true
            var observedLoadingStates: [Bool] = []
            var completionCount = 0
            var lastVisibleAppIDs: [String] = []
            var lastSelectedAppID: String?
            var lastHiddenCount = 0
            let loadingObservation = model.$isLoading
                .sink { isLoading in
                    XCTAssertTrue(Thread.isMainThread)
                    observedLoadingStates.append(isLoading)
                    guard Array(
                        observedLoadingStates.suffix(2)
                    ) == [true, false]
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
            defer { loadingObservation.cancel() }

            XCTAssertEqual(observedLoadingStates, [false])
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
            XCTAssertEqual(
                observedLoadingStates,
                [false, true, false],
                "unmetCondition=singleHiddenAppInventoryLoadingTransition "
                    + "finalLoadingStates=\(observedLoadingStates) "
                    + "finalVisibleAppIDs=\(lastVisibleAppIDs) "
                    + "finalSelectedAppID=\(lastSelectedAppID ?? "nil") "
                    + "finalHiddenCount=\(lastHiddenCount)"
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
            model.query = "ceshi"
            let reloadCompleted = expectation(
                description:
                    "unmetCondition=searchableAppInventoryLoadingTransitionCompleted expectedVisibleAppIDs=com.xxx.test"
            )
            reloadCompleted.assertForOverFulfill = true
            var observedLoadingStates: [Bool] = []
            var completionCount = 0
            var lastVisibleAppIDs: [String] = []
            var lastSelectedAppID: String?
            let loadingObservation = model.$isLoading
                .sink { isLoading in
                    XCTAssertTrue(Thread.isMainThread)
                    observedLoadingStates.append(isLoading)
                    guard Array(
                        observedLoadingStates.suffix(2)
                    ) == [true, false]
                    else {
                        return
                    }
                    completionCount += 1
                    lastVisibleAppIDs =
                        model.visibleApps.map(\.id)
                    lastSelectedAppID = model.selectedApp?.id
                    reloadCompleted.fulfill()
                }
            defer { loadingObservation.cancel() }

            XCTAssertEqual(observedLoadingStates, [false])
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
            XCTAssertEqual(
                observedLoadingStates,
                [false, true, false],
                "unmetCondition=singleSearchableAppInventoryLoadingTransition "
                    + "finalLoadingStates=\(observedLoadingStates) "
                    + "finalVisibleAppIDs=\(lastVisibleAppIDs) "
                    + "finalSelectedAppID=\(lastSelectedAppID ?? "nil")"
            )
            XCTAssertEqual(completionCount, 1)
            XCTAssertEqual(lastVisibleAppIDs, ["com.xxx.test"])
            XCTAssertEqual(lastSelectedAppID, "com.xxx.test")
            XCTAssertEqual(model.visibleApps.map(\.id), ["com.xxx.test"])
            XCTAssertEqual(model.selectedApp?.id, "com.xxx.test")
        }
    }
}
