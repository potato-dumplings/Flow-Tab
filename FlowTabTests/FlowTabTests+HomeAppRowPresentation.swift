import Combine
import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

private enum HomeAppRowPresentationWatchdogPolicy {
    static let inventoryReload: TimeInterval = 5
}

private final class HomeAppRowMutableInventory:
    AppInventoryProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var records: [InstalledAppRecord]

    init(records: [InstalledAppRecord]) {
        self.records = records
    }

    func installedApps() -> [InstalledAppRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    func replaceRecords(_ records: [InstalledAppRecord]) {
        lock.lock()
        self.records = records
        lock.unlock()
    }
}

extension FlowTabTests {
    func testHomeAppRowsMergeRunningHiddenInventoryAndKeepStatsClosed() {
        let visibleID = "com.example.visible"
        let preferenceHiddenID = "com.example.preference-hidden"
        let accessoryID = "com.example.accessory"
        let closedID = "com.example.closed"
        let systemManagedID = "com.example.system-managed"
        let presentation = HomeAppVisibilityPresentation(
            hiddenAppIDs: [
                preferenceHiddenID,
                accessoryID,
                closedID,
                systemManagedID
            ]
        )
        let runtimeSummaries = [
            homeSummary(appID: preferenceHiddenID, windowCount: 1),
            homeSummary(appID: visibleID, windowCount: 2)
        ]
        let installedApps = [
            homeInstalledApp(appID: visibleID, isRunning: true, policy: .regular),
            homeInstalledApp(appID: accessoryID, isRunning: true, policy: .accessory),
            homeInstalledApp(appID: closedID, isRunning: false, policy: nil),
            homeInstalledApp(
                appID: systemManagedID,
                isRunning: true,
                policy: .accessory,
                capability: .systemManaged(reason: .staticBundleDeclaration)
            )
        ]

        let rows = presentation.appRows(
            runtimeSummaries: runtimeSummaries,
            installedApps: installedApps
        )

        XCTAssertEqual(rows.map(\.appID), [visibleID, preferenceHiddenID, accessoryID])
        XCTAssertEqual(rows.map(\.windowCount), [2, 1, 0])
        XCTAssertEqual(rows.map(\.isHidden), [false, true, true])
        XCTAssertEqual(rows.map(\.hasRuntimeProjection), [true, true, false])
        XCTAssertEqual(
            HomeOverviewStats.make(
                appRows: rows,
                loadingWindowCountAppIDs: []
            ),
            HomeOverviewStats(
                totalApps: 3,
                visibleApps: 1,
                hiddenApps: 2,
                totalWindows: .ready(3)
            )
        )
    }

    func testHomeAppRowsNormalizeDuplicatesAndPromoteSupplementToRuntimeProjection() {
        let appID = "com.example.promoted"
        let presentation = HomeAppVisibilityPresentation(hiddenAppIDs: [appID])
        let inventory = [
            homeInstalledApp(
                appID: "  \(appID)  ",
                isRunning: true,
                policy: .accessory
            )
        ]

        let supplementalRows = presentation.appRows(
            runtimeSummaries: [],
            installedApps: inventory
        )
        XCTAssertEqual(supplementalRows.map(\.appID), [appID])
        XCTAssertEqual(supplementalRows.map(\.windowCount), [0])
        XCTAssertEqual(supplementalRows.map(\.hasRuntimeProjection), [false])

        let runtimeRows = presentation.appRows(
            runtimeSummaries: [homeSummary(appID: appID, windowCount: 4)],
            installedApps: inventory
        )
        XCTAssertEqual(runtimeRows.map(\.appID), [appID])
        XCTAssertEqual(runtimeRows.map(\.windowCount), [4])
        XCTAssertEqual(runtimeRows.map(\.hasRuntimeProjection), [true])
    }

    @MainActor
    func testSharedVisibilityModelSeparatesSettingsInventoryFromRunningHomeRows() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let visibleID = "com.example.shared-visible"
        let accessoryID = "com.example.shared-accessory"
        let closedID = "com.example.shared-closed"
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        AppVisibilityPreferencesStore.saveHiddenAppIDs(
            [closedID],
            userDefaults: userDefaults
        )
        let inventory = HomeAppRowMutableInventory(records: [
            homeInstalledApp(appID: visibleID, isRunning: true, policy: .regular),
            homeInstalledApp(appID: accessoryID, isRunning: true, policy: .accessory),
            homeInstalledApp(appID: closedID, isRunning: false, policy: nil)
        ])
        let model = AppVisibilityManagerModel(
            inventoryService: inventory,
            userDefaults: userDefaults
        )

        await reloadHomeVisibilityModelAndWait(model)
        XCTAssertEqual(model.hiddenCount, 2)
        var rows = HomeAppVisibilityPresentation(
            hiddenAppIDs: model.effectiveHiddenAppIDs
        ).appRows(
            runtimeSummaries: [homeSummary(appID: visibleID, windowCount: 1)],
            installedApps: model.apps
        )
        XCTAssertEqual(rows.map(\.appID), [visibleID, accessoryID])
        XCTAssertEqual(rows.map(\.isHidden), [false, true])

        model.setHidden(true, for: visibleID)
        rows = HomeAppVisibilityPresentation(
            hiddenAppIDs: model.effectiveHiddenAppIDs
        ).appRows(
            runtimeSummaries: [homeSummary(appID: visibleID, windowCount: 1)],
            installedApps: model.apps
        )
        XCTAssertEqual(model.hiddenCount, 3)
        XCTAssertEqual(rows.map(\.isHidden), [true, true])

        inventory.replaceRecords([
            homeInstalledApp(appID: visibleID, isRunning: true, policy: .regular),
            homeInstalledApp(appID: accessoryID, isRunning: true, policy: .regular),
            homeInstalledApp(appID: closedID, isRunning: false, policy: nil)
        ])
        await reloadHomeVisibilityModelAndWait(model)
        rows = HomeAppVisibilityPresentation(
            hiddenAppIDs: model.effectiveHiddenAppIDs
        ).appRows(
            runtimeSummaries: [
                homeSummary(appID: visibleID, windowCount: 1),
                homeSummary(appID: accessoryID, windowCount: 2)
            ],
            installedApps: model.apps
        )
        XCTAssertEqual(rows.map(\.appID), [accessoryID, visibleID])
        XCTAssertEqual(rows.map(\.hasRuntimeProjection), [true, true])
        XCTAssertEqual(model.hiddenCount, 2)

        inventory.replaceRecords([
            homeInstalledApp(appID: visibleID, isRunning: true, policy: .regular),
            homeInstalledApp(appID: accessoryID, isRunning: false, policy: nil),
            homeInstalledApp(appID: closedID, isRunning: false, policy: nil)
        ])
        await reloadHomeVisibilityModelAndWait(model)
        rows = HomeAppVisibilityPresentation(
            hiddenAppIDs: model.effectiveHiddenAppIDs
        ).appRows(
            runtimeSummaries: [homeSummary(appID: visibleID, windowCount: 1)],
            installedApps: model.apps
        )
        XCTAssertEqual(rows.map(\.appID), [visibleID])
        XCTAssertEqual(model.hiddenCount, 2)
    }

    func testMockRuntimeInventoryIsDeterministicAndIncludesCurrentAppOnRequest() {
        let baseArguments = [
            "FlowTab",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-mock-runtime-variant",
            FlowTabUITestApplicationMembershipFixture.variant
        ]
        let service = AppInventoryService(searchDirectories: [])

        withLaunchArgumentsForTesting(baseArguments) {
            let records = service.installedApps()
            XCTAssertEqual(
                Set(records.map(\.id)),
                [
                    FlowTabUITestApplicationMembershipFixture.stableAppID,
                    FlowTabUITestApplicationMembershipFixture.finalAccessoryAppID
                ]
            )
            XCTAssertEqual(
                records.first {
                    $0.id
                        == FlowTabUITestApplicationMembershipFixture
                            .finalAccessoryAppID
                }?.runtimeActivationPolicy,
                .accessory
            )
        }

        withLaunchArgumentsForTesting(
            baseArguments
                + [FlowTabTestLaunchOptions.includeCurrentAppInMockInventoryArgument]
        ) {
            let records = service.installedApps()
            let currentAppID = AppVisibilityPreferencesStore.currentAppID()
            XCTAssertEqual(Set(records.map(\.id)).count, 3)
            XCTAssertEqual(
                records.first { $0.id == currentAppID }?.isCurrentProcess,
                true
            )
        }
    }

    private func homeSummary(
        appID: String,
        windowCount: Int
    ) -> RuntimeHomeAppSummary {
        RuntimeHomeAppSummary(
            appID: appID,
            displayName: appID,
            groupID: "tests",
            lastActiveAt: 1,
            windowCount: windowCount,
            pid: 101,
            bundleIdentifier: appID
        )
    }

    private func homeInstalledApp(
        appID: String,
        isRunning: Bool,
        policy: ApplicationRuntimeActivationPolicy?,
        capability: AppVisibilityCapability = .configurable
    ) -> InstalledAppRecord {
        InstalledAppRecord(
            id: appID,
            displayName: appID,
            bundleIdentifier: appID,
            path: "/Applications/\(appID).app",
            isRunning: isRunning,
            runtimeActivationPolicy: policy,
            visibilityCapability: capability
        )
    }

    @MainActor
    private func reloadHomeVisibilityModelAndWait(
        _ model: AppVisibilityManagerModel
    ) async {
        let completed = expectation(description: "shared visibility inventory ready")
        var sawLoading = false
        let observation = model.$inventoryReadiness.sink { readiness in
            if readiness == .loading {
                sawLoading = true
            } else if readiness == .ready, sawLoading {
                completed.fulfill()
            }
        }
        model.reload()
        await fulfillment(
            of: [completed],
            timeout: HomeAppRowPresentationWatchdogPolicy.inventoryReload
        )
        observation.cancel()
    }
}
