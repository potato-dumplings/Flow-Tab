import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

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

    func testWorkspaceProviderTracksAccessoryRegularAccessoryTransitions() {
        let app = PermissionBoundaryRunningApplication(
            pid: 40_951,
            bundleIdentifier: "com.example.runtime-mode",
            localizedName: "Runtime Mode",
            activationPolicy: .accessory
        )
        let provider = RuntimeWorkspaceAppDirectoryProvider(
            runningApplicationsProvider: { [app] },
            currentPIDProvider: { 40_999 },
            showInCommandTabProvider: { false },
            rankProvider: { _ in [:] }
        )

        let accessoryEvidence = provider.appDirectorySnapshotEvidenceForPresentation()
        XCTAssertTrue(accessoryEvidence.membership.directoryAppIDs.isEmpty)

        app.setActivationPolicy(.regular)
        let regularEvidence = provider.appDirectorySnapshotEvidenceForPresentation()
        XCTAssertEqual(regularEvidence.membership.directoryAppIDs, [app.bundleIdentifier!])
        XCTAssertEqual(regularEvidence.membership.switcherEligibleAppIDs, [app.bundleIdentifier!])

        app.setActivationPolicy(.accessory)
        let finalAccessoryEvidence = provider.appDirectorySnapshotEvidenceForPresentation()
        XCTAssertTrue(finalAccessoryEvidence.membership.directoryAppIDs.isEmpty)
        XCTAssertEqual(
            [accessoryEvidence.revision, regularEvidence.revision, finalAccessoryEvidence.revision],
            [1, 2, 3]
        )
        XCTAssertEqual(accessoryEvidence.sourceID, finalAccessoryEvidence.sourceID)
    }

    func testWorkspaceProviderKeepsCurrentFlowTabInDirectoryAndAppliesSwitcherPreference() {
        let app = PermissionBoundaryRunningApplication(
            pid: 40_961,
            bundleIdentifier: "com.example.flowtab",
            localizedName: "FlowTab",
            activationPolicy: .accessory
        )
        var showInCommandTab = false
        let provider = RuntimeWorkspaceAppDirectoryProvider(
            runningApplicationsProvider: { [app] },
            currentPIDProvider: { app.processIdentifier },
            showInCommandTabProvider: { showInCommandTab },
            rankProvider: { _ in [:] }
        )

        let hiddenEvidence = provider.appDirectorySnapshotEvidenceForPresentation()
        XCTAssertEqual(hiddenEvidence.membership.directoryAppIDs, [app.bundleIdentifier!])
        XCTAssertTrue(hiddenEvidence.membership.switcherEligibleAppIDs.isEmpty)

        showInCommandTab = true
        let visibleEvidence = provider.appDirectorySnapshotEvidenceForPresentation()
        XCTAssertEqual(visibleEvidence.membership.directoryAppIDs, [app.bundleIdentifier!])
        XCTAssertEqual(visibleEvidence.membership.switcherEligibleAppIDs, [app.bundleIdentifier!])
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

    func testProjectionCoverageGuardAllowsRemovalAfterMembershipBecomesAccessory() throws {
        let stableApp = permissionBoundaryCandidate(appID: "com.example.coverage-stable")
        let transitionedApp = permissionBoundaryCandidate(appID: "com.example.coverage-accessory")
        let stableEntry = permissionBoundaryEntry(app: stableApp, pid: 42_151)
        let transitionedEntry = permissionBoundaryEntry(app: transitionedApp, pid: 42_152)
        let store = RuntimeReadModelStore()
        store.seedAppSwitcherProjectionForTesting(
            apps: [stableApp, transitionedApp],
            contextsByID: [:],
            appDirectoryEntries: [stableEntry, transitionedEntry],
            generatedAt: 10
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AccessoryCoverageRemoval",
            repairProvider: RuntimeProjectionRepairProvider(
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: PermissionBoundaryMainTableProjectionBuilder(
                apps: [stableApp]
            ),
            appDirectoryProvider: PermissionBoundaryAppDirectoryProvider(
                entries: [stableEntry]
            ),
            readModelStore: store,
            axWindowRepairAvailability: { false }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()

        let projection = try XCTUnwrap(service.readAppSwitcherProjection())
        XCTAssertEqual(projection.apps.map(\.id), [stableApp.id])
        XCTAssertGreaterThan(projection.freshness.generatedAt, 10)
    }

    func testProjectionCoverageGuardProtectsAppThatRemainsRegular() throws {
        let stableApp = permissionBoundaryCandidate(appID: "com.example.coverage-stable")
        let missingRegularApp = permissionBoundaryCandidate(appID: "com.example.coverage-regular")
        let stableEntry = permissionBoundaryEntry(app: stableApp, pid: 42_161)
        let missingRegularEntry = permissionBoundaryEntry(app: missingRegularApp, pid: 42_162)
        let store = RuntimeReadModelStore()
        store.seedAppSwitcherProjectionForTesting(
            apps: [stableApp, missingRegularApp],
            contextsByID: [:],
            appDirectoryEntries: [stableEntry, missingRegularEntry],
            generatedAt: 10
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.RegularCoverageProtection",
            repairProvider: RuntimeProjectionRepairProvider(
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: PermissionBoundaryMainTableProjectionBuilder(
                apps: [stableApp]
            ),
            appDirectoryProvider: PermissionBoundaryAppDirectoryProvider(
                entries: [stableEntry, missingRegularEntry]
            ),
            readModelStore: store,
            axWindowRepairAvailability: { false }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()

        let projection = try XCTUnwrap(service.readAppSwitcherProjection())
        XCTAssertEqual(projection.apps.map(\.id), [stableApp.id, missingRegularApp.id])
        XCTAssertEqual(projection.freshness.generatedAt, 10)
    }

    func testAuthoritativeAppDirectoryEvidenceRemovesStaleCommittedAccessoryApp() throws {
        let stableApp = AppSwitchCandidate(
            id: "com.example.stable-editor",
            displayName: "Stable Editor",
            groupID: "com.example.stable-editor",
            lastActiveAt: 20,
            windows: []
        )
        let transitionedApp = AppSwitchCandidate(
            id: "com.example.transitioned-menu-bar",
            displayName: "Transitioned Menu Bar",
            groupID: "com.example.transitioned-menu-bar",
            lastActiveAt: 10,
            windows: []
        )
        let stableEntry = RuntimeAppDirectoryEntry(
            pid: 42_201,
            appID: stableApp.id,
            bundleIdentifier: stableApp.id,
            localizedName: stableApp.displayName,
            launchDate: nil,
            activationRank: 0
        )
        let transitionedEntry = RuntimeAppDirectoryEntry(
            pid: 42_202,
            appID: transitionedApp.id,
            bundleIdentifier: transitionedApp.id,
            localizedName: transitionedApp.displayName,
            launchDate: nil,
            activationRank: 1
        )
        let store = RuntimeReadModelStore()
        store.seedAppSwitcherProjectionForTesting(
            apps: [stableApp, transitionedApp],
            contextsByID: [:],
            appDirectoryEntries: [stableEntry, transitionedEntry],
            generatedAt: 10
        )
        XCTAssertNotNil(
            store.commitSearchFreshnessBarrierFromMainTablePayload(
                makeRuntimeSearchIndexPayloadForTesting(apps: [stableApp, transitionedApp]),
                deferredRequestCount: 0,
                hasPendingRequests: false,
                generatedAt: 10
            )
        )

        store.commitAppDirectoryProviderEvidence([stableEntry], generatedAt: 11)

        XCTAssertEqual(
            try XCTUnwrap(store.readAppSwitcherProjection()).apps.map(\.id),
            [stableApp.id]
        )
        XCTAssertEqual(
            try XCTUnwrap(store.readHomeSummaryProjection()).summaries.map(\.appID),
            [stableApp.id]
        )
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().projection?.appEntries.map(\.appID),
            [stableApp.id]
        )
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().projection?.windowEntries.map(\.appID),
            []
        )
    }

    func testOlderMaintenanceEvidenceCannotOverrideNewerPresentationMembership() throws {
        let sourceID = UUID()
        let stableEntry = RuntimeAppDirectoryEntry(
            pid: 42_301,
            appID: "com.example.stable",
            bundleIdentifier: "com.example.stable",
            localizedName: "Stable",
            launchDate: nil
        )
        let staleEntry = RuntimeAppDirectoryEntry(
            pid: 42_302,
            appID: "com.example.stale-accessory",
            bundleIdentifier: "com.example.stale-accessory",
            localizedName: "Stale Accessory",
            launchDate: nil
        )
        let store = RuntimeReadModelStore()

        XCTAssertTrue(
            store.commitAppDirectoryPresentationEvidence(
                makePermissionBoundaryEvidence(
                    sourceID: sourceID,
                    revision: 2,
                    entries: [stableEntry]
                )
            )
        )
        XCTAssertFalse(
            store.commitAppDirectoryProviderEvidence(
                makePermissionBoundaryEvidence(
                    sourceID: sourceID,
                    revision: 1,
                    entries: [stableEntry, staleEntry]
                )
            )
        )

        XCTAssertEqual(
            try XCTUnwrap(store.readAppDirectoryProjection()).entries.map(\.appID),
            [stableEntry.appID]
        )
    }

    func testRegularSiblingPIDKeepsAppButInvalidAccessoryContextIsCleared() throws {
        let appID = "com.example.multi-instance"
        let regularPID: pid_t = 42_401
        let accessoryPID: pid_t = 42_402
        let staleAccessoryApp = PermissionBoundaryRunningApplication(
            pid: accessoryPID,
            bundleIdentifier: appID,
            localizedName: "Multi Instance",
            activationPolicy: .accessory
        )
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Multi Instance",
            groupID: appID,
            lastActiveAt: 1,
            windows: [
                WindowCandidate(
                    id: "stale-window",
                    title: "Stale Window",
                    isMinimized: false,
                    lastActiveAt: 1
                )
            ]
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: staleAccessoryApp,
            ownerPID: accessoryPID,
            windowsByID: [:]
        )
        let regularEntry = RuntimeAppDirectoryEntry(
            pid: regularPID,
            appID: appID,
            bundleIdentifier: appID,
            localizedName: candidate.displayName,
            launchDate: nil
        )
        let store = RuntimeReadModelStore()
        store.seedAppSwitcherProjectionForTesting(
            apps: [candidate],
            contextsByID: [appID: context],
            appDirectoryEntries: [regularEntry],
            generatedAt: 10
        )
        XCTAssertNotNil(
            store.commitSearchFreshnessBarrierFromMainTablePayload(
                makeRuntimeSearchIndexPayloadForTesting(apps: [candidate]),
                deferredRequestCount: 0,
                hasPendingRequests: false,
                generatedAt: 10
            )
        )

        _ = store.commitAppDirectoryPresentationEvidence(
            RuntimeAppDirectorySnapshotEvidence(
                sourceID: UUID(),
                revision: 1,
                capturedAt: 11,
                processIdentities: [
                    RuntimeAppProcessIdentity(
                        appID: appID,
                        pid: regularPID,
                        isDirectoryMember: true,
                        isSwitcherEligible: true
                    ),
                    RuntimeAppProcessIdentity(
                        appID: appID,
                        pid: accessoryPID,
                        isDirectoryMember: false,
                        isSwitcherEligible: false
                    )
                ],
                entries: [regularEntry]
            )
        )

        let projection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(projection.apps.map(\.id), [appID])
        XCTAssertTrue(try XCTUnwrap(projection.apps.first).windows.isEmpty)
        XCTAssertNil(projection.contextsByID[appID])
        let searchProjection = try XCTUnwrap(
            store.readCommittedSearchIndexForSearch().projection
        )
        XCTAssertEqual(searchProjection.appEntries.map(\.appID), [appID])
        XCTAssertTrue(searchProjection.windowEntries.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(store.readHomeSummaryProjection()).summary(for: appID)?.pid,
            regularPID
        )
    }

    func testAccessoryAppCanReenterAfterLaterRegularEvidence() throws {
        let appID = "com.example.dynamic-mode"
        let entry = RuntimeAppDirectoryEntry(
            pid: 42_501,
            appID: appID,
            bundleIdentifier: appID,
            localizedName: "Dynamic Mode",
            launchDate: nil
        )
        let sourceID = UUID()
        let store = RuntimeReadModelStore()

        _ = store.commitAppDirectoryPresentationEvidence(
            makePermissionBoundaryEvidence(sourceID: sourceID, revision: 1, entries: [])
        )
        XCTAssertTrue(try XCTUnwrap(store.readAppSwitcherProjection()).apps.isEmpty)

        _ = store.commitAppDirectoryPresentationEvidence(
            makePermissionBoundaryEvidence(sourceID: sourceID, revision: 2, entries: [entry])
        )
        XCTAssertEqual(
            try XCTUnwrap(store.readAppSwitcherProjection()).apps.map(\.id),
            [appID]
        )
    }

    @MainActor
    func testActivationStopsWhenTargetLosesSwitcherEligibility() {
        let appID = "com.example.transitioned-before-activation"
        let runningApp = NSRunningApplication.current
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: [:]
        )
        let activator = RuntimeActivator()
        var activationRequestCount = 0
        activator.applicationIsEligibleForSwitcherActivationOverride = { _ in false }
        activator.requestActivationOverride = { _, _ in
            activationRequestCount += 1
        }

        activator.activate(
            target: .app(appID: appID, fallback: nil),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(activationRequestCount, 0)
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

private func permissionBoundaryCandidate(appID: String) -> AppSwitchCandidate {
    AppSwitchCandidate(
        id: appID,
        displayName: appID,
        groupID: appID,
        lastActiveAt: 1,
        windows: []
    )
}

private func permissionBoundaryEntry(
    app: AppSwitchCandidate,
    pid: pid_t
) -> RuntimeAppDirectoryEntry {
    RuntimeAppDirectoryEntry(
        pid: pid,
        appID: app.id,
        bundleIdentifier: app.id,
        localizedName: app.displayName,
        launchDate: nil
    )
}

private func makePermissionBoundaryEvidence(
    sourceID: UUID,
    revision: UInt64,
    entries: [RuntimeAppDirectoryEntry]
) -> RuntimeAppDirectorySnapshotEvidence {
    RuntimeAppDirectorySnapshotEvidence(
        sourceID: sourceID,
        revision: revision,
        capturedAt: TimeInterval(revision),
        processIdentities: entries.map { entry in
            RuntimeAppProcessIdentity(
                appID: entry.appID,
                pid: entry.pid,
                isDirectoryMember: true,
                isSwitcherEligible: entry.isEligibleForAppSwitcherProjection
            )
        },
        entries: entries
    )
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

private final class PermissionBoundaryMainTableProjectionBuilder:
    RuntimeMainTableProjectionBuilding
{
    private let apps: [AppSwitchCandidate]

    init(apps: [AppSwitchCandidate]) {
        self.apps = apps
    }

    func currentAppWindowPayloadFromMainTables(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeCurrentAppWindowPayload? {
        nil
    }

    func appSwitcherProjectionPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeAppSwitcherProjectionPayload? {
        RuntimeAppSwitcherProjectionPayload(
            apps: apps,
            contextsByID: [:],
            hasCompleteWindowCoverage: false
        )
    }

    func searchIndexPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexPayload? {
        makeRuntimeSearchIndexPayloadForTesting(apps: apps)
    }
}

private final class PermissionBoundaryRunningApplication: NSRunningApplication {
    private let fakePID: pid_t
    private let fakeBundleIdentifier: String
    private let fakeLocalizedName: String
    private var fakeActivationPolicy: NSApplication.ActivationPolicy
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

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) {
        fakeActivationPolicy = activationPolicy
    }
}
