import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeAppDirectoryDoesNotReadmitHiddenAccessoryProcess() {
        let regularApp = PermissionBoundaryRunningApplication(
            pid: 40_801,
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor"
        )
        let hiddenAccessoryProcess = PermissionBoundaryRunningApplication(
            pid: 40_802,
            bundleIdentifier: "com.example.editor.helper",
            localizedName: "Editor Helper",
            activationPolicy: .accessory
        )

        let facts = RuntimeAppDirectoryFactSource.maintenanceFacts(
            from: [regularApp, hiddenAccessoryProcess],
            currentPID: 40_899,
            includeCurrentProcessInAppLayer: false,
            rankProvider: { _ in [:] }
        )

        XCTAssertEqual(facts.entries.map(\.appID), ["com.example.editor"])
        XCTAssertEqual(
            facts.windowRepairApplications.map(\.processIdentifier),
            [regularApp.processIdentifier]
        )
    }

    func testRuntimeDirectoryRejectsAccessoryAppActivationEntry() {
        let accessoryApp = PermissionBoundaryRunningApplication(
            pid: 40_901,
            bundleIdentifier: "com.example.menu-bar-helper",
            localizedName: "Menu Bar Helper",
            activationPolicy: .accessory
        )
        XCTAssertNil(
            RuntimeAppDirectoryFactSource.runningApplicationEntry(
                for: accessoryApp,
                currentPID: 40_999
            )
        )
    }

    func testFocusedRepairDirectoryEvidenceDoesNotProjectAccessoryApp() throws {
        let accessoryApp = PermissionBoundaryRunningApplication(
            pid: 40_902,
            bundleIdentifier: "com.example.focused-menu-bar-helper",
            localizedName: "Focused Menu Bar Helper",
            activationPolicy: .accessory
        )
        let entries = RuntimeAppDirectoryFactSource.entries(
            from: [accessoryApp],
            currentPID: 40_999
        )
        XCTAssertTrue(entries.isEmpty)
    }

    func testRuntimeAppDirectorySeparatesMembershipFromWindowRepairEligibility() {
        let regularApp = PermissionBoundaryRunningApplication(
            pid: 41_001,
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor"
        )
        let currentAccessoryApp = PermissionBoundaryRunningApplication(
            pid: 41_002,
            bundleIdentifier: "com.example.flowtab",
            localizedName: "FlowTab",
            activationPolicy: .accessory
        )
        let unrelatedAccessoryApp = PermissionBoundaryRunningApplication(
            pid: 41_004,
            bundleIdentifier: "com.example.agent",
            localizedName: "Agent",
            activationPolicy: .accessory
        )
        let terminatedApp = PermissionBoundaryRunningApplication(
            pid: 41_005,
            bundleIdentifier: "com.example.terminated",
            localizedName: "Terminated",
            isTerminated: true
        )

        let facts = RuntimeAppDirectoryFactSource.maintenanceFacts(
            from: [
                regularApp,
                currentAccessoryApp,
                unrelatedAccessoryApp,
                terminatedApp
            ],
            currentPID: currentAccessoryApp.processIdentifier,
            includeCurrentProcessInAppLayer: false,
            rankProvider: { apps in
                Dictionary(
                    uniqueKeysWithValues: apps.enumerated().map {
                        ($0.element.processIdentifier, $0.offset)
                    }
                )
            }
        )

        XCTAssertEqual(
            facts.entries.map(\.appID),
            ["com.example.editor", "com.example.flowtab"]
        )
        XCTAssertEqual(
            facts.windowRepairApplications.map(\.processIdentifier),
            [regularApp.processIdentifier]
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: facts.entries.map {
                ($0.appID, $0.isEligibleForAppSwitcherProjection)
            }),
            [
                "com.example.editor": true,
                "com.example.flowtab": false
            ]
        )
    }

    func testRuntimeHomeProjectionKeepsDirectoryEntryExcludedFromAppSwitcher() throws {
        let editorEntry = RuntimeAppDirectoryEntry(
            pid: 42_001,
            appID: "com.example.editor",
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            launchDate: nil,
            activationRank: 0
        )
        let flowTabEntry = RuntimeAppDirectoryEntry(
            pid: 42_002,
            appID: "com.example.flowtab",
            bundleIdentifier: "com.example.flowtab",
            localizedName: "FlowTab",
            launchDate: nil,
            activationRank: 1,
            isEligibleForAppSwitcherProjection: false
        )
        let entries = [editorEntry, flowTabEntry]
        let store = RuntimeReadModelStore()
        store.commitAppDirectoryProviderEvidence(entries, generatedAt: 10)

        XCTAssertEqual(
            try XCTUnwrap(store.readAppSwitcherProjection()).apps.map(\.id),
            ["com.example.editor"]
        )
        XCTAssertEqual(
            try XCTUnwrap(store.readHomeSummaryProjection()).summaries.map(\.appID),
            ["com.example.editor", "com.example.flowtab"]
        )

        let builder = RuntimeMainTableProjectionBuilder(
            windowRecordStore: RuntimeWindowRecordStore()
        )
        let payload = try XCTUnwrap(
            builder.appSwitcherProjectionPayloadFromMainTables(
                appDirectoryEntries: entries,
                generatedAt: 11
            )
        )
        XCTAssertEqual(payload.apps.map(\.id), ["com.example.editor"])
        XCTAssertEqual(
            payload.homeSummaries.map(\.appID),
            ["com.example.editor", "com.example.flowtab"]
        )
        XCTAssertEqual(payload.homeSummaries.last?.windowCount, 0)
        XCTAssertEqual(
            try XCTUnwrap(
                builder.searchIndexPayloadFromMainTables(
                    appDirectoryEntries: entries,
                    generatedAt: 11
                )
            ).appEntries.map(\.appID),
            ["com.example.editor"]
        )
    }

    func testRuntimeMaintenancePublishesHomeDirectoryWithoutAXWindowRepair() throws {
        let editorEntry = RuntimeAppDirectoryEntry(
            pid: 42_101,
            appID: "com.example.editor",
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            launchDate: nil,
            activationRank: 0
        )
        let flowTabEntry = RuntimeAppDirectoryEntry(
            pid: 42_102,
            appID: "com.example.flowtab",
            bundleIdentifier: "com.example.flowtab",
            localizedName: "FlowTab",
            launchDate: nil,
            activationRank: 1,
            isEligibleForAppSwitcherProjection: false
        )
        let readModelStore = RuntimeReadModelStore()
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppDirectoryPermissionBoundary",
            repairProvider: RuntimeProjectionRepairProvider(
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: RuntimeWindowRecordStore()
            ),
            appDirectoryProvider: PermissionBoundaryAppDirectoryProvider(
                entries: [editorEntry, flowTabEntry]
            ),
            readModelStore: readModelStore,
            axWindowRepairAvailability: { false }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .homeProjectionMissing)
        service.waitForMaintenanceQueueForTesting()

        XCTAssertEqual(
            try XCTUnwrap(service.readHomeSummaryProjection()).summaries.map(\.appID),
            ["com.example.editor", "com.example.flowtab"]
        )
        XCTAssertEqual(
            try XCTUnwrap(service.readAppSwitcherProjection()).apps.map(\.id),
            ["com.example.editor"]
        )
    }

    @MainActor
    func testRuntimeHomeWindowObservationExcludesCurrentProcess() {
        let currentSummary = RuntimeHomeAppSummary(
            appID: "com.example.flowtab",
            displayName: "FlowTab",
            groupID: "com.example.flowtab",
            lastActiveAt: 1,
            windowCount: 0,
            pid: 43_001
        )
        let editorSummary = RuntimeHomeAppSummary(
            appID: "com.example.editor",
            displayName: "Editor",
            groupID: "com.example.editor",
            lastActiveAt: 0,
            windowCount: 1,
            pid: 43_002
        )

        XCTAssertEqual(
            RuntimeAXWindowChangeMonitor.expectedAppIDsByPID(
                from: [currentSummary, editorSummary],
                currentPID: currentSummary.pid
            ),
            [editorSummary.pid: editorSummary.appID]
        )
    }
}

private final class PermissionBoundaryAppDirectoryProvider: RuntimeAppDirectoryProviding {
    let entries: [RuntimeAppDirectoryEntry]

    init(entries: [RuntimeAppDirectoryEntry]) {
        self.entries = entries
    }

    func appDirectoryEntriesForRuntimeMaintenance() -> [RuntimeAppDirectoryEntry] {
        entries
    }
}

private final class PermissionBoundaryRunningApplication: NSRunningApplication {
    private let fakePID: pid_t
    private let fakeBundleIdentifier: String
    private let fakeLocalizedName: String
    private let fakeActivationPolicy: NSApplication.ActivationPolicy
    private let fakeIsTerminated: Bool

    init(
        pid: pid_t,
        bundleIdentifier: String,
        localizedName: String,
        activationPolicy: NSApplication.ActivationPolicy = .regular,
        isTerminated: Bool = false
    ) {
        fakePID = pid
        fakeBundleIdentifier = bundleIdentifier
        fakeLocalizedName = localizedName
        fakeActivationPolicy = activationPolicy
        fakeIsTerminated = isTerminated
        super.init()
    }

    override var processIdentifier: pid_t { fakePID }
    override var activationPolicy: NSApplication.ActivationPolicy { fakeActivationPolicy }
    override var isTerminated: Bool { fakeIsTerminated }
    override var bundleIdentifier: String? { fakeBundleIdentifier }
    override var localizedName: String? { fakeLocalizedName }
    override var launchDate: Date? { Date(timeIntervalSince1970: TimeInterval(fakePID)) }
}
