import Combine
import XCTest
@testable import FlowTab

extension FlowTabTests {
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
                description: "hidden app inventory reload completed"
            )
            var cancellables: Set<AnyCancellable> = []
            model.$isLoading
                .drop(while: { !$0 })
                .filter { !$0 }
                .prefix(1)
                .sink { _ in
                    reloadCompleted.fulfill()
                }
                .store(in: &cancellables)

            model.reload()
            await fulfillment(of: [reloadCompleted], timeout: 5)

            XCTAssertFalse(model.isLoading)
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
                description: "searchable app inventory reload completed"
            )
            var cancellables: Set<AnyCancellable> = []
            model.$isLoading
                .drop(while: { !$0 })
                .filter { !$0 }
                .prefix(1)
                .sink { _ in
                    reloadCompleted.fulfill()
                }
                .store(in: &cancellables)

            model.reload()
            await fulfillment(of: [reloadCompleted], timeout: 5)

            XCTAssertEqual(model.visibleApps.map(\.id), ["com.xxx.test"])
            XCTAssertEqual(model.selectedApp?.id, "com.xxx.test")
        }
    }
}
