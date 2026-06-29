import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @discardableResult
    private func commitMainTableSearchFreshnessBarrierForTesting(
        _ store: RuntimeReadModelStore,
        generatedAt: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> RuntimeSearchIndexProjection? {
        let committed = store.commitSearchFreshnessBarrierFromProjectionCache(
            deferredRequestCount: 0,
            hasPendingRequests: false,
            generatedAt: generatedAt
        )
        XCTAssertNotNil(committed, file: file, line: line)
        return committed
    }

    func testRuntimeMainTableProjectionBuilderBuildsAppSwitcherPayloadFromMainTables() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let cgWindowID = CGWindowID(240_801)
        let axWindowID = "ax:\(pid):main-table-full"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let builder: RuntimeMainTableProjectionBuilding = RuntimeMainTableProjectionBuilder(
            windowRecordStore: windowRecordStore
        )
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)

        let payload = try XCTUnwrap(
            builder.appSwitcherProjectionPayloadFromMainTables(
                appDirectoryEntries: [appDirectoryEntry],
                generatedAt: 80
            )
        )

        let app = try XCTUnwrap(payload.apps.first)
        XCTAssertEqual(payload.apps.map(\.id), [appID])
        XCTAssertEqual(app.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(app.windows.map(\.title), ["Main Table Projection"])
        let projectedWindowID = try XCTUnwrap(app.windows.first?.id)
        XCTAssertEqual(
            payload.contextsByID[appID]?.windowsByID[projectedWindowID]?.cgWindowID,
            cgWindowID
        )
        XCTAssertEqual(
            payload.contextsByID[appID]?.windowsByID[projectedWindowID]?.spaceIDs,
            [5]
        )
    }

    func testRuntimeMainTableProjectionBuilderUsesAppDirectoryActivationRank() throws {
        let frontPID: pid_t = 260_901
        let backgroundPID: pid_t = 260_902
        let alphaPID: pid_t = 260_903
        let frontCGWindowID = CGWindowID(240_901)
        let backgroundCGWindowID = CGWindowID(240_902)
        let alphaCGWindowID = CGWindowID(240_903)
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                frontPID: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        frontCGWindowID: makeMainTableProjectionWindowRecord(
                            pid: frontPID,
                            cgWindowID: frontCGWindowID,
                            axWindowID: "ax:\(frontPID):front-rank"
                        )
                    ],
                    currentAXToCG: ["ax:\(frontPID):front-rank": frontCGWindowID],
                    validCGWindowIDs: [frontCGWindowID],
                    lastAXWindowIDs: ["ax:\(frontPID):front-rank"],
                    hasObservedAXWindowHandle: true
                ),
                backgroundPID: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        backgroundCGWindowID: makeMainTableProjectionWindowRecord(
                            pid: backgroundPID,
                            cgWindowID: backgroundCGWindowID,
                            axWindowID: "ax:\(backgroundPID):background-rank"
                        )
                    ],
                    currentAXToCG: ["ax:\(backgroundPID):background-rank": backgroundCGWindowID],
                    validCGWindowIDs: [backgroundCGWindowID],
                    lastAXWindowIDs: ["ax:\(backgroundPID):background-rank"],
                    hasObservedAXWindowHandle: true
                ),
                alphaPID: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        alphaCGWindowID: makeMainTableProjectionWindowRecord(
                            pid: alphaPID,
                            cgWindowID: alphaCGWindowID,
                            axWindowID: "ax:\(alphaPID):alpha-rank"
                        )
                    ],
                    currentAXToCG: ["ax:\(alphaPID):alpha-rank": alphaCGWindowID],
                    validCGWindowIDs: [alphaCGWindowID],
                    lastAXWindowIDs: ["ax:\(alphaPID):alpha-rank"],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let builder = RuntimeMainTableProjectionBuilder(windowRecordStore: windowRecordStore)

        let payload = try XCTUnwrap(
            builder.appSwitcherProjectionPayloadFromMainTables(
                appDirectoryEntries: [
                    RuntimeAppDirectoryEntry(
                        pid: alphaPID,
                        appID: "com.example.alpha",
                        bundleIdentifier: "com.example.alpha",
                        localizedName: "Alpha",
                        launchDate: nil,
                        activationRank: 1
                    ),
                    RuntimeAppDirectoryEntry(
                        pid: backgroundPID,
                        appID: "com.example.dupe",
                        bundleIdentifier: "com.example.dupe",
                        localizedName: "Dupe",
                        launchDate: nil,
                        activationRank: 5
                    ),
                    RuntimeAppDirectoryEntry(
                        pid: frontPID,
                        appID: "com.example.dupe",
                        bundleIdentifier: "com.example.dupe",
                        localizedName: "Dupe",
                        launchDate: nil,
                        activationRank: 0
                    )
                ],
                generatedAt: 90
            )
        )

        XCTAssertEqual(payload.apps.map(\.id), ["com.example.dupe", "com.example.alpha"])
        XCTAssertEqual(payload.apps.first?.lastActiveAt, 0)
        XCTAssertEqual(payload.apps.last?.lastActiveAt, -1)
        XCTAssertEqual(payload.apps.first?.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: frontPID, cgWindowID: frontCGWindowID),
            RuntimeWindowListEntry.cgStableWindowID(pid: backgroundPID, cgWindowID: backgroundCGWindowID)
        ])
    }

    func testRuntimeReadModelStoreAppDirectoryProjectionUsesActivationRankEvidence() throws {
        let alphaPID: pid_t = 260_911
        let frontPID: pid_t = 260_912
        let alphaEntry = RuntimeAppDirectoryEntry(
            pid: alphaPID,
            appID: "com.example.alpha",
            bundleIdentifier: "com.example.alpha",
            localizedName: "Alpha",
            launchDate: nil,
            activationRank: 1
        )
        let frontEntry = RuntimeAppDirectoryEntry(
            pid: frontPID,
            appID: "com.example.front",
            bundleIdentifier: "com.example.front",
            localizedName: "Front",
            launchDate: nil,
            activationRank: 0
        )
        let store = RuntimeReadModelStore()

        store.commitAppDirectoryProviderEvidence([alphaEntry, frontEntry], generatedAt: 10)

        var appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), ["com.example.front", "com.example.alpha"])
        XCTAssertEqual(appProjection.apps.map(\.lastActiveAt), [0, -1])
        XCTAssertTrue(appProjection.contextsByID.isEmpty)
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 1)
        let homeProjection = try XCTUnwrap(store.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summaries.map(\.appID), ["com.example.front", "com.example.alpha"])
        XCTAssertEqual(homeProjection.summaries.map(\.windowCount), [0, 0])
        XCTAssertFalse(homeProjection.freshness.isCompleteForScope)
        XCTAssertEqual(homeProjection.freshness.sourceGeneration.appLifecycle, 1)
        var appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertTrue(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().readiness,
            .missingCommittedIndex
        )

        store.commitAppDirectoryProviderEvidence([alphaEntry, frontEntry], generatedAt: 11)
        appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 1)

        let promotedAlphaEntry = RuntimeAppDirectoryEntry(
            pid: alphaPID,
            appID: "com.example.alpha",
            bundleIdentifier: "com.example.alpha",
            localizedName: "Alpha",
            launchDate: nil,
            activationRank: 0
        )
        let demotedFrontEntry = RuntimeAppDirectoryEntry(
            pid: frontPID,
            appID: "com.example.front",
            bundleIdentifier: "com.example.front",
            localizedName: "Front",
            launchDate: nil,
            activationRank: 1
        )

        store.commitAppDirectoryProviderEvidence([promotedAlphaEntry, demotedFrontEntry], generatedAt: 12)

        appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), ["com.example.alpha", "com.example.front"])
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 2)
    }

    func testRuntimeReadModelStoreCurrentAppRepairEvidencePreservesExistingActivationRank() throws {
        let frontPID: pid_t = 260_921
        let alphaPID: pid_t = 260_922
        let rankedFrontEntry = RuntimeAppDirectoryEntry(
            pid: frontPID,
            appID: "com.example.front",
            bundleIdentifier: "com.example.front",
            localizedName: "Front",
            launchDate: nil,
            activationRank: 0
        )
        let rankedAlphaEntry = RuntimeAppDirectoryEntry(
            pid: alphaPID,
            appID: "com.example.alpha",
            bundleIdentifier: "com.example.alpha",
            localizedName: "Alpha",
            launchDate: nil,
            activationRank: 1
        )
        let unrankedFrontRepairEntry = RuntimeAppDirectoryEntry(
            pid: frontPID,
            appID: "com.example.front",
            bundleIdentifier: "com.example.front",
            localizedName: "Front",
            launchDate: nil
        )
        let store = RuntimeReadModelStore()

        store.commitAppDirectoryProviderEvidence([rankedAlphaEntry, rankedFrontEntry], generatedAt: 10)
        store.commitCurrentAppRepairAppDirectoryEvidence([unrankedFrontRepairEntry], generatedAt: 11)

        var appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(
            appDirectoryProjection.entries(forAppID: "com.example.front").first?.activationRank,
            0
        )
        var appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), ["com.example.front", "com.example.alpha"])
        XCTAssertEqual(appProjection.apps.map(\.lastActiveAt), [0, -1])

        let demotedFrontRepairEntry = RuntimeAppDirectoryEntry(
            pid: frontPID,
            appID: "com.example.front",
            bundleIdentifier: "com.example.front",
            localizedName: "Front",
            launchDate: nil,
            activationRank: 2
        )

        store.commitCurrentAppRepairAppDirectoryEvidence([demotedFrontRepairEntry], generatedAt: 12)

        appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 2)
        XCTAssertEqual(
            appDirectoryProjection.entries(forAppID: "com.example.front").first?.activationRank,
            2
        )
        appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), ["com.example.alpha", "com.example.front"])
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().readiness,
            .missingCommittedIndex
        )
    }

    func testRuntimeReadModelStoreKeepsScopedAppDirectoryEvidencePartialUntilCompleteCoverage() throws {
        let scopedEntry = RuntimeAppDirectoryEntry(
            pid: 260_931,
            appID: "com.example.scoped",
            bundleIdentifier: "com.example.scoped",
            localizedName: "Scoped",
            launchDate: nil,
            activationRank: 0
        )
        let providerEntry = RuntimeAppDirectoryEntry(
            pid: 260_932,
            appID: "com.example.provider",
            bundleIdentifier: "com.example.provider",
            localizedName: "Provider",
            launchDate: nil,
            activationRank: 1
        )
        let updatedScopedEntry = RuntimeAppDirectoryEntry(
            pid: scopedEntry.pid,
            appID: scopedEntry.appID,
            bundleIdentifier: scopedEntry.bundleIdentifier,
            localizedName: "Scoped Updated",
            launchDate: nil,
            activationRank: 0
        )
        let store = RuntimeReadModelStore()

        store.commitCurrentAppRepairAppDirectoryEvidence([scopedEntry], generatedAt: 10)

        var appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [scopedEntry])
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertFalse(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertTrue(store.diagnostics().hasAppDirectoryProjection)
        XCTAssertFalse(store.diagnostics().hasCompleteAppDirectoryProjection)
        let appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), [scopedEntry.appID])
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(store.readCommittedSearchIndexForSearch().readiness, .missingCommittedIndex)

        store.commitCurrentAppRepairAppDirectoryEvidence([scopedEntry], generatedAt: 11)
        appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertFalse(appDirectoryProjection.freshness.isCompleteForScope)

        store.commitAppDirectoryProviderEvidence([scopedEntry, providerEntry], generatedAt: 12)

        appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [providerEntry, scopedEntry])
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 2)
        XCTAssertTrue(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertTrue(store.diagnostics().hasCompleteAppDirectoryProjection)

        store.commitCurrentAppRepairAppDirectoryEvidence([updatedScopedEntry], generatedAt: 13)

        appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [providerEntry, updatedScopedEntry])
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 3)
        XCTAssertTrue(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertTrue(store.diagnostics().hasCompleteAppDirectoryProjection)
    }

    func testRuntimeMainTableProjectionBuilderRequiresAppDirectoryEntryForCurrentAppPayload() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let cgWindowID = CGWindowID(240_804)
        let axWindowID = "ax:\(pid):main-table-current-app-directory-required"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let builder: RuntimeMainTableProjectionBuilding = RuntimeMainTableProjectionBuilder(
            windowRecordStore: windowRecordStore
        )

        XCTAssertNil(
            builder.currentAppWindowPayloadFromMainTables(
                appID: appID,
                pid: pid,
                appDirectoryEntries: [],
                generatedAt: 81
            )
        )

        let payload = try XCTUnwrap(
            builder.currentAppWindowPayloadFromMainTables(
                appID: appID,
                pid: pid,
                appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)],
                generatedAt: 82
            )
        )
        XCTAssertEqual(payload.summary.appID, appID)
        XCTAssertEqual(payload.summary.pid, pid)
        XCTAssertEqual(payload.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
    }

    func testRuntimeProjectionServiceCommitsAppSwitcherProjectionFromMainTablesAsStale() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: []
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        readModelStore.markAppWindowsDirty(
            appID: appID,
            pid: pid,
            pendingScope: "appWindows:\(appID)"
        )
        let cgWindowID = CGWindowID(240_802)
        let axWindowID = "ax:\(pid):main-table-switcher"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableAppSwitcherProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()

        let appProjection = try XCTUnwrap(readModelStore.readAppSwitcherProjection())
        let app = try XCTUnwrap(appProjection.apps.first(where: { $0.id == appID }))
        XCTAssertEqual(app.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(app.windows.map(\.title), ["Main Table Projection"])
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.dirtyAppIDs, [appID])
        XCTAssertEqual(appProjection.freshness.dirtyPIDs, [pid])
        XCTAssertTrue(appProjection.freshness.pendingRepairScopes.contains("appWindows:\(appID)"))

        let homeProjection = try XCTUnwrap(readModelStore.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summary(for: appID)?.windowCount, 1)
        XCTAssertFalse(homeProjection.freshness.isCompleteForScope)
        XCTAssertNil(readModelStore.readHomeAppDetailProjection(appID: appID))

        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID), [])
    }

    func testRuntimeProjectionServiceCommitsAppDirectoryProviderProjectionFromMainTablesAsStaleWithFullRepairFallback() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let legacyWindow = WindowCandidate(
            id: "legacy-provider-window",
            title: "Legacy Provider Window",
            isMinimized: false,
            lastActiveAt: 100
        )
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: [legacyWindow]
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        readModelStore.markAppWindowsDirty(
            appID: appID,
            pid: pid,
            pendingScope: "appWindows:\(appID)"
        )
        let cgWindowID = CGWindowID(240_811)
        let axWindowID = "ax:\(pid):main-table-app-directory-provider"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppDirectoryProviderProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            appDirectoryProvider: FixedRuntimeAppDirectoryProvider(entries: [appDirectoryEntry]),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()

        let appDirectoryProjection = try XCTUnwrap(readModelStore.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [appDirectoryEntry])
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 1)
        let appProjection = try XCTUnwrap(readModelStore.readAppSwitcherProjection())
        let app = try XCTUnwrap(appProjection.apps.first(where: { $0.id == appID }))
        XCTAssertEqual(app.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(app.windows.map(\.title), ["Main Table Projection"])
        XCTAssertFalse(app.windows.contains { $0.id == legacyWindow.id })
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(appProjection.freshness.dirtyAppIDs, [appID])
        XCTAssertEqual(appProjection.freshness.dirtyPIDs, [pid])
        XCTAssertTrue(appProjection.freshness.pendingRepairScopes.contains("appWindows:\(appID)"))

        let homeProjection = try XCTUnwrap(readModelStore.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summary(for: appID)?.windowCount, 1)
        XCTAssertFalse(homeProjection.freshness.isCompleteForScope)
        requestLock.lock()
        let startedRequestsAfterAppSwitcherMaintenance = startedRequests
        requestLock.unlock()
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.map(\.target), [.fullRepair])
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.map(\.priority), [.low])
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.first?.reasons, Set([.fullRepairFallback]))

        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID),
            [legacyWindow.id]
        )
    }

    func testRuntimeProjectionServiceKeepsAppDirectoryDerivedProjectionDegradedWithoutMainTableCommit() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let readModelStore = RuntimeReadModelStore()
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppDirectoryDerivedProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: RuntimeWindowRecordStore(),
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeUnavailableMainTableProjectionBuilder(),
            appDirectoryProvider: FixedRuntimeAppDirectoryProvider(entries: [appDirectoryEntry]),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()

        let appDirectoryProjection = try XCTUnwrap(readModelStore.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [appDirectoryEntry])
        XCTAssertTrue(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 1)

        let appProjection = try XCTUnwrap(readModelStore.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), [appID])
        XCTAssertTrue(appProjection.apps.first?.windows.isEmpty == true)
        XCTAssertTrue(appProjection.contextsByID.isEmpty)
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 0)

        let homeProjection = try XCTUnwrap(readModelStore.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summaries.map(\.appID), [appID])
        XCTAssertEqual(homeProjection.summary(for: appID)?.windowCount, 0)
        XCTAssertFalse(homeProjection.freshness.isCompleteForScope)
        XCTAssertEqual(homeProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(homeProjection.freshness.sourceGeneration.projection, 0)

        requestLock.lock()
        let startedRequestsAfterAppSwitcherMaintenance = startedRequests
        requestLock.unlock()
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.map(\.target), [.fullRepair])
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.map(\.priority), [.low])
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.first?.reasons, Set([.fullRepairFallback]))
        XCTAssertEqual(
            readModelStore.readCommittedSearchIndexForSearch().readiness,
            .missingCommittedIndex
        )
    }

    func testRuntimeProjectionServiceKeepsAppDirectoryOnlyMainTableProjectionIncompleteForSearch() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let windowRecordStore = RuntimeWindowRecordStore()
        let readModelStore = RuntimeReadModelStore()
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppDirectoryOnlyMainTableProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            appDirectoryProvider: FixedRuntimeAppDirectoryProvider(entries: [appDirectoryEntry]),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()

        let appProjection = try XCTUnwrap(readModelStore.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), [appID])
        XCTAssertTrue(appProjection.apps.first?.windows.isEmpty == true)
        XCTAssertNotNil(appProjection.contextsByID[appID])
        XCTAssertTrue(appProjection.contextsByID[appID]?.windowsByID.isEmpty == true)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 1)
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)

        let homeProjection = try XCTUnwrap(readModelStore.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summary(for: appID)?.windowCount, 0)
        XCTAssertEqual(homeProjection.freshness.sourceGeneration.projection, 1)
        XCTAssertFalse(homeProjection.freshness.isCompleteForScope)
        XCTAssertEqual(
            readModelStore.readCommittedSearchIndexForSearch().readiness,
            .missingCommittedIndex
        )
        requestLock.lock()
        let startedRequestsAfterAppSwitcherMaintenance = startedRequests
        requestLock.unlock()
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.map(\.target), [.fullRepair])
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.map(\.priority), [.low])
        XCTAssertEqual(startedRequestsAfterAppSwitcherMaintenance.first?.reasons, Set([.fullRepairFallback]))

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        service.waitForMaintenanceQueueForTesting()

        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .missingCommittedIndex)
        XCTAssertEqual(searchRead.resultState, .missingCommittedIndex)
        XCTAssertNil(searchRead.projection)
    }

    func testRuntimeProjectionServiceCommitsSpaceTopologyProjectionFromMainTablesAsStale() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let legacyWindow = WindowCandidate(
            id: "legacy-space-topology-window",
            title: "Legacy Space Topology Window",
            isMinimized: false,
            lastActiveAt: 100
        )
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: [legacyWindow]
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        let cgWindowID = CGWindowID(240_810)
        let axWindowID = "ax:\(pid):main-table-space-topology"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableSpaceTopologyProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                cgWindowListProvider: FixedRuntimeCGWindowListProvider(
                    rawWindowInfo: [
                        makeRawCGWindowInfo(
                            pid: pid,
                            windowID: cgWindowID,
                            title: "Sampled Space Topology Window"
                        )
                    ]
                ),
                spaceTopologyProvider: FixedRuntimeSpaceTopologyProvider(
                    snapshot: RuntimeSpaceTopologySnapshot(
                        spacesByID: [
                            7: RuntimeSpaceTopologySpace(id: 7, displayID: 1, isCurrent: true)
                        ],
                        windowIDsBySpaceID: [
                            7: [cgWindowID]
                        ],
                        spaceIDsByCGWindowID: [
                            cgWindowID: [7]
                        ]
                    )
                ),
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.signalSpaceTopologyChanged()
        service.waitForMaintenanceQueueForTesting()

        let appProjection = try XCTUnwrap(readModelStore.readAppSwitcherProjection())
        let app = try XCTUnwrap(appProjection.apps.first(where: { $0.id == appID }))
        XCTAssertEqual(app.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(app.windows.map(\.title), ["Main Table Projection"])
        let projectedWindowID = try XCTUnwrap(app.windows.first?.id)
        let contextWindow = try XCTUnwrap(
            appProjection.contextsByID[appID]?.windowsByID[projectedWindowID]
        )
        XCTAssertEqual(contextWindow.cgWindowID, cgWindowID)
        XCTAssertEqual(contextWindow.spaceIDs, [5])
        XCTAssertTrue(appProjection.freshness.isCompleteForScope)
        XCTAssertTrue(appProjection.freshness.dirtyCGWindowIDs.isEmpty)
        XCTAssertNil(appProjection.freshness.spaceTopologySignatureSummary)
        XCTAssertFalse(appProjection.freshness.pendingRepairScopes.contains("spaceTopology"))

        let homeProjection = try XCTUnwrap(readModelStore.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summary(for: appID)?.windowCount, 1)
        XCTAssertTrue(homeProjection.freshness.isCompleteForScope)
        requestLock.lock()
        let startedTargets = startedRequests.map(\.target)
        requestLock.unlock()
        XCTAssertEqual(startedTargets, [.spaceTopology])
        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(searchRead.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(searchRead.freshness?.dirtyCGWindowIDs, [])
        XCTAssertEqual(searchRead.freshness?.pendingRepairScopes, [])
        XCTAssertEqual(
            searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID),
            [legacyWindow.id]
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        service.waitForMaintenanceQueueForTesting()

        let freshSearchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(freshSearchRead.readiness, .committedGenerationValidated)
        XCTAssertEqual(freshSearchRead.resultState, .committedGenerationResult)
        XCTAssertTrue(freshSearchRead.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(
            freshSearchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID),
            [projectedWindowID]
        )
    }

    func testRuntimeProjectionServiceCommitsLaunchedAppProjectionFromMainTablesAsStale() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: []
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        let cgWindowID = CGWindowID(240_806)
        let axWindowID = "ax:\(pid):main-table-launch"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let coordinator = RuntimeReconciliationCoordinator()
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableAppLaunchProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: coordinator
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.signalAppLaunched(
            appID: appID,
            pid: pid,
            appDirectoryEntry: appDirectoryEntry
        )
        service.waitForMaintenanceQueueForTesting()

        let appProjection = try XCTUnwrap(readModelStore.readAppSwitcherProjection())
        let app = try XCTUnwrap(appProjection.apps.first(where: { $0.id == appID }))
        XCTAssertEqual(app.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(app.windows.map(\.title), ["Main Table Projection"])
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.dirtyAppIDs, [appID])
        XCTAssertEqual(appProjection.freshness.dirtyPIDs, [pid])
        XCTAssertTrue(appProjection.freshness.pendingRepairScopes.contains("appLaunched:\(appID)"))

        let homeProjection = try XCTUnwrap(readModelStore.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summary(for: appID)?.windowCount, 1)
        XCTAssertFalse(homeProjection.freshness.isCompleteForScope)

        requestLock.lock()
        let startedTargets = startedRequests.map(\.target)
        requestLock.unlock()
        XCTAssertEqual(startedTargets, [.app(pid)])
        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID), [])
    }

    func testRuntimeProjectionServiceCommitsTerminationProjectionFromMainTablesWithoutRefreshingSearch() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let cgWindowID = CGWindowID(240_807)
        let axWindowID = "ax:\(pid):main-table-termination"
        let terminatedAppID = "com.example.terminated-main-table"
        let terminatedPID = pid_t(pid + 40_807)
        let legacyWindow = WindowCandidate(
            id: "legacy-cache-contamination",
            title: "Legacy Cache Contamination",
            isMinimized: false,
            lastActiveAt: 100
        )
        let survivingApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: [legacyWindow]
        )
        let terminatedApp = AppSwitchCandidate(
            id: terminatedAppID,
            displayName: "Terminated",
            groupID: "terminated",
            lastActiveAt: 90,
            windows: [
                WindowCandidate(
                    id: "terminated-cache-window",
                    title: "Terminated Cache Window",
                    isMinimized: false,
                    lastActiveAt: 90
                )
            ]
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [survivingApp, terminatedApp],
            contextsByID: [:],
            appDirectoryEntries: [
                RuntimeAppDirectoryEntry(app: runningApp),
                RuntimeAppDirectoryEntry(
                    pid: terminatedPID,
                    appID: terminatedAppID,
                    bundleIdentifier: terminatedAppID,
                    localizedName: "Terminated",
                    launchDate: nil
                )
            ],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableTerminationProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore
        )

        service.signalAppTerminated(appID: terminatedAppID, pid: terminatedPID)
        service.waitForMaintenanceQueueForTesting()

        let appProjection = try XCTUnwrap(readModelStore.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), [appID])
        let app = try XCTUnwrap(appProjection.apps.first)
        XCTAssertEqual(app.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(app.windows.map(\.title), ["Main Table Projection"])
        XCTAssertFalse(appProjection.apps.contains { $0.id == terminatedAppID })
        XCTAssertTrue(appProjection.freshness.isCompleteForScope)

        let homeProjection = try XCTUnwrap(readModelStore.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summaries.map(\.appID), [appID])
        XCTAssertEqual(homeProjection.summary(for: appID)?.windowCount, 1)
        XCTAssertTrue(homeProjection.freshness.isCompleteForScope)

        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID),
            [legacyWindow.id]
        )
        XCTAssertTrue(searchRead.projection?.appEntries.contains { $0.appID == terminatedAppID } ?? false)
        XCTAssertEqual(
            searchRead.projection?.windowEntries
                .filter { $0.appID == terminatedAppID }
                .map(\.windowTitle),
            ["Terminated Cache Window"]
        )
    }

    func testRuntimeProjectionServiceCommitsAXDestroyedProjectionFromMainTablesAsStale() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let legacyWindow = WindowCandidate(
            id: "legacy-ax-destroyed-window",
            title: "Legacy AX Destroyed Window",
            isMinimized: false,
            lastActiveAt: 100
        )
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: [legacyWindow]
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        let cgWindowID = CGWindowID(240_808)
        let axWindowID = "ax:\(pid):main-table-ax-destroyed"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableAXDestroyedProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.signalAXWindowDestroyed(
            appID: appID,
            pid: pid,
            axWindowID: axWindowID
        )
        service.waitForMaintenanceQueueForTesting()

        let projection = try XCTUnwrap(readModelStore.readCurrentAppWindowProjection(appID: appID))
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.title), [
            "Main Table Projection"
        ])
        let projectedWindowID = try XCTUnwrap(
            projection.currentAppWindowPayload.candidate.windows.first?.id
        )
        let contextWindow = projection.currentAppWindowPayload.context.windowsByID[projectedWindowID]
        XCTAssertEqual(contextWindow?.cgWindowID, cgWindowID)
        XCTAssertNil(contextWindow?.axWindow)
        XCTAssertFalse(projection.freshness.isCompleteForScope)
        XCTAssertEqual(projection.freshness.dirtyAppIDs, [appID])
        XCTAssertEqual(projection.freshness.dirtyPIDs, [pid])
        XCTAssertTrue(projection.freshness.pendingRepairScopes.contains("axWindowDestroyed:\(appID)"))

        let homeDetailProjection = try XCTUnwrap(
            readModelStore.readHomeAppDetailProjection(appID: appID)
        )
        XCTAssertEqual(homeDetailProjection.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertNil(homeDetailProjection.context.windowsByID[projectedWindowID]?.axWindow)

        let downgradedRecord = windowRecordStore.state(for: pid)?
            .windowRecordsByCGWindowID[cgWindowID]
        XCTAssertNil(downgradedRecord?.currentAXAttachment)
        XCTAssertTrue(downgradedRecord?.needsReconciliation == true)
        requestLock.lock()
        let startedTargets = startedRequests.map(\.target)
        requestLock.unlock()
        XCTAssertEqual(startedTargets, [.app(pid)])
        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID),
            [legacyWindow.id]
        )
    }

    func testRuntimeProjectionServiceCommitsVerifiedFocusProjectionFromMainTablesAsStale() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let legacyWindow = WindowCandidate(
            id: "legacy-verified-focus-window",
            title: "Legacy Verified Focus Window",
            isMinimized: false,
            lastActiveAt: 100
        )
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: [legacyWindow]
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        let focusedCGWindowID = CGWindowID(240_809)
        let focusedAXWindow = AXUIElementCreateApplication(pid)
        let focusedAXWindowID = AXWindowInspectorForTesting.makeWindowID(pid: pid, index: 0)
        let focusedReadbackTitle = AXWindowInspector.title(for: focusedAXWindow)
            ?? "Verified Focus Main Table"
        AXLiveWindowRegistry.shared.replaceWindows(forPID: pid, with: [focusedAXWindow])
        defer { AXLiveWindowRegistry.shared.remove(pid: pid) }
        let windowRecordStore = RuntimeWindowRecordStore()
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableVerifiedFocusProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: appID,
                windowID: RuntimeWindowListEntry.cgStableWindowID(
                    pid: pid,
                    cgWindowID: focusedCGWindowID
                ),
                ownerPID: pid,
                targetCGWindowID: focusedCGWindowID,
                focusedCGWindowID: focusedCGWindowID,
                focusedAXWindow: focusedAXWindow,
                title: "Verified Focus Main Table",
                frame: CGRect(x: 25, y: 35, width: 640, height: 480),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )
        )
        service.waitForMaintenanceQueueForTesting()

        let projection = try XCTUnwrap(readModelStore.readCurrentAppWindowProjection(appID: appID))
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: focusedCGWindowID)
        ])
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.title), [
            focusedReadbackTitle
        ])
        let projectedWindowID = try XCTUnwrap(
            projection.currentAppWindowPayload.candidate.windows.first?.id
        )
        let contextWindow = try XCTUnwrap(
            projection.currentAppWindowPayload.context.windowsByID[projectedWindowID]
        )
        XCTAssertEqual(contextWindow.cgWindowID, focusedCGWindowID)
        XCTAssertEqual(contextWindow.activationHandleID, focusedAXWindowID)
        XCTAssertTrue(contextWindow.axWindow.map { CFEqual($0, focusedAXWindow) } == true)
        XCTAssertEqual(contextWindow.lastConfirmationSource, .verifiedFocusReadback)
        XCTAssertFalse(projection.freshness.isCompleteForScope)
        XCTAssertEqual(projection.freshness.dirtyAppIDs, [appID])
        XCTAssertEqual(projection.freshness.dirtyPIDs, [pid])
        XCTAssertEqual(projection.freshness.dirtyCGWindowIDs, [focusedCGWindowID])
        XCTAssertTrue(projection.freshness.pendingRepairScopes.contains("activationVerified:\(appID)"))

        let homeDetailProjection = try XCTUnwrap(
            readModelStore.readHomeAppDetailProjection(appID: appID)
        )
        XCTAssertEqual(homeDetailProjection.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: focusedCGWindowID)
        ])
        XCTAssertEqual(
            homeDetailProjection.context.windowsByID[projectedWindowID]?.lastConfirmationSource,
            .verifiedFocusReadback
        )
        let record = try XCTUnwrap(
            windowRecordStore.state(for: pid)?
                .windowRecordsByCGWindowID[focusedCGWindowID]
        )
        XCTAssertEqual(record.lastConfirmationSource, .verifiedFocusReadback)
        XCTAssertEqual(record.currentAXWindowID, focusedAXWindowID)
        requestLock.lock()
        let startedTargets = startedRequests.map(\.target)
        requestLock.unlock()
        XCTAssertEqual(startedTargets, [.app(pid)])
        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID),
            [legacyWindow.id]
        )
    }

    func testRuntimeProjectionServiceCommitsSearchIndexFromMainTableProjectionOnlyAfterBarrier() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: []
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        readModelStore.markAppWindowsDirty(
            appID: appID,
            pid: pid,
            pendingScope: "appWindows:\(appID)"
        )
        let cgWindowID = CGWindowID(240_803)
        let axWindowID = "ax:\(pid):main-table-search"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableSearchProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()

        var searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID), [])

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        service.waitForMaintenanceQueueForTesting()

        searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .committedGenerationValidated)
        XCTAssertEqual(searchRead.resultState, .committedGenerationResult)
        XCTAssertEqual(searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertTrue(readModelStore.diagnostics().dirtyAppIDs.isEmpty)
    }

    func testRuntimeReadModelStoreDoesNotCommitSearchFromStaleProjectionCache() throws {
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = try XCTUnwrap(committedApps.first)
        let pid = pid_t(42_120)
        store.seedAppSwitcherProjectionForTesting(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(store, generatedAt: 11)
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )

        let committed = store.commitSearchFreshnessBarrierFromProjectionCache(
            deferredRequestCount: 0,
            hasPendingRequests: false,
            generatedAt: 20
        )

        XCTAssertNil(committed)
        let read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .degradedStaleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(read.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(
            read.projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            repairedApp.windows.map(\.id)
        )
        XCTAssertEqual(store.diagnostics().dirtyAppIDs, [repairedApp.id])
    }

    func testRuntimeReadModelStoreCommitsSearchFromCurrentProjectionCacheAfterBarrierValidation() throws {
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 340,
            windows: [
                WindowCandidate(
                    id: "browser-main-table-search",
                    title: "Main Table Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 340
                )
            ]
        )
        let pid = pid_t(42_121)
        store.seedAppSwitcherProjectionForTesting(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(store, generatedAt: 11)
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        store.commitMainTableAppSwitcherProjectionPayload(
            RuntimeAppSwitcherProjectionPayload(
                apps: [repairedApp],
                contextsByID: [:]
            ),
            generatedAt: 20
        )

        var read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .degradedStaleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)

        let committed = try XCTUnwrap(
            store.commitSearchFreshnessBarrierFromProjectionCache(
                deferredRequestCount: 0,
                hasPendingRequests: false,
                generatedAt: 21
            )
        )

        XCTAssertTrue(committed.freshness.isCompleteForScope)
        read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .committedGenerationValidated)
        XCTAssertEqual(read.resultState, .committedGenerationResult)
        XCTAssertEqual(
            read.projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-main-table-search"]
        )
        XCTAssertTrue(store.diagnostics().dirtyAppIDs.isEmpty)
    }

    func testRuntimeProjectionServiceCommitsSelectedCurrentAppProjectionFromMainTablesAsStale() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: []
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        let cgWindowID = CGWindowID(240_601)
        let axWindowID = "ax:\(pid):main-table"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let coordinator = RuntimeReconciliationCoordinator()
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableCurrentAppProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: coordinator
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.signalSelectedCurrentAppWindowsChanged(appID: appID, pid: pid)
        service.waitForMaintenanceQueueForTesting()

        let projection = try XCTUnwrap(readModelStore.readCurrentAppWindowProjection(appID: appID))
        XCTAssertEqual(projection.currentAppWindowPayload.summary.appID, appID)
        XCTAssertEqual(projection.currentAppWindowPayload.summary.pid, pid)
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.title), [
            "Main Table Projection"
        ])
        let projectedWindowID = try XCTUnwrap(
            projection.currentAppWindowPayload.candidate.windows.first?.id
        )
        XCTAssertEqual(
            projection.currentAppWindowPayload.context.windowsByID[projectedWindowID]?.cgWindowID,
            cgWindowID
        )
        XCTAssertFalse(projection.freshness.isCompleteForScope)
        XCTAssertEqual(projection.freshness.dirtyAppIDs, [appID])
        XCTAssertEqual(projection.freshness.dirtyPIDs, [pid])
        XCTAssertTrue(
            projection.freshness.pendingRepairScopes.contains("selectedCurrentAppWindows:\(appID)")
        )

        requestLock.lock()
        let startedTargets = startedRequests.map(\.target)
        requestLock.unlock()
        XCTAssertEqual(startedTargets, [.app(pid)])
        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID), [])
    }

    func testRuntimeProjectionServiceCommitsAppWindowDirtyProjectionForHomeDetailFromMainTablesAsStale() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: []
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        let cgWindowID = CGWindowID(240_805)
        let axWindowID = "ax:\(pid):main-table-home-detail"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let coordinator = RuntimeReconciliationCoordinator()
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MainTableHomeDetailProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: coordinator
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.signalAppWindowsChanged(appID: appID, pid: pid)
        service.waitForMaintenanceQueueForTesting()

        let projection = try XCTUnwrap(readModelStore.readCurrentAppWindowProjection(appID: appID))
        XCTAssertEqual(projection.currentAppWindowPayload.summary.appID, appID)
        XCTAssertEqual(projection.currentAppWindowPayload.summary.pid, pid)
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertFalse(projection.freshness.isCompleteForScope)
        XCTAssertEqual(projection.freshness.dirtyAppIDs, [appID])
        XCTAssertTrue(projection.freshness.pendingRepairScopes.contains("appWindows:\(appID)"))

        let homeDetailProjection = try XCTUnwrap(
            readModelStore.readHomeAppDetailProjection(appID: appID)
        )
        XCTAssertEqual(homeDetailProjection.summary.windowCount, 1)
        XCTAssertEqual(homeDetailProjection.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        let projectedWindowID = try XCTUnwrap(homeDetailProjection.candidate.windows.first?.id)
        XCTAssertEqual(
            homeDetailProjection.context.windowsByID[projectedWindowID]?.cgWindowID,
            cgWindowID
        )

        requestLock.lock()
        let startedTargets = startedRequests.map(\.target)
        requestLock.unlock()
        XCTAssertEqual(startedTargets, [.app(pid)])
        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID), [])
    }

    func testRuntimeProjectionServiceCommitsCurrentAppProjectionFromAppDirectoryProviderEvidence() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let displayName = runningApp.localizedName ?? appID
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let legacyWindow = WindowCandidate(
            id: "legacy-current-app-provider-window",
            title: "Legacy Current App Provider Window",
            isMinimized: false,
            lastActiveAt: 100
        )
        let committedApp = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: displayName
            ),
            lastActiveAt: 100,
            windows: [legacyWindow]
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [committedApp],
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        commitMainTableSearchFreshnessBarrierForTesting(readModelStore, generatedAt: 11)
        let cgWindowID = CGWindowID(240_812)
        let axWindowID = "ax:\(pid):main-table-current-app-provider"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: pid,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let requestLock = NSLock()
        var startedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.CurrentAppProviderProjection",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            appDirectoryProvider: FixedRuntimeAppDirectoryProvider(entries: [appDirectoryEntry]),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                startedRequests.append(request)
                requestLock.unlock()
                return .completed
            }
        )

        service.signalAppWindowsChanged(appID: appID, pid: pid)
        service.waitForMaintenanceQueueForTesting()

        let appDirectoryProjection = try XCTUnwrap(readModelStore.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [appDirectoryEntry])
        let projection = try XCTUnwrap(readModelStore.readCurrentAppWindowProjection(appID: appID))
        XCTAssertEqual(projection.currentAppWindowPayload.summary.appID, appID)
        XCTAssertEqual(projection.currentAppWindowPayload.summary.pid, pid)
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        XCTAssertEqual(projection.currentAppWindowPayload.candidate.windows.map(\.title), [
            "Main Table Projection"
        ])
        XCTAssertFalse(projection.currentAppWindowPayload.candidate.windows.contains {
            $0.id == legacyWindow.id
        })
        XCTAssertFalse(projection.freshness.isCompleteForScope)
        XCTAssertEqual(projection.freshness.dirtyAppIDs, [appID])
        XCTAssertTrue(projection.freshness.pendingRepairScopes.contains("appWindows:\(appID)"))

        let homeDetailProjection = try XCTUnwrap(
            readModelStore.readHomeAppDetailProjection(appID: appID)
        )
        XCTAssertEqual(homeDetailProjection.summary.windowCount, 1)
        XCTAssertEqual(homeDetailProjection.candidate.windows.map(\.id), [
            RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        ])
        requestLock.lock()
        let startedTargets = startedRequests.map(\.target)
        requestLock.unlock()
        XCTAssertEqual(startedTargets, [.app(pid)])

        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID),
            [legacyWindow.id]
        )
    }

    func testRuntimeReadModelStoreOwnsHomeDetailProjectionFromCurrentAppCache() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let window = WindowCandidate(
            id: "main-table-home-detail-window",
            title: "Main Table Home Detail",
            isMinimized: false,
            lastActiveAt: 500
        )
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: runningApp.localizedName ?? appID,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: runningApp.localizedName ?? appID
            ),
            lastActiveAt: 500,
            windows: [window]
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: [
                window.id: RuntimeWindowContext(
                    id: window.id,
                    title: window.title,
                    isMinimized: window.isMinimized,
                    ownerPID: runningApp.processIdentifier,
                    cgWindowID: 240_701,
                    spaceIDs: [5]
                )
            ]
        )
        let summary = RuntimeHomeAppSummary(
            appID: appID,
            displayName: candidate.displayName,
            groupID: candidate.groupID,
            lastActiveAt: candidate.lastActiveAt,
            windowCount: candidate.windows.count,
            pid: runningApp.processIdentifier
        )
        let payload = RuntimeCurrentAppWindowPayload(
            summary: summary,
            candidate: candidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let store = RuntimeReadModelStore()

        store.commitCurrentAppWindowProjection(payload, generatedAt: 42)

        XCTAssertNil(store.readAppDirectoryProjection())
        XCTAssertNil(store.readAppSwitcherProjection())
        XCTAssertNil(store.readHomeSummaryProjection())
        let homeDetailProjection = try XCTUnwrap(
            store.readHomeAppDetailProjection(appID: appID)
        )
        XCTAssertEqual(homeDetailProjection.summary, summary)
        XCTAssertEqual(homeDetailProjection.candidate.windows.map(\.id), [window.id])
        XCTAssertEqual(
            homeDetailProjection.context.windowsByID[window.id]?.cgWindowID,
            240_701
        )
        XCTAssertTrue(homeDetailProjection.freshness.isCompleteForScope)

        store.markAppWindowsDirty(
            appID: appID,
            pid: runningApp.processIdentifier,
            pendingScope: "appWindows:\(appID)"
        )

        let staleHomeDetailProjection = try XCTUnwrap(
            store.readHomeAppDetailProjection(appID: appID)
        )
        XCTAssertEqual(staleHomeDetailProjection.summary, summary)
        XCTAssertFalse(staleHomeDetailProjection.freshness.isCompleteForScope)
        XCTAssertEqual(staleHomeDetailProjection.freshness.dirtyAppIDs, [appID])
        XCTAssertEqual(staleHomeDetailProjection.freshness.dirtyPIDs, [runningApp.processIdentifier])
        XCTAssertTrue(staleHomeDetailProjection.freshness.pendingRepairScopes.contains("appWindows:\(appID)"))
    }

    func testRuntimeReadModelStoreDoesNotDeriveHomeDetailFromAppSwitcherProjection() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let window = WindowCandidate(
            id: "app-switcher-only-home-detail-window",
            title: "App Switcher Only Home Detail",
            isMinimized: false,
            lastActiveAt: 500
        )
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: runningApp.localizedName ?? appID,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: runningApp.localizedName ?? appID
            ),
            lastActiveAt: 500,
            windows: [window]
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: [
                window.id: RuntimeWindowContext(
                    id: window.id,
                    title: window.title,
                    isMinimized: window.isMinimized,
                    ownerPID: runningApp.processIdentifier,
                    cgWindowID: 240_702,
                    spaceIDs: [5]
                )
            ]
        )
        let store = RuntimeReadModelStore()

        store.seedAppSwitcherProjectionForTesting(
            apps: [candidate],
            contextsByID: [appID: context],
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)],
            generatedAt: 42
        )

        XCTAssertNotNil(store.readAppSwitcherProjection()?.contextsByID[appID])
        XCTAssertNotNil(store.readHomeSummaryProjection()?.summary(for: appID))
        XCTAssertNil(store.readHomeAppDetailProjection(appID: appID))
    }

    private func makeMainTableProjectionWindowRecord(
        pid: pid_t,
        cgWindowID: CGWindowID,
        axWindowID: String
    ) -> RuntimeWindowRecord {
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindowID,
            stableWindowID: RuntimeWindowListEntry.cgStableWindowID(
                pid: pid,
                cgWindowID: cgWindowID
            ),
            firstSeenAt: 10
        )
        record.currentAXAttachment = RuntimeCurrentAXAttachment(
            axWindowID: axWindowID,
            axWindow: AXUIElementCreateApplication(pid),
            title: "Main Table Projection",
            frame: CGRect(x: 40, y: 50, width: 900, height: 700),
            state: RuntimeAXWindowState(isMinimized: false, isFocused: true, isMain: true)
        )
        record.lastKnownCGTitle = "Main Table Projection"
        record.lastKnownCGFrame = CGRect(x: 40, y: 50, width: 900, height: 700)
        record.lastConfirmationSource = .verifiedFocusReadback
        record.lastExactConfirmedAt = 12
        record.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: cgWindowID,
            spaceIDs: [5],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: 12,
            invalidatedAt: nil
        )
        return record
    }

    private final class FixedRuntimeAppDirectoryProvider: RuntimeAppDirectoryProviding {
        private let entries: [RuntimeAppDirectoryEntry]

        init(entries: [RuntimeAppDirectoryEntry]) {
            self.entries = entries
        }

        func appDirectoryEntriesForRuntimeMaintenance() -> [RuntimeAppDirectoryEntry] {
            entries
        }
    }
}
