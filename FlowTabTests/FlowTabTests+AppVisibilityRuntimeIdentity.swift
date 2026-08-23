import Combine
import Dispatch
import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

private enum AppVisibilityRuntimeIdentityWatchdogPolicy {
    static let eventDelivery: TimeInterval = 5
}

private final class MutableAppVisibilityInventory:
    AppInventoryProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var records: [InstalledAppRecord]
    private(set) var readCount = 0

    init(records: [InstalledAppRecord]) {
        self.records = records
    }

    func installedApps() -> [InstalledAppRecord] {
        lock.lock()
        defer { lock.unlock() }
        readCount += 1
        return records
    }

    func replaceRecords(_ records: [InstalledAppRecord]) {
        lock.lock()
        self.records = records
        lock.unlock()
    }

    func currentReadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return readCount
    }
}

private final class SequencedAppVisibilityInventory:
    AppInventoryProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let firstScanStarted: @Sendable () -> Void
    private let firstScanRelease: DispatchSemaphore
    private let firstRecords: [InstalledAppRecord]
    private let latestRecords: [InstalledAppRecord]
    private var readCount = 0

    init(
        firstRecords: [InstalledAppRecord],
        latestRecords: [InstalledAppRecord],
        firstScanStarted: @escaping @Sendable () -> Void,
        firstScanRelease: DispatchSemaphore
    ) {
        self.firstRecords = firstRecords
        self.latestRecords = latestRecords
        self.firstScanStarted = firstScanStarted
        self.firstScanRelease = firstScanRelease
    }

    func installedApps() -> [InstalledAppRecord] {
        lock.lock()
        readCount += 1
        let currentRead = readCount
        lock.unlock()

        if currentRead == 1 {
            firstScanStarted()
            firstScanRelease.wait()
            return firstRecords
        }
        return latestRecords
    }

    func currentReadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return readCount
    }
}

extension FlowTabTests {
    @MainActor
    func testDynamicAppPreferenceSurvivesClosedAccessoryAndRegularModes() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let appID = "com.example.dynamic-app"
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        AppVisibilityPreferencesStore.saveHiddenAppIDs(
            [appID],
            userDefaults: userDefaults
        )
        let inventory = MutableAppVisibilityInventory(
            records: [dynamicAppRecord(appID: appID, runtimePolicy: nil)]
        )
        let model = AppVisibilityManagerModel(
            inventoryService: inventory,
            userDefaults: userDefaults
        )

        await reloadAndWait(model)
        XCTAssertEqual(model.preferenceHiddenAppIDs, [appID])
        XCTAssertEqual(model.effectiveHiddenAppIDs, [appID])
        XCTAssertEqual(
            model.presentation(for: model.apps[0]),
            AppVisibilityPresentation(
                state: .hidden(reason: .userPreference),
                controlMode: .standard
            )
        )

        inventory.replaceRecords([
            dynamicAppRecord(appID: appID, runtimePolicy: .accessory)
        ])
        await reloadAndWait(model)
        XCTAssertEqual(model.preferenceHiddenAppIDs, [appID])
        XCTAssertEqual(model.effectiveHiddenAppIDs, [appID])
        XCTAssertEqual(model.hiddenCount, 1)
        XCTAssertEqual(
            model.presentation(for: model.apps[0]),
            AppVisibilityPresentation(
                state: .hidden(reason: .runtimeMode),
                controlMode: .regularModeOnly
            )
        )

        model.setHidden(false, for: appID)
        XCTAssertTrue(model.preferenceHiddenAppIDs.isEmpty)
        XCTAssertEqual(model.effectiveHiddenAppIDs, [appID])
        XCTAssertFalse(model.isPreferenceHidden(model.apps[0]))

        model.setHidden(true, for: appID)
        XCTAssertEqual(model.preferenceHiddenAppIDs, [appID])
        XCTAssertEqual(
            userDefaults.stringArray(forKey: AppPreferenceKeys.hiddenAppIDs),
            [appID]
        )

        inventory.replaceRecords([
            dynamicAppRecord(appID: appID, runtimePolicy: .regular)
        ])
        await reloadAndWait(model)
        XCTAssertEqual(model.preferenceHiddenAppIDs, [appID])
        XCTAssertEqual(model.effectiveHiddenAppIDs, [appID])
        XCTAssertEqual(
            model.presentation(for: model.apps[0]),
            AppVisibilityPresentation(
                state: .hidden(reason: .userPreference),
                controlMode: .standard
            )
        )
    }

    @MainActor
    func testPreferenceRefreshReprojectsWithoutReadingInventory() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let appID = "com.example.preference-refresh"
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        let inventory = MutableAppVisibilityInventory(
            records: [dynamicAppRecord(appID: appID, runtimePolicy: .regular)]
        )
        let model = AppVisibilityManagerModel(
            inventoryService: inventory,
            userDefaults: userDefaults
        )
        await reloadAndWait(model)
        XCTAssertEqual(inventory.currentReadCount(), 1)
        XCTAssertTrue(model.effectiveHiddenAppIDs.isEmpty)

        AppVisibilityPreferencesStore.setAppHidden(
            true,
            appID: appID,
            userDefaults: userDefaults
        )
        model.refreshStoredPreferences()

        XCTAssertEqual(inventory.currentReadCount(), 1)
        XCTAssertEqual(model.preferenceHiddenAppIDs, [appID])
        XCTAssertEqual(model.effectiveHiddenAppIDs, [appID])
    }

    @MainActor
    func testNewerReloadGenerationDiscardsOlderInventoryResult() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        let firstScanStarted = expectation(description: "first inventory scan started")
        let firstScanRelease = DispatchSemaphore(value: 0)
        defer { firstScanRelease.signal() }
        let inventory = SequencedAppVisibilityInventory(
            firstRecords: [
                dynamicAppRecord(
                    appID: "com.example.stale",
                    runtimePolicy: .accessory
                )
            ],
            latestRecords: [
                dynamicAppRecord(
                    appID: "com.example.latest",
                    runtimePolicy: .regular
                )
            ],
            firstScanStarted: { firstScanStarted.fulfill() },
            firstScanRelease: firstScanRelease
        )
        let model = AppVisibilityManagerModel(
            inventoryService: inventory,
            userDefaults: userDefaults
        )

        model.reload()
        await fulfillment(
            of: [firstScanStarted],
            timeout: AppVisibilityRuntimeIdentityWatchdogPolicy.eventDelivery
        )
        let latestReloadCompleted = expectation(
            description: "latest inventory generation committed"
        )
        var sawLoading = false
        let readinessObservation = model.$inventoryReadiness.sink { readiness in
            if readiness == .loading {
                sawLoading = true
            } else if readiness == .ready, sawLoading {
                latestReloadCompleted.fulfill()
            }
        }
        defer { readinessObservation.cancel() }

        model.reload()
        firstScanRelease.signal()
        await fulfillment(
            of: [latestReloadCompleted],
            timeout: AppVisibilityRuntimeIdentityWatchdogPolicy.eventDelivery
        )

        XCTAssertEqual(inventory.currentReadCount(), 2)
        XCTAssertEqual(model.apps.map(\.id), ["com.example.latest"])
        XCTAssertEqual(model.inventoryReadiness, .ready)
    }

    private func dynamicAppRecord(
        appID: String,
        runtimePolicy: ApplicationRuntimeActivationPolicy?
    ) -> InstalledAppRecord {
        InstalledAppRecord(
            id: appID,
            displayName: appID,
            bundleIdentifier: appID,
            path: "/Applications/\(appID).app",
            isRunning: runtimePolicy != nil,
            runtimeActivationPolicy: runtimePolicy
        )
    }

    @MainActor
    private func reloadAndWait(_ model: AppVisibilityManagerModel) async {
        let reloadCompleted = expectation(description: "visibility inventory ready")
        var sawLoading = false
        let readinessObservation = model.$inventoryReadiness.sink { readiness in
            if readiness == .loading {
                sawLoading = true
            } else if readiness == .ready, sawLoading {
                reloadCompleted.fulfill()
            }
        }
        model.reload()
        await fulfillment(
            of: [reloadCompleted],
            timeout: AppVisibilityRuntimeIdentityWatchdogPolicy.eventDelivery
        )
        readinessObservation.cancel()
    }
}
