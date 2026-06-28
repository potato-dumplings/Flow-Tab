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
        readModelStore.commitAppSwitcherProjection(
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
        let detailProjection = try XCTUnwrap(readModelStore.readHomeAppDetailProjection(appID: appID))
        XCTAssertEqual(detailProjection.candidate.windows.map(\.id), app.windows.map(\.id))

        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .degradedStaleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(searchRead.projection?.windowEntries.filter { $0.appID == appID }.map(\.windowID), [])
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
        readModelStore.commitAppSwitcherProjection(
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
        readModelStore.commitAppSwitcherProjection(
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
        XCTAssertFalse(searchRead.projection?.appEntries.contains { $0.appID == terminatedAppID } ?? true)
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
        readModelStore.commitAppSwitcherProjection(
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
        store.commitAppSwitcherProjection(
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
        store.commitAppSwitcherProjection(
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
        readModelStore.commitAppSwitcherProjection(
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
        readModelStore.commitAppSwitcherProjection(
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

        let homeDetailProjection = try XCTUnwrap(
            store.readHomeAppDetailProjection(appID: appID)
        )
        XCTAssertEqual(homeDetailProjection.summary, summary)
        XCTAssertEqual(homeDetailProjection.candidate.windows.map(\.id), [window.id])
        XCTAssertEqual(
            homeDetailProjection.context.windowsByID[window.id]?.cgWindowID,
            240_701
        )
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
}
