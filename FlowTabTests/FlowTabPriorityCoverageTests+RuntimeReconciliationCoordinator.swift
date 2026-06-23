import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    private func appDirectoryStateFreshness(_ generatedAt: TimeInterval) -> RuntimeProjectionFreshness {
        RuntimeProjectionFreshness(
            generatedAt: generatedAt,
            sourceGeneration: RuntimeReadModelGeneration(),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
    }

    func testRuntimeReadModelStoreCommitsProjectionsAndMarksDirtyMetadata() throws {
        let store = RuntimeReadModelStore()
        let apps = searchScenarioApps()
        let app = try XCTUnwrap(apps.first)
        let pid = NSRunningApplication.current.processIdentifier
        let generatedAt = TimeInterval(42)
        let initialDirectoryEntry = RuntimeAppDirectoryEntry(
            pid: pid,
            appID: app.id,
            bundleIdentifier: "com.example.initial",
            localizedName: app.displayName,
            launchDate: nil
        )

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [app.id: makeRuntimeAppContext(
                appID: app.id,
                runningApp: .current,
                windows: app.windows
            )],
            appDirectoryEntries: [initialDirectoryEntry],
            generatedAt: generatedAt
        )

        var appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), apps.map(\.id))
        XCTAssertEqual(appProjection.freshness.generatedAt, generatedAt)
        XCTAssertTrue(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 1)
        let searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .verifiedCurrentGenerationCommitted)
        let searchProjection = try XCTUnwrap(searchRead.projection)
        XCTAssertEqual(searchProjection.appEntries.map(\.appID), apps.map(\.id))
        XCTAssertEqual(
            searchProjection.windowEntries.map(\.windowID),
            apps.flatMap(\.windows).map(\.id)
        )
        XCTAssertEqual(searchProjection.freshness.generatedAt, generatedAt)
        XCTAssertTrue(searchProjection.freshness.isCompleteForScope)
        var appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [initialDirectoryEntry])
        XCTAssertEqual(appDirectoryProjection.freshness.generatedAt, generatedAt)
        XCTAssertTrue(appDirectoryProjection.freshness.isCompleteForScope)

        store.markAppWindowsDirty(
            appID: app.id,
            pid: pid,
            pendingScope: "appWindows:\(app.id)"
        )

        appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.dirtyAppIDs, [app.id])
        XCTAssertEqual(appProjection.freshness.dirtyPIDs, [pid])
        XCTAssertEqual(appProjection.freshness.pendingRepairScopes, ["appWindows:\(app.id)"])
        XCTAssertEqual(appProjection.freshness.sourceGeneration.axDirty, 1)
        appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertFalse(appDirectoryProjection.freshness.isCompleteForScope)

        let summary = RuntimeHomeAppSummary(
            appID: app.id,
            displayName: app.displayName,
            groupID: app.groupID,
            lastActiveAt: app.lastActiveAt,
            windowCount: app.windows.count,
            pid: pid
        )
        let payload = RuntimeCurrentAppWindowPayload(
            summary: summary,
            candidate: app,
            context: makeRuntimeAppContext(
                appID: app.id,
                runningApp: .current,
                windows: app.windows
            ),
            appDirectoryEntries: [initialDirectoryEntry]
        )

        store.commitCurrentAppWindowProjection(payload, generatedAt: generatedAt + 1)

        let currentAppProjection = try XCTUnwrap(
            store.readCurrentAppWindowProjection(appID: app.id)
        )
        XCTAssertEqual(currentAppProjection.currentAppWindowPayload.candidate.id, app.id)
        XCTAssertEqual(currentAppProjection.currentAppWindowPayload.summary.appID, app.id)
        XCTAssertEqual(currentAppProjection.currentAppWindowPayload.context.appID, app.id)
        XCTAssertTrue(currentAppProjection.freshness.isCompleteForScope)
        XCTAssertEqual(currentAppProjection.freshness.sourceGeneration.projection, 2)
        let repairedAppProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(
            repairedAppProjection.apps.first(where: { $0.id == app.id })?.windows.map(\.id),
            app.windows.map(\.id)
        )
        XCTAssertNotNil(repairedAppProjection.contextsByID[app.id])
        let homeProjection = try XCTUnwrap(store.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summaries.map(\.appID), apps.map(\.id))
        XCTAssertEqual(homeProjection.summary(for: app.id)?.windowCount, app.windows.count)
        XCTAssertEqual(homeProjection.freshness.generatedAt, generatedAt + 1)
        XCTAssertTrue(homeProjection.freshness.isCompleteForScope)
        let diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.dirtyAppIDs.isEmpty)
        XCTAssertEqual(diagnostics.currentAppWindowProjectionAppIDs, [app.id])
        XCTAssertTrue(diagnostics.hasAppDirectoryProjection)
        XCTAssertEqual(diagnostics.appDirectoryEntryPIDs, [pid])
        appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertTrue(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appDirectoryProjection.entries(forAppID: app.id).map(\.pid), [pid])
    }

    func testRuntimeReadModelStoreFullRepairColdStartCommitsCurrentSearchIndex() throws {
        let store = RuntimeReadModelStore()
        let apps = searchScenarioApps()
        let app = try XCTUnwrap(apps.first)
        let pid = pid_t(42_201)
        let entry = RuntimeAppDirectoryEntry(
            pid: pid,
            appID: app.id,
            bundleIdentifier: "com.example.cold-start",
            localizedName: app.displayName,
            launchDate: nil
        )

        let summary = store.commitFullRepairProjectionPayload(
            RuntimeFullRepairProjectionPayload(
                apps: apps,
                contextsByID: [app.id: makeRuntimeAppContext(
                    appID: app.id,
                    runningApp: .current,
                    windows: app.windows
                )],
                appDirectoryEntries: [entry]
            ),
            generatedAt: 30
        )

        XCTAssertEqual(summary.coldStartCommittedCount, 1)
        XCTAssertEqual(summary.degradedCommittedCount, 0)
        let appSwitcherProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertTrue(appSwitcherProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appSwitcherProjection.apps.map(\.id), apps.map(\.id))
        let searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .verifiedCurrentGenerationCommitted)
        XCTAssertEqual(searchRead.resultState, .verifiedCurrentGenerationCommittedResult)
        XCTAssertTrue(searchRead.committedIndexCoversCurrentGeneration)
        let searchProjection = try XCTUnwrap(searchRead.projection)
        XCTAssertEqual(searchProjection.windowEntries.map(\.windowID), apps.flatMap(\.windows).map(\.id))
        let directoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(directoryProjection.entries, [entry])
        XCTAssertTrue(directoryProjection.freshness.isCompleteForScope)
    }

    func testRuntimeReadModelStoreDirtyFullRepairCommitsDegradedProjectionAndKeepsSearchStale() throws {
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let committedApp = try XCTUnwrap(committedApps.first)
        let pid = pid_t(42_202)
        let repairedApp = AppSwitchCandidate(
            id: committedApp.id,
            displayName: committedApp.displayName,
            groupID: committedApp.groupID,
            lastActiveAt: 720,
            windows: [
                WindowCandidate(
                    id: "full-repair-rebuilt-window",
                    title: "Full Repair Rebuilt Window",
                    isMinimized: false,
                    lastActiveAt: 720
                )
            ]
        )

        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )

        let summary = store.commitFullRepairProjectionPayload(
            RuntimeFullRepairProjectionPayload(
                apps: [repairedApp],
                contextsByID: [:],
                appDirectoryEntries: []
            ),
            generatedAt: 30
        )

        XCTAssertEqual(summary.coldStartCommittedCount, 0)
        XCTAssertEqual(summary.degradedCommittedCount, 1)
        let appSwitcherProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appSwitcherProjection.apps.map(\.id), [repairedApp.id])
        XCTAssertEqual(appSwitcherProjection.apps.first?.windows.map(\.id), ["full-repair-rebuilt-window"])
        XCTAssertFalse(appSwitcherProjection.freshness.isCompleteForScope)
        let searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .staleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(searchRead.committedIndexCoversCurrentGeneration)
        let searchProjection = try XCTUnwrap(searchRead.projection)
        XCTAssertEqual(
            searchProjection.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            committedApp.windows.map(\.id)
        )
        XCTAssertFalse(
            searchProjection.windowEntries.contains { $0.windowID == "full-repair-rebuilt-window" }
        )
        let diagnostics = store.diagnostics()
        XCTAssertEqual(diagnostics.dirtyAppIDs, [repairedApp.id])
        XCTAssertEqual(diagnostics.dirtyPIDs, [pid])
        XCTAssertEqual(diagnostics.pendingRepairScopes, ["appWindows:\(repairedApp.id)"])
        XCTAssertTrue(diagnostics.hasStagingSearchIndex)
    }

    func testRuntimeReadModelStoreRemovesTerminatedAppFromCommittedProjectionsAndSearch() throws {
        let store = RuntimeReadModelStore()
        let apps = searchScenarioApps()
        let terminatedApp = try XCTUnwrap(apps.first)
        let remainingApps = Array(apps.dropFirst())
        let pid = NSRunningApplication.current.processIdentifier
        let terminatedDirectoryEntry = RuntimeAppDirectoryEntry(
            pid: pid,
            appID: terminatedApp.id,
            bundleIdentifier: "com.example.terminated",
            localizedName: terminatedApp.displayName,
            launchDate: nil
        )
        let remainingDirectoryEntry = RuntimeAppDirectoryEntry(
            pid: pid + 1,
            appID: remainingApps[0].id,
            bundleIdentifier: "com.example.remaining",
            localizedName: remainingApps[0].displayName,
            launchDate: nil
        )

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
            appDirectoryEntries: [terminatedDirectoryEntry, remainingDirectoryEntry],
            generatedAt: 10
        )

        store.markAppTerminated(appID: terminatedApp.id, pid: pid)

        let appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), remainingApps.map(\.id))
        XCTAssertNil(appProjection.contextsByID[terminatedApp.id])
        XCTAssertTrue(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 2)

        let searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .verifiedCurrentGenerationCommitted)
        XCTAssertFalse(searchRead.projection?.appEntries.contains { $0.appID == terminatedApp.id } ?? true)
        XCTAssertFalse(searchRead.projection?.windowEntries.contains { $0.appID == terminatedApp.id } ?? true)
        XCTAssertEqual(
            searchRead.projection?.appEntries.map(\.appID),
            remainingApps.map(\.id)
        )
        let appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries.map(\.appID), [remainingApps[0].id])
        XCTAssertEqual(appDirectoryProjection.entries.map(\.pid), [pid + 1])

        store.markAppTerminated(appID: terminatedApp.id, pid: pid)

        let duplicateSignalProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(duplicateSignalProjection.apps.map(\.id), remainingApps.map(\.id))
        XCTAssertEqual(duplicateSignalProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(duplicateSignalProjection.freshness.sourceGeneration.projection, 2)
        XCTAssertEqual(store.readAppDirectoryProjection()?.entries.map(\.pid), [pid + 1])
    }

    func testRuntimeReadModelStoreAppLaunchSignalUpsertsDirectoryEntryWithDirtyFreshness() throws {
        let store = RuntimeReadModelStore()
        let launchedEntry = RuntimeAppDirectoryEntry(
            pid: 73_001,
            appID: "com.example.launched",
            bundleIdentifier: "com.example.launched",
            localizedName: "Launched",
            launchDate: nil
        )

        store.markAppLifecycleDirty(
            appID: launchedEntry.appID,
            pid: launchedEntry.pid,
            pendingScope: "appLaunched:\(launchedEntry.appID)",
            appDirectoryEntry: launchedEntry,
            generatedAt: 52
        )

        let appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [launchedEntry])
        XCTAssertEqual(appDirectoryProjection.freshness.generatedAt, 52)
        XCTAssertFalse(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appDirectoryProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(appDirectoryProjection.freshness.dirtyAppIDs, [launchedEntry.appID])
        XCTAssertEqual(appDirectoryProjection.freshness.dirtyPIDs, [launchedEntry.pid])
        XCTAssertEqual(
            appDirectoryProjection.freshness.pendingRepairScopes,
            ["appLaunched:\(launchedEntry.appID)"]
        )
    }

    func testRuntimeReadModelStoreDoesNotSynthesizeAppDirectoryFromSwitcherContexts() throws {
        let store = RuntimeReadModelStore()
        let app = try XCTUnwrap(searchScenarioApps().first)
        let context = makeRuntimeAppContext(
            appID: app.id,
            runningApp: .current,
            windows: app.windows
        )

        store.commitAppSwitcherProjection(
            apps: [app],
            contextsByID: [app.id: context],
            appDirectoryEntries: nil,
            generatedAt: 64
        )

        XCTAssertNil(store.readAppDirectoryProjection())
        let appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), [app.id])
    }

    func testRuntimeFullRepairProjectionPayloadDoesNotInferAppDirectoryFromContexts() throws {
        let app = try XCTUnwrap(searchScenarioApps().first)
        let context = makeRuntimeAppContext(
            appID: app.id,
            runningApp: .current,
            windows: app.windows
        )

        let payload = RuntimeFullRepairProjectionPayload(
            apps: [app],
            contextsByID: [app.id: context],
            appDirectoryEntries: []
        )

        XCTAssertTrue(payload.appDirectoryEntries.isEmpty)
    }

    func testRuntimeAppDirectoryStateOwnsPIDKeyedReplacementAndProjectionDerivation() throws {
        var state = RuntimeAppDirectoryState()
        let firstEntry = RuntimeAppDirectoryEntry(
            pid: 100,
            appID: "com.example.mail",
            bundleIdentifier: "com.example.mail.stale",
            localizedName: "Stale Mail",
            launchDate: nil
        )
        let repairedEntry = RuntimeAppDirectoryEntry(
            pid: firstEntry.pid,
            appID: firstEntry.appID,
            bundleIdentifier: "com.example.mail",
            localizedName: "Mail",
            launchDate: nil
        )
        let secondEntry = RuntimeAppDirectoryEntry(
            pid: 101,
            appID: "com.example.notes",
            bundleIdentifier: "com.example.notes",
            localizedName: "Notes",
            launchDate: nil
        )

        XCTAssertNil(state.projection(freshness: appDirectoryStateFreshness))
        XCTAssertFalse(state.isInitialized)

        state.upsert(entries: [], generatedAt: 9)
        XCTAssertNil(state.projection(freshness: appDirectoryStateFreshness))

        state.replace(entries: [firstEntry, repairedEntry], generatedAt: 10)
        var projection = try XCTUnwrap(state.projection(freshness: appDirectoryStateFreshness))
        XCTAssertEqual(projection.entries, [repairedEntry])
        XCTAssertEqual(projection.freshness.generatedAt, 10)
        XCTAssertEqual(state.entryPIDs, [100])

        state.upsert(entries: [secondEntry], generatedAt: 11)
        projection = try XCTUnwrap(state.projection(freshness: appDirectoryStateFreshness))
        XCTAssertEqual(projection.entries.map(\.pid), [100, 101])
        XCTAssertEqual(projection.entries(forAppID: secondEntry.appID), [secondEntry])
        XCTAssertEqual(projection.freshness.generatedAt, 11)

        state.remove(pid: firstEntry.pid, generatedAt: 12)
        projection = try XCTUnwrap(state.projection(freshness: appDirectoryStateFreshness))
        XCTAssertEqual(projection.entries, [secondEntry])
        XCTAssertEqual(projection.freshness.generatedAt, 12)

        state.remove(appID: secondEntry.appID, pid: secondEntry.pid, generatedAt: 13)
        projection = try XCTUnwrap(state.projection(freshness: appDirectoryStateFreshness))
        XCTAssertTrue(projection.entries.isEmpty)
        XCTAssertEqual(projection.freshness.generatedAt, 13)
        XCTAssertTrue(state.isInitialized)
    }

    func testRuntimeReadModelStoreDerivesAppDirectoryProjectionFromPIDKeyedState() throws {
        let store = RuntimeReadModelStore()
        let apps = searchScenarioApps()
        let app = try XCTUnwrap(apps.first)
        let pid = NSRunningApplication.current.processIdentifier
        let staleEntry = RuntimeAppDirectoryEntry(
            pid: pid,
            appID: app.id,
            bundleIdentifier: "com.example.stale",
            localizedName: "Stale Mail",
            launchDate: nil
        )
        let repairedEntry = RuntimeAppDirectoryEntry(
            pid: pid,
            appID: app.id,
            bundleIdentifier: "com.example.repaired",
            localizedName: app.displayName,
            launchDate: nil
        )
        let launchedEntry = RuntimeAppDirectoryEntry(
            pid: pid + 1,
            appID: "com.example.launched",
            bundleIdentifier: "com.example.launched",
            localizedName: "Launched",
            launchDate: nil
        )

        XCTAssertNil(store.readAppDirectoryProjection())
        XCTAssertFalse(store.diagnostics().hasAppDirectoryProjection)

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [
                app.id: makeRuntimeAppContext(
                    appID: app.id,
                    runningApp: .current,
                    windows: app.windows
                )
            ],
            appDirectoryEntries: [staleEntry, repairedEntry],
            generatedAt: 10
        )

        var projection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(projection.entries, [repairedEntry])
        XCTAssertEqual(projection.freshness.generatedAt, 10)
        XCTAssertEqual(store.diagnostics().appDirectoryEntryPIDs, [pid])

        store.markAppLifecycleDirty(
            appID: launchedEntry.appID,
            pid: launchedEntry.pid,
            pendingScope: "appLaunched:\(launchedEntry.appID)",
            appDirectoryEntry: launchedEntry,
            generatedAt: 11
        )

        projection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(Set(projection.entries.map(\.pid)), [pid, pid + 1])
        XCTAssertEqual(projection.entries(forAppID: launchedEntry.appID), [launchedEntry])
        XCTAssertEqual(projection.freshness.generatedAt, 11)
        XCTAssertFalse(projection.freshness.isCompleteForScope)
        XCTAssertEqual(projection.freshness.dirtyAppIDs, [launchedEntry.appID])

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 12
        )

        projection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(Set(projection.entries.map(\.pid)), [pid, pid + 1])
        XCTAssertEqual(projection.freshness.generatedAt, 11)
        XCTAssertTrue(projection.freshness.isCompleteForScope)
    }

    func testRuntimeReadModelStorePreservesRunningInstanceWhenSameBundleDifferentPIDTerminates() throws {
        let store = RuntimeReadModelStore()
        let apps = terminateScenarioApps()
        let activeApp = try XCTUnwrap(apps.first)
        let activePID = NSRunningApplication.current.processIdentifier
        let secondaryPID = activePID + 1
        let context = makeRuntimeAppContext(
            appID: activeApp.id,
            runningApp: .current,
            windows: activeApp.windows
        )
        let activeDirectoryEntry = RuntimeAppDirectoryEntry(
            pid: activePID,
            appID: activeApp.id,
            bundleIdentifier: "com.example.mail",
            localizedName: activeApp.displayName,
            launchDate: nil
        )
        let secondaryDirectoryEntry = RuntimeAppDirectoryEntry(
            pid: secondaryPID,
            appID: activeApp.id,
            bundleIdentifier: activeDirectoryEntry.bundleIdentifier,
            localizedName: activeDirectoryEntry.localizedName,
            launchDate: nil
        )

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [activeApp.id: context],
            appDirectoryEntries: [activeDirectoryEntry, secondaryDirectoryEntry],
            generatedAt: 10
        )

        store.markAppTerminated(appID: activeApp.id, pid: secondaryPID)

        var appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), apps.map(\.id))
        XCTAssertEqual(
            appProjection.contextsByID[activeApp.id]?.runningApp.processIdentifier,
            activePID
        )
        XCTAssertEqual(store.readAppDirectoryProjection()?.entries.map(\.pid), [activePID])
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.dirtyAppIDs, [activeApp.id])
        XCTAssertEqual(appProjection.freshness.pendingRepairScopes, ["appTerminated:\(activeApp.id)"])
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 2)
        var searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .staleCommitted)
        XCTAssertTrue(searchRead.projection?.appEntries.contains { $0.appID == activeApp.id } ?? false)

        store.markAppTerminated(appID: activeApp.id, pid: secondaryPID)

        appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 2)
        XCTAssertEqual(store.readAppDirectoryProjection()?.entries.map(\.pid), [activePID])

        store.markAppTerminated(appID: activeApp.id, pid: activePID)

        appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertFalse(appProjection.apps.contains { $0.id == activeApp.id })
        XCTAssertNil(appProjection.contextsByID[activeApp.id])
        XCTAssertTrue(store.readAppDirectoryProjection()?.entries.isEmpty == true)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 2)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 3)
        searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertFalse(searchRead.projection?.appEntries.contains { $0.appID == activeApp.id } ?? true)
    }

    func testRuntimeProjectionServicePrunesTerminatedPIDButKeepsSameAppDirectoryInstance() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let app = try XCTUnwrap(terminateScenarioApps().first)
        let activePID = NSRunningApplication.current.processIdentifier
        let terminatedPID = activePID + 1
        let activeEntry = RuntimeAppDirectoryEntry(
            pid: activePID,
            appID: app.id,
            bundleIdentifier: "com.example.mail",
            localizedName: app.displayName,
            launchDate: nil
        )
        let terminatedEntry = RuntimeAppDirectoryEntry(
            pid: terminatedPID,
            appID: app.id,
            bundleIdentifier: activeEntry.bundleIdentifier,
            localizedName: activeEntry.localizedName,
            launchDate: nil
        )
        store.commitAppSwitcherProjection(
            apps: [app],
            contextsByID: [
                app.id: makeRuntimeAppContext(
                    appID: app.id,
                    runningApp: .current,
                    windows: app.windows
                )
            ],
            appDirectoryEntries: [activeEntry, terminatedEntry],
            generatedAt: 10
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.PartialAppTermination",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store
        )

        service.signalAppTerminated(appID: app.id, pid: terminatedPID)
        service.waitForMaintenanceQueueForTesting()

        let appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), [app.id])
        XCTAssertFalse(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(store.readAppDirectoryProjection()?.entries.map(\.pid), [activePID])
        let searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .staleCommitted)
        XCTAssertTrue(searchRead.projection?.appEntries.contains { $0.appID == app.id } ?? false)
    }

    func testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals() {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let seededApp = AppSwitchCandidate(
            id: "com.example.seeded",
            displayName: "Seeded",
            groupID: "seeded",
            lastActiveAt: 100,
            windows: []
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.commitAppSwitcherProjection(
            apps: [seededApp],
            contextsByID: [:],
            appDirectoryEntries: nil,
            clearsDirtyState: false,
            generatedAt: 1
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.ReadModelStore",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: readModelStore,
            reconciliationExecutor: { _, _ in .completed }
        )

        let appProjection = service.readAppSwitcherProjection()

        XCTAssertEqual(appProjection?.apps.map(\.id), [seededApp.id])
        XCTAssertTrue(service.runtimeReadModelDiagnostics().hasAppSwitcherProjection)

        service.signalAppWindowsChanged(appID: "com.example.editor", pid: 18_405)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10)

        let diagnostics = service.runtimeReadModelDiagnostics()
        XCTAssertEqual(diagnostics.dirtyAppIDs, ["com.example.editor"])
        XCTAssertEqual(diagnostics.dirtyPIDs, [18_405])
        XCTAssertEqual(diagnostics.generation.axDirty, 1)
        XCTAssertEqual(
            service.readAppSwitcherProjection()?.freshness.pendingRepairScopes,
            ["appWindows:com.example.editor"]
        )
        XCTAssertFalse(service.readAppSwitcherProjection()?.freshness.isCompleteForScope ?? true)
    }

    func testRuntimeReadModelStoreKeepsStagingSearchIndexHiddenWithoutBarrierPayload() throws {
        let store = RuntimeReadModelStore()
        let apps = searchScenarioApps()
        let stagedApp = try XCTUnwrap(apps.first)
        let pid = pid_t(42_099)

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: stagedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(stagedApp.id)"
        )
        store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: stagedApp, pid: pid)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )

        var read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(read.committedIndexCoversCurrentGeneration)
        XCTAssertNotNil(read.projection)
        var diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.hasCommittedSearchIndex)
        XCTAssertTrue(diagnostics.hasStagingSearchIndex)

        let commitResult = store.commitSearchFreshnessBarrierPayloads(
            [],
            deferredRequestCount: 0,
            hasPendingRequests: false,
            generatedAt: 21
        )

        XCTAssertFalse(commitResult.stagedNewPayload)
        XCTAssertFalse(commitResult.committedNewGeneration)
        read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertNotNil(read.projection)
        diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.hasCommittedSearchIndex)
        XCTAssertTrue(diagnostics.hasStagingSearchIndex)
    }

    func testRuntimeReadModelStoreSearchReadinessTracksDirtyMetadataWithoutReadingStaging() throws {
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let stagedApps = [
            AppSwitchCandidate(
                id: "com.example.staging-only",
                displayName: "Staging Only",
                groupID: "staging",
                lastActiveAt: 99,
                windows: [
                    WindowCandidate(
                        id: "staging-window",
                        title: "Staging Window",
                        isMinimized: false,
                        lastActiveAt: 99
                    )
                ]
            )
        ]
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )

        var read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .verifiedCurrentGenerationCommitted)
        XCTAssertEqual(read.resultState, .verifiedCurrentGenerationCommittedResult)
        XCTAssertTrue(read.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(read.projection?.appEntries.map(\.appID), committedApps.map(\.id))

        store.markAppWindowsDirty(
            appID: "com.example.browser",
            pid: 42_100,
            pendingScope: "appWindows:com.example.browser"
        )
        store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: stagedApps[0], pid: 42_100)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )

        read = store.readCommittedSearchIndexForSearch()
        let staleProjection = try XCTUnwrap(read.projection)
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(read.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(staleProjection.appEntries.map(\.appID), committedApps.map(\.id))
        XCTAssertFalse(staleProjection.appEntries.map(\.appID).contains("com.example.staging-only"))
        XCTAssertEqual(staleProjection.freshness.dirtyAppIDs, ["com.example.browser"])
        XCTAssertEqual(staleProjection.freshness.dirtyPIDs, [42_100])
        XCTAssertEqual(staleProjection.freshness.pendingRepairScopes, ["appWindows:com.example.browser"])
    }

    func testRuntimeReadModelStoreStagesScopedSearchRepairAndCommitsNewCommittedGeneration() throws {
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 320,
            windows: [
                WindowCandidate(
                    id: "browser-2",
                    title: "Fresh Docs",
                    isMinimized: false,
                    lastActiveAt: 320
                )
            ]
        )
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        let pid = pid_t(42_101)
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )

        let stagedResult = store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )
        let staged = try XCTUnwrap(stagedResult.stagedSearchIndex)
        XCTAssertEqual(staged.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID), ["browser-2"])
        var read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(read.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(
            read.projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )

        let commitResult = store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)],
            deferredRequestCount: 0,
            hasPendingRequests: false,
            generatedAt: 21
        )

        let committed = try XCTUnwrap(commitResult.committedSearchIndex)
        XCTAssertTrue(committed.freshness.isCompleteForScope)
        read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .verifiedCurrentGenerationCommitted)
        XCTAssertEqual(read.resultState, .verifiedCurrentGenerationCommittedResult)
        XCTAssertTrue(read.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(
            read.projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-2"]
        )
        let diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.dirtyAppIDs.isEmpty)
        XCTAssertFalse(diagnostics.hasStagingSearchIndex)
    }

    func testRuntimeReadModelStoreStagesSearchRepairFromCurrentAppProjectionPayload() throws {
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 330,
            windows: [
                WindowCandidate(
                    id: "browser-payload",
                    title: "Payload Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 330
                )
            ]
        )
        let pid = pid_t(42_103)
        let payload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: repairedApp.id,
                displayName: repairedApp.displayName,
                groupID: repairedApp.groupID,
                lastActiveAt: repairedApp.lastActiveAt,
                windowCount: repairedApp.windows.count,
                pid: pid
            ),
            candidate: repairedApp,
            context: makeRuntimeAppContext(
                appID: repairedApp.id,
                runningApp: .current,
                windows: repairedApp.windows
            ),
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: .current)]
        )
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )

        let stagedResult = store.commitSearchFreshnessBarrierPayloads(
            [payload],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )
        let staged = try XCTUnwrap(stagedResult.stagedSearchIndex)

        XCTAssertEqual(staged.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID), ["browser-payload"])
        XCTAssertEqual(store.readCommittedSearchIndexForSearch().readiness, .staleCommitted)
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )

        let commitResult = store.commitSearchFreshnessBarrierPayloads(
            [payload],
            deferredRequestCount: 0,
            hasPendingRequests: false,
            generatedAt: 21
        )

        let committed = try XCTUnwrap(commitResult.committedSearchIndex)
        XCTAssertTrue(committed.freshness.isCompleteForScope)
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-payload"]
        )
    }

    func testRuntimeReadModelStoreCommitsSearchFreshnessBarrierOnlyWithCurrentPayloadAndNoOutstandingRepair() throws {
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 340,
            windows: [
                WindowCandidate(
                    id: "browser-barrier-fresh",
                    title: "Barrier Fresh Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 340
                )
            ]
        )
        let staleStagingApp = AppSwitchCandidate(
            id: repairedApp.id,
            displayName: repairedApp.displayName,
            groupID: repairedApp.groupID,
            lastActiveAt: 330,
            windows: [
                WindowCandidate(
                    id: "browser-stale-staging",
                    title: "Stale Staging Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 330
                )
            ]
        )
        let pid = pid_t(42_108)
        let payload = makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: staleStagingApp, pid: pid)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )

        var result = store.commitSearchFreshnessBarrierPayloads(
            [],
            deferredRequestCount: 0,
            hasPendingRequests: false,
            generatedAt: 21
        )

        XCTAssertFalse(result.stagedNewPayload)
        XCTAssertFalse(result.committedNewGeneration)
        var read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            read.projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )
        XCTAssertTrue(store.diagnostics().hasStagingSearchIndex)

        result = store.commitSearchFreshnessBarrierPayloads(
            [payload],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 22
        )

        XCTAssertTrue(result.stagedNewPayload)
        XCTAssertFalse(result.committedNewGeneration)
        read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            read.projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )
        XCTAssertTrue(store.diagnostics().hasStagingSearchIndex)

        result = store.commitSearchFreshnessBarrierPayloads(
            [payload],
            deferredRequestCount: 0,
            hasPendingRequests: true,
            generatedAt: 23
        )

        XCTAssertTrue(result.stagedNewPayload)
        XCTAssertFalse(result.committedNewGeneration)
        XCTAssertEqual(store.readCommittedSearchIndexForSearch().readiness, .staleCommitted)
        XCTAssertTrue(store.diagnostics().hasStagingSearchIndex)

        result = store.commitSearchFreshnessBarrierPayloads(
            [payload],
            deferredRequestCount: 0,
            hasPendingRequests: false,
            generatedAt: 24
        )

        XCTAssertTrue(result.stagedNewPayload)
        XCTAssertTrue(result.committedNewGeneration)
        read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .verifiedCurrentGenerationCommitted)
        XCTAssertEqual(read.resultState, .verifiedCurrentGenerationCommittedResult)
        XCTAssertEqual(
            read.projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-barrier-fresh"]
        )
        let diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.dirtyAppIDs.isEmpty)
        XCTAssertFalse(diagnostics.hasStagingSearchIndex)
    }

    func testRuntimeReadModelStoreTreatsUncommittedSearchStagingAsDegradedWhenDirtyClears() throws {
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 320,
            windows: [
                WindowCandidate(
                    id: "browser-staged-not-committed",
                    title: "Staged Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 320
                )
            ]
        )
        let pid = pid_t(42_109)
        let payload = makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        store.commitCurrentAppWindowProjection(payload, generatedAt: 20)

        let result = store.commitSearchFreshnessBarrierPayloads(
            [payload],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 21
        )

        XCTAssertTrue(result.stagedNewPayload)
        XCTAssertFalse(result.committedNewGeneration)
        let read = store.readCommittedSearchIndexForSearch()
        let projection = try XCTUnwrap(read.projection)
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(read.committedIndexCoversCurrentGeneration)
        XCTAssertFalse(read.freshness?.isCompleteForScope ?? true)
        XCTAssertEqual(
            projection.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )
        let diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.dirtyAppIDs.isEmpty)
        XCTAssertTrue(diagnostics.pendingRepairScopes.isEmpty)
        XCTAssertTrue(diagnostics.hasStagingSearchIndex)
    }

    func testRuntimeReconciliationCoordinatorMarksSpaceTopologyAffectedWindows() {
        let coordinator = RuntimeReconciliationCoordinator()
        let previous = RuntimeSpaceTopologySnapshot(
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001])
            ]
        )
        let current = RuntimeSpaceTopologySnapshot(
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true),
                11: RuntimeSpaceTopologySpace(id: 11, displayID: 1, isCurrent: false)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001, 240_002]),
                11: Set<CGWindowID>([240_003])
            ]
        )

        _ = coordinator.applySpaceTopologySnapshot(previous, now: 1)
        let diff = coordinator.applySpaceTopologySnapshot(current, now: 2)
        let request = coordinator.readyRequests(now: 2).first

        XCTAssertEqual(diff.changedSpaceIDs, Set([10, 11]))
        XCTAssertEqual(diff.affectedCGWindowIDs, Set<CGWindowID>([240_001, 240_002, 240_003]))
        XCTAssertTrue(diff.hasSignatureChange)
        XCTAssertEqual(diff.previousSignature, previous.signature)
        XCTAssertEqual(diff.currentSignature, current.signature)
        XCTAssertEqual(request?.target, .spaceTopology)
        XCTAssertEqual(request?.reasons, Set([.spaceTopologyChanged]))
        XCTAssertEqual(request?.affectedCGWindowIDs, Set<CGWindowID>([240_001, 240_002, 240_003]))
        XCTAssertEqual(request?.state, .pending)
    }

    func testRuntimeReconciliationCoordinatorCoalescesDirtyAppAndRetriesTransientEmptyCurrentAppWindowPayloads() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [0.1, 0.3])
        )

        let initial = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .axNotification,
            now: 10
        )
        let coalesced = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .manualRefresh,
            now: 10.05
        )
        let started = try XCTUnwrap(coordinator.startRequest(id: coalesced.id))
        let retry = try XCTUnwrap(
            coordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(
                id: started.id,
                now: 11
            )
        )

        XCTAssertEqual(initial.id, coalesced.id)
        XCTAssertEqual(started.state, .inFlight)
        XCTAssertEqual(retry.reasons, Set([.axNotification, .manualRefresh]))
        XCTAssertEqual(retry.priority, .normal)
        XCTAssertEqual(retry.state, .waitingRetry)
        XCTAssertEqual(retry.attempt, 1)
        XCTAssertEqual(retry.notBefore, 11.1, accuracy: 0.0001)
        XCTAssertTrue(coordinator.readyRequests(now: 11.09).isEmpty)
        XCTAssertEqual(coordinator.readyRequests(now: 11.1).map(\.id), [retry.id])

        coordinator.completeRequest(id: retry.id)
        XCTAssertTrue(coordinator.readyRequests(now: 12).isEmpty)
    }

    func testRuntimeReconciliationCoordinatorSchedulesFullRepairFallbackWhenRetryPolicyExhausts() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [])
        )
        let dirty = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .axNotification,
            now: 10
        )
        let started = try XCTUnwrap(coordinator.startRequest(id: dirty.id))

        let retry = coordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(
            id: started.id,
            now: 11
        )

        XCTAssertNil(retry)
        let readyRequests = coordinator.readyRequests(now: 11)
        XCTAssertEqual(readyRequests.map(\.target), [.fullRepair])
        XCTAssertEqual(readyRequests.first?.reasons, Set([.fullRepairFallback]))
        XCTAssertEqual(readyRequests.first?.priority, .low)
        XCTAssertFalse(readyRequests.contains { $0.id == dirty.id })
    }

    func testRuntimeReconciliationCoordinatorPromotesPriorityAndBypassesRetryBackoff() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [5])
        )
        let pid = pid_t(18_405)
        let dirty = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: pid,
            reason: .manualRefresh,
            now: 10
        )
        let started = try XCTUnwrap(coordinator.startRequest(id: dirty.id))
        let retry = try XCTUnwrap(
            coordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(
                id: started.id,
                now: 10.5
            )
        )

        XCTAssertEqual(retry.priority, .low)
        XCTAssertTrue(coordinator.readyRequests(now: 11).isEmpty)

        let promoted = coordinator.markWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: "com.example.editor",
                windowID: "cg:18405:240001",
                ownerPID: pid,
                targetCGWindowID: 240_001,
                focusedCGWindowID: 240_002,
                focusedAXWindow: nil,
                title: "Verified Window",
                frame: CGRect(x: 10, y: 20, width: 800, height: 600),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            ),
            now: 11
        )

        XCTAssertEqual(promoted.id, dirty.id)
        XCTAssertEqual(promoted.priority, .high)
        XCTAssertEqual(promoted.state, .pending)
        XCTAssertEqual(promoted.attempt, 0)
        XCTAssertEqual(promoted.notBefore, 11, accuracy: 0.0001)
        XCTAssertEqual(promoted.reasons, Set([.manualRefresh, .activationVerified]))
        XCTAssertEqual(promoted.affectedCGWindowIDs, Set<CGWindowID>([240_001, 240_002]))
        XCTAssertEqual(coordinator.readyRequests(now: 11).map(\.id), [dirty.id])
    }

    func testRuntimeReconciliationCoordinatorCancelsPendingFullRepairForHighPriorityScopedRepair() {
        let coordinator = RuntimeReconciliationCoordinator()
        let fullRepair = coordinator.scheduleFullRepairFallback(now: 10)

        let scopedRepair = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .selectedCurrentAppWindows,
            now: 10.1
        )

        let readyRequests = coordinator.readyRequests(now: 10.1)
        XCTAssertEqual(fullRepair.target, .fullRepair)
        XCTAssertEqual(fullRepair.reasons, Set([.fullRepairFallback]))
        XCTAssertEqual(fullRepair.priority, .low)
        XCTAssertEqual(readyRequests.map(\.id), [scopedRepair.id])
        XCTAssertEqual(readyRequests.map(\.target), [.app(18_405)])
        XCTAssertFalse(readyRequests.contains { $0.id == fullRepair.id })
    }

    func testRuntimeReconciliationCoordinatorMarksVerifiedFocusReadbackAffectedWindows() throws {
        let coordinator = RuntimeReconciliationCoordinator()

        let request = coordinator.markWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: "com.example.editor",
                windowID: "cg:18405:240001",
                ownerPID: 18_405,
                targetCGWindowID: 240_001,
                focusedCGWindowID: 240_002,
                focusedAXWindow: nil,
                title: "Requested Window",
                frame: CGRect(x: 10, y: 20, width: 800, height: 600),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            ),
            now: 10
        )

        XCTAssertEqual(request.target, .app(18_405))
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.reasons, Set([.activationVerified]))
        XCTAssertEqual(request.priority, .high)
        XCTAssertEqual(request.affectedCGWindowIDs, Set<CGWindowID>([240_001, 240_002]))
        XCTAssertEqual(coordinator.readyRequests(now: 10).map(\.id), [request.id])
    }

    func testRuntimeReconciliationCoordinatorCancelsTerminatedAppRequestsWithoutDroppingOtherTargets() {
        let coordinator = RuntimeReconciliationCoordinator()
        let terminatedPID = pid_t(18_405)
        let otherPID = pid_t(18_406)

        let terminatedRequest = coordinator.markAppDirty(
            appID: "com.example.terminated",
            pid: terminatedPID,
            reason: .axNotification,
            now: 10
        )
        let otherRequest = coordinator.markAppDirty(
            appID: "com.example.other",
            pid: otherPID,
            reason: .manualRefresh,
            now: 10
        )
        let previousTopology = RuntimeSpaceTopologySnapshot(
            spacesByID: [
                7: RuntimeSpaceTopologySpace(id: 7, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                7: Set<CGWindowID>([240_001])
            ]
        )
        let currentTopology = RuntimeSpaceTopologySnapshot(
            spacesByID: [
                7: RuntimeSpaceTopologySpace(id: 7, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                7: Set<CGWindowID>([240_001, 240_002])
            ]
        )
        _ = coordinator.applySpaceTopologySnapshot(previousTopology, now: 10)
        _ = coordinator.applySpaceTopologySnapshot(currentTopology, now: 10)

        coordinator.cancelAppRequests(pid: terminatedPID)

        let remainingRequests = coordinator.readyRequests(now: 10)
        XCTAssertFalse(remainingRequests.contains { $0.id == terminatedRequest.id })
        XCTAssertTrue(remainingRequests.contains { $0.id == otherRequest.id })
        XCTAssertTrue(remainingRequests.contains { $0.target == .spaceTopology })
    }

    func testRuntimeSnapshotProviderRecordsSpaceTopologyThroughCoordinator() {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let previous = RuntimeSpaceTopologySnapshot(
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001])
            ]
        )
        let current = RuntimeSpaceTopologySnapshot(
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true),
                11: RuntimeSpaceTopologySpace(id: 11, displayID: 1, isCurrent: false)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_002]),
                11: Set<CGWindowID>([240_003])
            ]
        )

        _ = provider.recordSpaceTopologySnapshot(previous, now: 1)
        let diff = provider.recordSpaceTopologySnapshot(current, now: 2)
        let request = coordinator.readyRequests(now: 2).first

        XCTAssertEqual(diff.affectedCGWindowIDs, Set<CGWindowID>([240_001, 240_002, 240_003]))
        XCTAssertEqual(request?.target, .spaceTopology)
        XCTAssertEqual(request?.affectedCGWindowIDs, Set<CGWindowID>([240_001, 240_002, 240_003]))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: diff.signatureLogFields)["signature"],
            "d=1,current=10,spaces=2,windows=2,fullscreen=0"
        )
    }

    func testRuntimeSnapshotProviderMarksAffectedWindowRecordsForSpaceTopologyReconciliation() {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let pid = pid_t(18_405)
        let removedSpaceWindowID = CGWindowID(240_001)
        let addedSpaceWindowID = CGWindowID(240_002)
        let unaffectedWindowID = CGWindowID(240_003)
        let previous = RuntimeSpaceTopologySnapshot(
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                10: [removedSpaceWindowID]
            ]
        )
        let current = RuntimeSpaceTopologySnapshot(
            spacesByID: [
                11: RuntimeSpaceTopologySpace(id: 11, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                11: [addedSpaceWindowID]
            ]
        )
        var removedSpaceRecord = RuntimeWindowRecord(
            cgWindowID: removedSpaceWindowID,
            stableWindowID: "cg:\(pid):\(removedSpaceWindowID)",
            firstSeenAt: 1
        )
        removedSpaceRecord.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: removedSpaceWindowID,
            spaceIDs: [10],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: 1,
            invalidatedAt: nil
        )
        var addedSpaceRecord = RuntimeWindowRecord(
            cgWindowID: addedSpaceWindowID,
            stableWindowID: "cg:\(pid):\(addedSpaceWindowID)",
            firstSeenAt: 1
        )
        addedSpaceRecord.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: addedSpaceWindowID,
            spaceIDs: [11],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: 1,
            invalidatedAt: nil
        )
        let unaffectedRecord = RuntimeWindowRecord(
            cgWindowID: unaffectedWindowID,
            stableWindowID: "cg:\(pid):\(unaffectedWindowID)",
            firstSeenAt: 1
        )

        _ = provider.recordSpaceTopologySnapshot(previous, now: 1)
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [
                removedSpaceWindowID: removedSpaceRecord,
                addedSpaceWindowID: addedSpaceRecord,
                unaffectedWindowID: unaffectedRecord
            ]
        )
        let diff = provider.recordSpaceTopologySnapshot(current, now: 2)
        let records = provider.windowMappingStateByPID[pid]?.windowRecordsByCGWindowID

        XCTAssertEqual(diff.removedSpaceIDs, [10])
        XCTAssertEqual(diff.addedSpaceIDs, [11])
        XCTAssertEqual(diff.affectedCGWindowIDs, [removedSpaceWindowID, addedSpaceWindowID])
        XCTAssertTrue(records?[removedSpaceWindowID]?.needsReconciliation == true)
        XCTAssertEqual(records?[removedSpaceWindowID]?.lastReconciliationMarkedAt, 2)
        XCTAssertEqual(records?[removedSpaceWindowID]?.spaceRecovery?.invalidatedAt, 2)
        XCTAssertTrue(records?[addedSpaceWindowID]?.needsReconciliation == true)
        XCTAssertEqual(records?[addedSpaceWindowID]?.lastReconciliationMarkedAt, 2)
        XCTAssertNil(records?[addedSpaceWindowID]?.spaceRecovery?.invalidatedAt)
        XCTAssertFalse(records?[unaffectedWindowID]?.needsReconciliation == true)
    }

    func testRuntimeProjectionServiceDrainsSpaceTopologySignalThroughCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let affectedWindowID = CGWindowID(240_001)
        let provider = RuntimeSnapshotProvider(
            cgWindowListProvider: FixedRuntimeCGWindowListProvider(
                rawWindowInfo: [
                    makeRawCGWindowInfo(
                        pid: 18_405,
                        windowID: affectedWindowID,
                        title: "Topology Target"
                    )
                ]
            ),
            spaceTopologyProvider: FixedRuntimeSpaceTopologyProvider(
                snapshot: RuntimeSpaceTopologySnapshot(
                    spacesByID: [
                        7: RuntimeSpaceTopologySpace(id: 7, displayID: 1, isCurrent: true)
                    ],
                    windowIDsBySpaceID: [
                        7: [affectedWindowID]
                    ],
                    spaceIDsByCGWindowID: [
                        affectedWindowID: [7]
                    ]
                )
            ),
            reconciliationCoordinator: coordinator
        )
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let readModelStore = RuntimeReadModelStore()
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SpaceTopologySignal",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalSpaceTopologyChanged()
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.target, .spaceTopology)
        XCTAssertEqual(request.reasons, Set([.spaceTopologyChanged]))
        XCTAssertEqual(request.affectedCGWindowIDs, [affectedWindowID])
        XCTAssertEqual(request.state, .inFlight)
        let diagnostics = readModelStore.diagnostics()
        XCTAssertEqual(diagnostics.dirtyCGWindowIDs, [affectedWindowID])
        XCTAssertEqual(diagnostics.generation.space, 1)
        XCTAssertEqual(diagnostics.pendingRepairScopes, ["spaceTopology"])
        XCTAssertTrue(coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).isEmpty)
    }

    func testRuntimeProjectionRepairProviderReconcilesSpaceTopologyThroughAffectedTargets() {
        let recordedPID = pid_t(1_840_501_409)
        let currentPID = pid_t(1_840_501_410)
        let recordedWindowID = CGWindowID(240_001)
        let currentWindowID = CGWindowID(240_002)
        let staleWindowID = CGWindowID(240_003)
        let provider = RuntimeSnapshotProvider(
            cgWindowListProvider: FixedRuntimeCGWindowListProvider(
                rawWindowInfo: [
                    makeRawCGWindowInfo(
                        pid: currentPID,
                        windowID: currentWindowID,
                        title: "Current Topology Window"
                    )
                ]
            )
        )
        let repairProvider = RuntimeProjectionRepairProvider(runtimeFactProvider: provider)
        provider.windowMappingStateByPID[recordedPID] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [
                recordedWindowID: RuntimeWindowRecord(
                    cgWindowID: recordedWindowID,
                    stableWindowID: "cg:\(recordedPID):\(recordedWindowID)",
                    firstSeenAt: 1
                )
            ]
        )

        let results = repairProvider.reconcileSpaceTopology(
            affectedCGWindowIDs: [recordedWindowID, currentWindowID, staleWindowID]
        )

        XCTAssertEqual(results.map(\.pid), [recordedPID, currentPID])
        XCTAssertEqual(results.map(\.affectedCGWindowIDs), [[recordedWindowID], [currentWindowID]])
    }

    func testRuntimeProjectionRepairProviderReconcilesAppWindowsWithAffectedCGWindowScope() {
        let provider = RuntimeSnapshotProvider()
        let repairProvider = RuntimeProjectionRepairProvider(runtimeFactProvider: provider)
        let currentPID = NSRunningApplication.current.processIdentifier
        let affectedCGWindowIDs: Set<CGWindowID> = [240_001, 240_002]

        let result = repairProvider.reconcileAppWindows(
            processIdentifier: currentPID,
            affectedCGWindowIDs: affectedCGWindowIDs
        )

        XCTAssertEqual(result.pid, currentPID)
        XCTAssertEqual(result.affectedCGWindowIDs, affectedCGWindowIDs)
    }

    func testRuntimeProjectionRepairProviderReconciliationResultReportsAffectedWindowRecordEvidence() {
        let provider = RuntimeSnapshotProvider()
        let repairProvider = RuntimeProjectionRepairProvider(runtimeFactProvider: provider)
        let pid = pid_t(1_840_501_407)
        let exactWindowID = CGWindowID(240_001)
        let provisionalWindowID = CGWindowID(240_002)
        let missingWindowID = CGWindowID(240_003)
        var exactRecord = RuntimeWindowRecord(
            cgWindowID: exactWindowID,
            stableWindowID: "cg:\(pid):\(exactWindowID)",
            firstSeenAt: 10
        )
        exactRecord.lastConfirmationSource = .publicExactMatch
        let provisionalRecord = RuntimeWindowRecord(
            cgWindowID: provisionalWindowID,
            stableWindowID: "cg:\(pid):\(provisionalWindowID)",
            firstSeenAt: 10
        )
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [
                exactWindowID: exactRecord,
                provisionalWindowID: provisionalRecord
            ]
        )

        let result = repairProvider.reconcileAppWindows(
            processIdentifier: pid,
            affectedCGWindowIDs: [exactWindowID, provisionalWindowID, missingWindowID]
        )

        XCTAssertEqual(result.pid, pid)
        XCTAssertEqual(result.affectedCGWindowIDs, [exactWindowID, provisionalWindowID, missingWindowID])
        XCTAssertEqual(result.knownAffectedCGWindowIDs, [exactWindowID, provisionalWindowID])
        XCTAssertEqual(result.exactAffectedCGWindowIDs, [exactWindowID])
    }

    func testRuntimeProjectionServiceDrainsAppWindowChangesThroughCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppWindowSignal",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalAppWindowsChanged(appID: "com.example.editor", pid: 18_405)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.reasons, Set([.axNotification]))
        XCTAssertEqual(request.state, .inFlight)
        XCTAssertTrue(coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).isEmpty)
    }

    func testRuntimeProjectionServiceDrainsSelectedCurrentAppWindowChangesAtHighPriority() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SelectedCurrentAppWindowSignal",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalSelectedCurrentAppWindowsChanged(appID: "com.example.editor", pid: 18_405)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.reasons, Set([.selectedCurrentAppWindows]))
        XCTAssertEqual(request.priority, .high)
        XCTAssertEqual(request.state, .inFlight)
        XCTAssertTrue(coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).isEmpty)
    }

    func testRuntimeProjectionServiceSignalsDestroyedAXWindowThroughCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let pid = pid_t(18_405)
        let axWindowID = "ax:18405:0"
        let cgWindowID = CGWindowID(240_001)
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindowID,
            stableWindowID: "cg:\(pid):\(cgWindowID)",
            firstSeenAt: 10
        )
        record.currentAXAttachment = RuntimeCurrentAXAttachment(
            axWindowID: axWindowID,
            axWindow: AXUIElementCreateApplication(pid),
            title: "Destroyed Window",
            frame: CGRect(x: 10, y: 20, width: 800, height: 600),
            state: RuntimeAXWindowState(isMinimized: false, isFocused: true, isMain: true)
        )
        record.lastExactAXWindowID = axWindowID
        record.lastConfirmationSource = .publicExactMatch
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [cgWindowID: record],
            currentAXToCG: [axWindowID: cgWindowID],
            validCGWindowIDs: [cgWindowID],
            lastAXWindowIDs: [axWindowID]
        )
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AXDestroyed",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalAXWindowDestroyed(
            appID: "com.example.editor",
            pid: pid,
            axWindowID: axWindowID
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        let downgradedRecord = provider.windowMappingStateByPID[pid]?
            .windowRecordsByCGWindowID[cgWindowID]
        XCTAssertEqual(request.target, .app(pid))
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.reasons, [.axNotification])
        XCTAssertEqual(request.affectedCGWindowIDs, [cgWindowID])
        XCTAssertNil(downgradedRecord?.currentAXAttachment)
        XCTAssertNil(downgradedRecord?.lastConfirmationSource)
        XCTAssertEqual(downgradedRecord?.bindingConfidence, .sticky)
        XCTAssertTrue(downgradedRecord?.needsReconciliation == true)
    }

    func testRuntimeProjectionServiceDrainsLaunchedAppThroughCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let launchedEntry = RuntimeAppDirectoryEntry(
            pid: 18_407,
            appID: "com.example.new",
            bundleIdentifier: "com.example.new",
            localizedName: "New",
            launchDate: nil
        )
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppLaunchSignal",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalAppLaunched(
            appID: "com.example.new",
            pid: 18_407,
            appDirectoryEntry: launchedEntry
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.target, .app(18_407))
        XCTAssertEqual(request.appID, "com.example.new")
        XCTAssertEqual(request.reasons, Set([.appLaunched]))
        XCTAssertEqual(request.state, .inFlight)
        let appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, [launchedEntry])
        XCTAssertFalse(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertTrue(coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).isEmpty)
    }

    func testRuntimeProjectionServiceCommitsLaunchedAppRepairIntoAppSwitcherProjection() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let existingApp = AppSwitchCandidate(
            id: "com.example.existing",
            displayName: "Existing",
            groupID: "example",
            lastActiveAt: 100,
            windows: []
        )
        let repairedApp = AppSwitchCandidate(
            id: "com.example.new",
            displayName: "New",
            groupID: "example",
            lastActiveAt: 300,
            windows: [
                WindowCandidate(
                    id: "new-window",
                    title: "New Window",
                    isMinimized: false,
                    lastActiveAt: 300
                )
            ]
        )
        let pid = pid_t(18_407)
        store.commitAppSwitcherProjection(
            apps: [existingApp],
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppLaunchRepairCommit",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { _, _ in
                .completedWithRepairedCurrentAppWindowPayloads([
                    self.makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)
                ])
            }
        )

        service.signalAppLaunched(appID: repairedApp.id, pid: pid)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 11)

        let projection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(projection.apps.map(\.id), [repairedApp.id, existingApp.id])
        XCTAssertEqual(
            projection.apps.first(where: { $0.id == repairedApp.id })?.windows.map(\.id),
            ["new-window"]
        )
        XCTAssertNotNil(projection.contextsByID[repairedApp.id])
        XCTAssertTrue(projection.freshness.isCompleteForScope)
        let homeProjection = try XCTUnwrap(store.readHomeSummaryProjection())
        XCTAssertEqual(homeProjection.summaries.map(\.appID), [repairedApp.id, existingApp.id])
        XCTAssertEqual(homeProjection.summary(for: repairedApp.id)?.windowCount, 1)
        XCTAssertTrue(homeProjection.freshness.isCompleteForScope)
    }

    func testRuntimeProjectionServiceClearsTerminatedAppRuntimeState() {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let pid = pid_t(18_405)
        let cgWindowID = CGWindowID(240_001)
        let liveAXWindow = AXUIElementCreateApplication(pid)
        AXLiveWindowRegistry.shared.refreshSnapshot(forPID: pid, windows: [liveAXWindow])
        defer { AXLiveWindowRegistry.shared.remove(pid: pid) }
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [
                cgWindowID: RuntimeWindowRecord(
                    cgWindowID: cgWindowID,
                    stableWindowID: "cg:\(pid):\(cgWindowID)",
                    firstSeenAt: 10
                )
            ]
        )
        let request = coordinator.markAppDirty(
            appID: "com.example.terminated",
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppTerminated",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider)
        )

        XCTAssertFalse(AXLiveWindowRegistry.shared.windows(forPID: pid).isEmpty)
        service.signalAppTerminated(appID: "com.example.terminated", pid: pid)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 11)

        XCTAssertNil(provider.windowMappingStateByPID[pid])
        XCTAssertTrue(AXLiveWindowRegistry.shared.windows(forPID: pid).isEmpty)
        XCTAssertFalse(coordinator.readyRequests(now: 11).contains { $0.id == request.id })
    }

    func testRuntimeProjectionServiceDrainsVerifiedFocusThroughCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let pid = pid_t(18_405)
        let focusedCGWindowID = CGWindowID(240_001)
        let focusedAXWindow = AXUIElementCreateApplication(pid)
        let focusedAXWindowID = AXWindowInspectorForTesting.makeWindowID(pid: pid, index: 0)
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [
                focusedCGWindowID: RuntimeWindowRecord(
                    cgWindowID: focusedCGWindowID,
                    stableWindowID: "cg:\(pid):\(focusedCGWindowID)",
                    firstSeenAt: 1
                )
            ],
            validCGWindowIDs: [focusedCGWindowID]
        )
        AXLiveWindowRegistry.shared.refreshSnapshot(forPID: pid, windows: [focusedAXWindow])
        defer { AXLiveWindowRegistry.shared.remove(pid: pid) }
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.VerifiedFocusSignal",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: "com.example.editor",
                windowID: "cg:18405:240001",
                ownerPID: pid,
                targetCGWindowID: focusedCGWindowID,
                focusedCGWindowID: focusedCGWindowID,
                focusedAXWindow: focusedAXWindow,
                title: "Verified Window",
                frame: CGRect(x: 10, y: 20, width: 800, height: 600),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.target, .app(pid))
        XCTAssertEqual(request.reasons, Set([.activationVerified]))
        XCTAssertEqual(request.affectedCGWindowIDs, Set<CGWindowID>([focusedCGWindowID]))
        XCTAssertEqual(request.state, .inFlight)
        let record = try XCTUnwrap(provider.windowMappingStateByPID[pid]?.windowRecordsByCGWindowID[focusedCGWindowID])
        XCTAssertEqual(record.bindingConfidence, .exact)
        XCTAssertEqual(record.lastConfirmationSource, .verifiedFocusReadback)
        XCTAssertEqual(record.lastExactAXWindowID, focusedAXWindowID)
        XCTAssertEqual(provider.windowMappingStateByPID[pid]?.currentAXToCG[focusedAXWindowID], focusedCGWindowID)
        XCTAssertTrue(coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).isEmpty)
    }

    func testRuntimeProjectionServiceSeedsVerifiedFocusRecordWithoutPriorMappingState() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let pid = pid_t(18_406)
        let focusedCGWindowID = CGWindowID(240_101)
        let focusedAXWindow = AXUIElementCreateApplication(pid)
        let focusedAXWindowID = AXWindowInspectorForTesting.makeWindowID(pid: pid, index: 0)
        AXLiveWindowRegistry.shared.refreshSnapshot(forPID: pid, windows: [focusedAXWindow])
        defer { AXLiveWindowRegistry.shared.remove(pid: pid) }
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.VerifiedFocusSeed",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: "com.example.seed",
                windowID: "cg:18406:240101",
                ownerPID: pid,
                targetCGWindowID: focusedCGWindowID,
                focusedCGWindowID: focusedCGWindowID,
                focusedAXWindow: focusedAXWindow,
                title: "Seeded Verified Window",
                frame: CGRect(x: 30, y: 40, width: 640, height: 480),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.target, .app(pid))
        XCTAssertEqual(request.affectedCGWindowIDs, Set<CGWindowID>([focusedCGWindowID]))
        let mappingState = try XCTUnwrap(provider.windowMappingStateByPID[pid])
        let record = try XCTUnwrap(mappingState.windowRecordsByCGWindowID[focusedCGWindowID])
        XCTAssertEqual(record.bindingConfidence, .exact)
        XCTAssertEqual(record.lastConfirmationSource, .verifiedFocusReadback)
        XCTAssertEqual(record.lastExactAXWindowID, focusedAXWindowID)
        XCTAssertEqual(mappingState.currentAXToCG[focusedAXWindowID], focusedCGWindowID)
        XCTAssertEqual(mappingState.validCGWindowIDs, [focusedCGWindowID])
    }

    func testRuntimeProjectionServiceSeedsVerifiedFocusRecordWhenFocusedAXWindowIsNotInRegistry() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let pid = pid_t(18_407)
        let focusedCGWindowID = CGWindowID(240_201)
        let focusedAXWindow = AXUIElementCreateApplication(pid)
        let focusedAXWindowID = AXWindowInspectorForTesting.makeVerifiedFocusFallbackWindowID(
            pid: pid,
            cgWindowID: focusedCGWindowID
        )
        AXLiveWindowRegistry.shared.remove(pid: pid)
        defer { AXLiveWindowRegistry.shared.remove(pid: pid) }
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.VerifiedFocusFallbackAXID",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: "com.example.fallback",
                windowID: "cg:18407:240201",
                ownerPID: pid,
                targetCGWindowID: focusedCGWindowID,
                focusedCGWindowID: focusedCGWindowID,
                focusedAXWindow: focusedAXWindow,
                title: "Fallback Verified Window",
                frame: CGRect(x: 50, y: 60, width: 700, height: 500),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.target, .app(pid))
        XCTAssertEqual(request.affectedCGWindowIDs, Set<CGWindowID>([focusedCGWindowID]))
        let mappingState = try XCTUnwrap(provider.windowMappingStateByPID[pid])
        let record = try XCTUnwrap(mappingState.windowRecordsByCGWindowID[focusedCGWindowID])
        XCTAssertEqual(record.bindingConfidence, .exact)
        XCTAssertEqual(record.lastConfirmationSource, .verifiedFocusReadback)
        XCTAssertEqual(record.lastExactAXWindowID, focusedAXWindowID)
        XCTAssertEqual(mappingState.currentAXToCG[focusedAXWindowID], focusedCGWindowID)
        XCTAssertNil(AXWindowInspectorForTesting.windowIndex(from: focusedAXWindowID, expectedPID: pid))
        XCTAssertEqual(mappingState.validCGWindowIDs, [focusedCGWindowID])
    }

    func testRuntimeProjectionServiceSchedulesRetryWhenDrainSeesTransientEmptyCurrentAppWindowPayload() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [0.1])
        )
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.TransientCurrentAppPayloadRetry",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            reconciliationExecutor: { _, _ in
                .transientEmptyCurrentAppWindowPayload
            }
        )

        let dirty = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .axNotification,
            now: 10
        )
        let drained = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10)

        XCTAssertEqual(drained.map(\.id), [dirty.id])
        XCTAssertTrue(coordinator.readyRequests(now: 10.09).isEmpty)

        let retry = try XCTUnwrap(coordinator.readyRequests(now: 10.1).first)
        XCTAssertEqual(retry.id, dirty.id)
        XCTAssertEqual(retry.target, .app(18_405))
        XCTAssertEqual(retry.state, .waitingRetry)
        XCTAssertEqual(retry.attempt, 1)
    }

    func testRuntimeProjectionServiceMaintenanceRequestDrainsReadyRequestsBySchedulerPriority() {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let lowPriority = coordinator.markAppDirty(
            appID: "com.example.low",
            pid: 18_405,
            reason: .manualRefresh,
            now: 10
        )
        let highPriority = coordinator.markAppDirty(
            appID: "com.example.high",
            pid: 18_406,
            reason: .appLaunched,
            now: 10.1
        )
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let expectation = expectation(description: "runtime maintenance drains ready requests")
        expectation.expectedFulfillmentCount = 2
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.MaintenancePriority",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                expectation.fulfill()
                return .completed
            }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(executedRequests.map(\.id), [highPriority.id, lowPriority.id])
        XCTAssertEqual(executedRequests.map(\.priority), [.high, .low])
        XCTAssertTrue(coordinator.readyRequests(now: 11).isEmpty)
    }

    func testRuntimeProjectionServiceMaintenanceSchedulesLowPriorityFullRepairWhenProjectionMissing() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.full-repair",
            displayName: "Full Repair",
            groupID: "full",
            lastActiveAt: 42,
            windows: []
        )
        let appDirectoryEntries = [
            RuntimeAppDirectoryEntry(
                pid: 51_001,
                appID: repairedApp.id,
                bundleIdentifier: "com.example.full-repair",
                localizedName: repairedApp.displayName,
                launchDate: nil
            ),
            RuntimeAppDirectoryEntry(
                pid: 51_002,
                appID: "com.example.full-repair-helper",
                bundleIdentifier: "com.example.full-repair-helper",
                localizedName: "Full Repair Helper",
                launchDate: nil
            )
        ]
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let expectation = expectation(description: "runtime maintenance executes full repair fallback")
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.FullRepairFallback",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                expectation.fulfill()
                return .completedWithFullRepairProjection(
                    RuntimeFullRepairProjectionPayload(
                        apps: [repairedApp],
                        contextsByID: [:],
                        appDirectoryEntries: appDirectoryEntries
                    )
                )
            }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        wait(for: [expectation], timeout: 1)
        service.waitForMaintenanceQueueForTesting()

        XCTAssertEqual(executedRequests.map(\.target), [.fullRepair])
        XCTAssertEqual(executedRequests.map(\.priority), [.low])
        XCTAssertEqual(executedRequests.first?.reasons, Set([.fullRepairFallback]))
        let projection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(projection.apps.map(\.id), [repairedApp.id])
        XCTAssertTrue(projection.freshness.isCompleteForScope)
        let appDirectoryProjection = try XCTUnwrap(store.readAppDirectoryProjection())
        XCTAssertEqual(appDirectoryProjection.entries, appDirectoryEntries)
        XCTAssertTrue(appDirectoryProjection.freshness.isCompleteForScope)
        XCTAssertTrue(coordinator.readyRequests(now: 11).isEmpty)
    }

    func testRuntimeProjectionServiceSearchFreshnessBarrierPromotesAndBoundsReadyRepairs() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [60])
        )
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        var requests: [RuntimeReconciliationRequest] = []
        for index in 0...runtimeSearchFreshnessBarrierMaxReadyRepairs {
            let appID = "com.example.search-barrier-\(index)"
            let pid = pid_t(18_405 + index)
            store.markAppWindowsDirty(
                appID: appID,
                pid: pid,
                pendingScope: "appWindows:\(appID)"
            )
            requests.append(
                coordinator.markAppDirty(
                    appID: appID,
                    pid: pid,
                    reason: .manualRefresh,
                    now: 10 + Double(index) / 10
                )
            )
        }
        let waitingRetry = try XCTUnwrap(coordinator.startRequest(id: requests[0].id))
        let retryStart = Date.timeIntervalSinceReferenceDate
        let retry = try XCTUnwrap(
            coordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(
                id: waitingRetry.id,
                now: retryStart
            )
        )
        XCTAssertEqual(retry.priority, .low)
        XCTAssertFalse(coordinator.readyRequests(now: retryStart + 1).contains { $0.id == retry.id })

        let expectedExecuted = Array(requests.prefix(runtimeSearchFreshnessBarrierMaxReadyRepairs))
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let expectation = expectation(description: "search freshness barrier drains ready requests")
        expectation.expectedFulfillmentCount = runtimeSearchFreshnessBarrierMaxReadyRepairs
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SearchFreshnessBarrier",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                expectation.fulfill()
                return .completed
            }
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(executedRequests.map(\.id), expectedExecuted.map(\.id))
        XCTAssertEqual(
            executedRequests.map(\.priority),
            Array(repeating: .high, count: runtimeSearchFreshnessBarrierMaxReadyRepairs)
        )
        XCTAssertTrue(executedRequests.allSatisfy { $0.reasons.contains(.searchFreshnessBarrier) })
        XCTAssertEqual(executedRequests.first?.attempt, 0)
        let remainingRequests = coordinator.readyRequests(
            now: Date.timeIntervalSinceReferenceDate + 1
        )
        XCTAssertEqual(remainingRequests.count, 1)
        XCTAssertEqual(remainingRequests.first?.priority, .high)
        XCTAssertTrue(remainingRequests.first?.reasons.contains(.searchFreshnessBarrier) == true)
        let read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            read.projection?.appEntries.map(\.appID),
            committedApps.map(\.id)
        )
        XCTAssertFalse(store.diagnostics().hasStagingSearchIndex)
    }

    func testRuntimeProjectionServiceSearchFreshnessBarrierDoesNotPromoteOrDrainFullRepairFallback() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let dirtyApp = try XCTUnwrap(committedApps.first)
        let pid = pid_t(42_104)
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: dirtyApp.id,
            pid: pid,
            pendingScope: "appWindows:\(dirtyApp.id)"
        )
        let fullRepair = coordinator.scheduleFullRepairFallback(now: 10)
        coordinator.markAppDirty(
            appID: dirtyApp.id,
            pid: pid,
            reason: .manualRefresh,
            now: 10.1
        )
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let expectation = expectation(description: "search barrier drains scoped repair only")
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SearchBarrierSkipsFullRepair",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                expectation.fulfill()
                return .completed
            }
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        wait(for: [expectation], timeout: 1)
        service.waitForMaintenanceQueueForTesting()

        XCTAssertEqual(executedRequests.map(\.target), [.app(pid)])
        XCTAssertTrue(executedRequests.allSatisfy { $0.reasons.contains(.searchFreshnessBarrier) })
        let remaining = coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate + 1)
        XCTAssertFalse(executedRequests.contains { $0.id == fullRepair.id })
        XCTAssertFalse(remaining.contains { $0.id == fullRepair.id })
        let read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(read.committedIndexCoversCurrentGeneration)
    }

    func testRuntimeProjectionServiceSearchFreshnessBarrierCommitsRepairedSearchGeneration() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 320,
            windows: [
                WindowCandidate(
                    id: "browser-fresh",
                    title: "Fresh Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 320
                )
            ]
        )
        let pid = pid_t(42_102)
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        coordinator.markAppDirty(
            appID: repairedApp.id,
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        let expectation = expectation(description: "search freshness barrier commits repaired index")
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SearchFreshnessBarrierCommit",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { _, _ in
                expectation.fulfill()
                return .completedWithRepairedCurrentAppWindowPayloads([
                    self.makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)
                ])
            }
        )

        XCTAssertEqual(store.readCommittedSearchIndexForSearch().readiness, .staleCommitted)
        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        wait(for: [expectation], timeout: 1)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 11)

        let read = store.readCommittedSearchIndexForSearch()
        let projection = try XCTUnwrap(read.projection)
        XCTAssertEqual(read.readiness, .verifiedCurrentGenerationCommitted)
        XCTAssertEqual(read.resultState, .verifiedCurrentGenerationCommittedResult)
        XCTAssertTrue(read.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(
            projection.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-fresh"]
        )
        let diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.dirtyAppIDs.isEmpty)
        XCTAssertFalse(diagnostics.hasStagingSearchIndex)
    }

    func testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRepairDefers() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [0.5])
        )
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 320,
            windows: [
                WindowCandidate(
                    id: "browser-deferred",
                    title: "Deferred Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 320
                )
            ]
        )
        let pid = pid_t(42_103)
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )
        coordinator.markAppDirty(
            appID: repairedApp.id,
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        let expectation = expectation(description: "search freshness barrier defers repair")
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SearchFreshnessBarrierDeferred",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { _, _ in
                expectation.fulfill()
                return .transientEmptyCurrentAppWindowPayload
            }
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        wait(for: [expectation], timeout: 1)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10.1)

        let read = store.readCommittedSearchIndexForSearch()
        let projection = try XCTUnwrap(read.projection)
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(read.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(read.freshness?.dirtyAppIDs, [repairedApp.id])
        XCTAssertEqual(read.freshness?.dirtyPIDs, [pid])
        XCTAssertEqual(read.freshness?.pendingRepairScopes, ["appWindows:\(repairedApp.id)"])
        XCTAssertEqual(
            projection.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )
        XCTAssertTrue(store.diagnostics().hasStagingSearchIndex)
        XCTAssertTrue(coordinator.readyRequests(now: 10.49).isEmpty)
    }

    func testRuntimeProjectionServiceSearchFreshnessBarrierDoesNotCommitStaleStagingWithoutRepairPayload() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let stagedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 320,
            windows: [
                WindowCandidate(
                    id: "browser-stale-staging",
                    title: "Stale Staging Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 320
                )
            ]
        )
        let pid = pid_t(42_107)
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: stagedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(stagedApp.id)"
        )
        store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: stagedApp, pid: pid)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )
        coordinator.markAppDirty(
            appID: stagedApp.id,
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        let expectation = expectation(description: "search freshness barrier completes without repair payload")
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SearchFreshnessBarrierStaleStaging",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { _, _ in
                expectation.fulfill()
                return .completed
            }
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        wait(for: [expectation], timeout: 1)
        service.waitForMaintenanceQueueForTesting()

        let read = store.readCommittedSearchIndexForSearch()
        let projection = try XCTUnwrap(read.projection)
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            projection.windowEntries.filter { $0.appID == stagedApp.id }.map(\.windowID),
            ["browser-1"]
        )
        let diagnostics = store.diagnostics()
        XCTAssertEqual(diagnostics.dirtyAppIDs, [stagedApp.id])
        XCTAssertEqual(diagnostics.dirtyPIDs, [pid])
        XCTAssertEqual(diagnostics.pendingRepairScopes, ["appWindows:\(stagedApp.id)"])
        XCTAssertTrue(diagnostics.hasStagingSearchIndex)
        XCTAssertTrue(coordinator.readyRequests(now: 11).isEmpty)
    }

    func testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRetryExhaustsToFullRepairFallback() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [])
        )
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 320,
            windows: [
                WindowCandidate(
                    id: "browser-exhausted",
                    title: "Exhausted Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 320
                )
            ]
        )
        let pid = pid_t(42_105)
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )
        coordinator.markAppDirty(
            appID: repairedApp.id,
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        let expectation = expectation(description: "search freshness barrier exhausts scoped repair")
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SearchFreshnessBarrierRetryExhausted",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { _, _ in
                expectation.fulfill()
                return .transientEmptyCurrentAppWindowPayload
            }
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        wait(for: [expectation], timeout: 1)
        service.waitForMaintenanceQueueForTesting()

        let remainingRequests = coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate + 1)
        XCTAssertEqual(remainingRequests.map(\.target), [.fullRepair])
        XCTAssertEqual(remainingRequests.first?.reasons, Set([.fullRepairFallback]))
        XCTAssertEqual(remainingRequests.first?.priority, .low)
        let read = store.readCommittedSearchIndexForSearch()
        let projection = try XCTUnwrap(read.projection)
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(read.resultState, .degradedStaleCommittedResult)
        XCTAssertEqual(
            projection.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )
        XCTAssertTrue(store.diagnostics().hasStagingSearchIndex)
    }

    func testRuntimeProjectionServiceFullRepairFallbackCommitsDegradedProjectionWithoutRefreshingSearch() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [])
        )
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let store = RuntimeReadModelStore()
        let committedApps = searchScenarioApps()
        let repairedApp = AppSwitchCandidate(
            id: "com.example.browser",
            displayName: "Browser",
            groupID: "web",
            lastActiveAt: 320,
            windows: [
                WindowCandidate(
                    id: "browser-full-repair",
                    title: "Full Repair Runtime Docs",
                    isMinimized: false,
                    lastActiveAt: 320
                )
            ]
        )
        let pid = pid_t(42_106)
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        store.commitSearchFreshnessBarrierPayloads(
            [makeRuntimeCurrentAppWindowPayload(app: repairedApp, pid: pid)],
            deferredRequestCount: 1,
            hasPendingRequests: false,
            generatedAt: 20
        )
        coordinator.markAppDirty(
            appID: repairedApp.id,
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.FullRepairDegradedCommit",
            repairProvider: RuntimeProjectionRepairProvider(runtimeFactProvider: provider),
            readModelStore: store,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                switch request.target {
                case .app:
                    return .transientEmptyCurrentAppWindowPayload
                case .fullRepair:
                    return .completedWithFullRepairProjection(
                        RuntimeFullRepairProjectionPayload(
                            apps: [repairedApp],
                            contextsByID: [:],
                            appDirectoryEntries: []
                        )
                    )
                case .spaceTopology:
                    return .completed
                }
            }
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        service.waitForMaintenanceQueueForTesting()
        XCTAssertEqual(executedRequests.map(\.target), [.app(pid)])

        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(
            now: Date.timeIntervalSinceReferenceDate + 1
        )

        XCTAssertEqual(executedRequests.map(\.target), [.app(pid), .fullRepair])
        let appSwitcherProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appSwitcherProjection.apps.map(\.id), [repairedApp.id])
        XCTAssertEqual(appSwitcherProjection.apps.first?.windows.map(\.id), ["browser-full-repair"])
        XCTAssertFalse(appSwitcherProjection.freshness.isCompleteForScope)
        let searchRead = store.readCommittedSearchIndexForSearch()
        let searchProjection = try XCTUnwrap(searchRead.projection)
        XCTAssertEqual(searchRead.readiness, .staleCommitted)
        XCTAssertEqual(searchRead.resultState, .degradedStaleCommittedResult)
        XCTAssertFalse(searchRead.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(
            searchProjection.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )
        let diagnostics = store.diagnostics()
        XCTAssertEqual(diagnostics.dirtyAppIDs, [repairedApp.id])
        XCTAssertEqual(diagnostics.dirtyPIDs, [pid])
        XCTAssertEqual(diagnostics.pendingRepairScopes, ["appWindows:\(repairedApp.id)"])
        XCTAssertTrue(diagnostics.hasStagingSearchIndex)
    }

    private func makeRuntimeCurrentAppWindowPayload(
        app: AppSwitchCandidate,
        pid: pid_t
    ) -> RuntimeCurrentAppWindowPayload {
        RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: app.id,
                displayName: app.displayName,
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt,
                windowCount: app.windows.count,
                pid: pid
            ),
            candidate: app,
            context: makeRuntimeAppContext(
                appID: app.id,
                runningApp: .current,
                windows: app.windows
            ),
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: .current)]
        )
    }
}
