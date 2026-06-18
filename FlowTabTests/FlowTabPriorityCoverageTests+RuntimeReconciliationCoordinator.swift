import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testRuntimeReadModelStoreCommitsProjectionsAndMarksDirtyMetadata() throws {
        let store = RuntimeReadModelStore()
        let apps = searchScenarioApps()
        let app = try XCTUnwrap(apps.first)
        let pid = NSRunningApplication.current.processIdentifier
        let generatedAt = TimeInterval(42)

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
            generatedAt: generatedAt
        )

        var appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), apps.map(\.id))
        XCTAssertEqual(appProjection.freshness.generatedAt, generatedAt)
        XCTAssertTrue(appProjection.freshness.isCompleteForScope)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 1)
        let searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .currentGenerationCommitted)
        let searchProjection = try XCTUnwrap(searchRead.projection)
        XCTAssertEqual(searchProjection.appEntries.map(\.appID), apps.map(\.id))
        XCTAssertEqual(
            searchProjection.windowEntries.map(\.windowID),
            apps.flatMap(\.windows).map(\.id)
        )
        XCTAssertEqual(searchProjection.freshness.generatedAt, generatedAt)
        XCTAssertTrue(searchProjection.freshness.isCompleteForScope)

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
            )
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
    }

    func testRuntimeCurrentAppWindowPayloadOwnsProviderRepairPayloadProjection() throws {
        let app = try XCTUnwrap(searchScenarioApps().first)
        let pid = NSRunningApplication.current.processIdentifier
        let summary = RuntimeHomeAppSummary(
            appID: app.id,
            displayName: app.displayName,
            groupID: app.groupID,
            lastActiveAt: app.lastActiveAt,
            windowCount: app.windows.count,
            pid: pid
        )
        let context = makeRuntimeAppContext(
            appID: app.id,
            runningApp: .current,
            windows: app.windows
        )
        let repairPayload = RuntimeAppWindowRepairPayload(
            summary: summary,
            candidate: app,
            context: context
        )

        let payload = RuntimeCurrentAppWindowPayload(repairPayload: repairPayload)

        XCTAssertEqual(payload.summary.appID, app.id)
        XCTAssertEqual(payload.summary.windowCount, app.windows.count)
        XCTAssertEqual(payload.candidate.id, app.id)
        XCTAssertEqual(payload.candidate.windows.map(\.id), app.windows.map(\.id))
        XCTAssertEqual(payload.context.appID, app.id)
        XCTAssertEqual(
            payload.context.windowsByID.keys.sorted(),
            app.windows.map(\.id).sorted()
        )
    }

    func testRuntimeReadModelStoreRemovesTerminatedAppFromCommittedProjectionsAndSearch() throws {
        let store = RuntimeReadModelStore()
        let apps = searchScenarioApps()
        let terminatedApp = try XCTUnwrap(apps.first)
        let remainingApps = Array(apps.dropFirst())
        let pid = NSRunningApplication.current.processIdentifier

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
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
        XCTAssertEqual(searchRead.readiness, .currentGenerationCommitted)
        XCTAssertFalse(searchRead.projection?.appEntries.contains { $0.appID == terminatedApp.id } ?? true)
        XCTAssertFalse(searchRead.projection?.windowEntries.contains { $0.appID == terminatedApp.id } ?? true)
        XCTAssertEqual(
            searchRead.projection?.appEntries.map(\.appID),
            remainingApps.map(\.id)
        )

        store.markAppTerminated(appID: terminatedApp.id, pid: pid)

        let duplicateSignalProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(duplicateSignalProjection.apps.map(\.id), remainingApps.map(\.id))
        XCTAssertEqual(duplicateSignalProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(duplicateSignalProjection.freshness.sourceGeneration.projection, 2)
    }

    func testRuntimeReadModelStorePreservesRunningInstanceWhenSameBundleDifferentPIDTerminates() throws {
        let store = RuntimeReadModelStore()
        let apps = terminateScenarioApps()
        let activeApp = try XCTUnwrap(apps.first)
        let activePID = NSRunningApplication.current.processIdentifier
        let context = makeRuntimeAppContext(
            appID: activeApp.id,
            runningApp: .current,
            windows: activeApp.windows
        )

        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [activeApp.id: context],
            generatedAt: 10
        )

        store.markAppTerminated(appID: activeApp.id, pid: activePID + 1)

        var appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(appProjection.apps.map(\.id), apps.map(\.id))
        XCTAssertEqual(
            appProjection.contextsByID[activeApp.id]?.runningApp.processIdentifier,
            activePID
        )
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 0)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 1)
        var searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .currentGenerationCommitted)
        XCTAssertTrue(searchRead.projection?.appEntries.contains { $0.appID == activeApp.id } ?? false)

        store.markAppTerminated(appID: activeApp.id, pid: activePID)

        appProjection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertFalse(appProjection.apps.contains { $0.id == activeApp.id })
        XCTAssertNil(appProjection.contextsByID[activeApp.id])
        XCTAssertEqual(appProjection.freshness.sourceGeneration.appLifecycle, 1)
        XCTAssertEqual(appProjection.freshness.sourceGeneration.projection, 2)
        searchRead = store.readCommittedSearchIndexForSearch()
        XCTAssertFalse(searchRead.projection?.appEntries.contains { $0.appID == activeApp.id } ?? true)
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
            clearsDirtyState: false,
            generatedAt: 1
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.ReadModelStore",
            snapshotProvider: provider,
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

    func testRuntimeReadModelStoreKeepsStagingSearchIndexHiddenUntilCommit() throws {
        let store = RuntimeReadModelStore()
        let apps = searchScenarioApps()

        store.stageSearchIndexApps(apps, generatedAt: 20)

        var read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .missingCommittedIndex)
        XCTAssertNil(read.projection)
        var diagnostics = store.diagnostics()
        XCTAssertFalse(diagnostics.hasCommittedSearchIndex)
        XCTAssertTrue(diagnostics.hasStagingSearchIndex)

        let committed = try XCTUnwrap(
            store.commitStagedSearchIndex(generatedAt: 21)
        )

        XCTAssertEqual(committed.freshness.generatedAt, 21)
        XCTAssertTrue(committed.freshness.isCompleteForScope)
        read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .currentGenerationCommitted)
        XCTAssertEqual(
            read.projection?.windowEntries.map(\.windowID),
            apps.flatMap(\.windows).map(\.id)
        )
        diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.hasCommittedSearchIndex)
        XCTAssertFalse(diagnostics.hasStagingSearchIndex)
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
            generatedAt: 10
        )

        var read = store.readCommittedSearchIndexForSearch()
        XCTAssertEqual(read.readiness, .currentGenerationCommitted)
        XCTAssertEqual(read.projection?.appEntries.map(\.appID), committedApps.map(\.id))

        store.markAppWindowsDirty(
            appID: "com.example.browser",
            pid: 42_100,
            pendingScope: "appWindows:com.example.browser"
        )
        store.stageSearchIndexApps(stagedApps, generatedAt: 20)

        read = store.readCommittedSearchIndexForSearch()
        let staleProjection = try XCTUnwrap(read.projection)
        XCTAssertEqual(read.readiness, .staleCommitted)
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
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: 42_101,
            pendingScope: "appWindows:\(repairedApp.id)"
        )

        let staged = try XCTUnwrap(
            store.stageSearchIndexApp(
                repairedApp,
                generatedAt: 20
            )
        )
        XCTAssertEqual(staged.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID), ["browser-2"])
        XCTAssertEqual(store.readCommittedSearchIndexForSearch().readiness, .staleCommitted)
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )

        let committed = try XCTUnwrap(store.commitStagedSearchIndex(generatedAt: 21))

        XCTAssertTrue(committed.freshness.isCompleteForScope)
        XCTAssertEqual(store.readCommittedSearchIndexForSearch().readiness, .currentGenerationCommitted)
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
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
            )
        )
        store.commitAppSwitcherProjection(
            apps: committedApps,
            contextsByID: [:],
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )

        let staged = try XCTUnwrap(
            store.stageSearchIndexCurrentAppWindowPayloads([payload], generatedAt: 20)
        )

        XCTAssertEqual(staged.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID), ["browser-payload"])
        XCTAssertEqual(store.readCommittedSearchIndexForSearch().readiness, .staleCommitted)
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )

        let committed = try XCTUnwrap(store.commitStagedSearchIndex(generatedAt: 21))

        XCTAssertTrue(committed.freshness.isCompleteForScope)
        XCTAssertEqual(
            store.readCommittedSearchIndexForSearch().projection?.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-payload"]
        )
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

    func testRuntimeReconciliationCoordinatorCoalescesDirtyAppAndRetriesTransientEmptyAXSnapshots() throws {
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
            coordinator.scheduleRetryAfterTransientEmptyAXSnapshot(
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
            coordinator.scheduleRetryAfterTransientEmptyAXSnapshot(
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
            snapshotProvider: provider,
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

    func testRuntimeSnapshotProviderDerivesAffectedAppTargetsFromRecordsAndCurrentCGWindows() {
        let provider = RuntimeSnapshotProvider()
        let recordedWindowID = CGWindowID(240_001)
        let currentWindowID = CGWindowID(240_002)
        let unrelatedWindowID = CGWindowID(240_003)
        let staleWindowID = CGWindowID(240_004)
        let recordedPID = pid_t(1_840_501_405)
        let currentPID = pid_t(1_840_501_406)
        var record = RuntimeWindowRecord(
            cgWindowID: recordedWindowID,
            stableWindowID: "cg:\(recordedPID):\(recordedWindowID)",
            firstSeenAt: 10
        )
        record.refreshCGState(
            from: RuntimeSnapshotProvider.CGWindowEntry(
                id: recordedWindowID,
                title: "Recorded",
                bounds: CGRect(x: 10, y: 10, width: 320, height: 240),
                isOnscreen: false,
                alpha: 1.0,
                storeType: 1,
                spaceIDs: [7_001]
            ),
            observedAt: 11
        )
        provider.windowMappingStateByPID[recordedPID] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [recordedWindowID: record]
        )
        let currentCGWindowsByPID: [pid_t: [RuntimeSnapshotProvider.CGWindowEntry]] = [
            currentPID: [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: currentWindowID,
                    title: "Current",
                    bounds: CGRect(x: 20, y: 20, width: 640, height: 480),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [7_002]
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: unrelatedWindowID,
                    title: "Unrelated",
                    bounds: CGRect(x: 30, y: 30, width: 640, height: 480),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [7_003]
                )
            ]
        ]

        let targets = provider.appReconciliationTargets(
            affectedCGWindowIDs: [recordedWindowID, currentWindowID, staleWindowID],
            currentCGWindowsByPID: currentCGWindowsByPID
        )

        XCTAssertEqual(
            targets,
            [
                RuntimeAffectedWindowReconciliationTarget(
                    pid: recordedPID,
                    appID: "pid:\(recordedPID)",
                    affectedCGWindowIDs: [recordedWindowID]
                ),
                RuntimeAffectedWindowReconciliationTarget(
                    pid: currentPID,
                    appID: "pid:\(currentPID)",
                    affectedCGWindowIDs: [currentWindowID]
                )
            ]
        )
    }

    func testRuntimeSnapshotProviderReconcilesAppWindowsWithAffectedCGWindowScope() {
        let provider = RuntimeSnapshotProvider()
        let currentPID = NSRunningApplication.current.processIdentifier
        let affectedCGWindowIDs: Set<CGWindowID> = [240_001, 240_002]

        let result = provider.reconcileAppWindows(
            processIdentifier: currentPID,
            affectedCGWindowIDs: affectedCGWindowIDs
        )

        XCTAssertEqual(result.pid, currentPID)
        XCTAssertEqual(result.affectedCGWindowIDs, affectedCGWindowIDs)
    }

    func testRuntimeSnapshotProviderReconciliationResultReportsAffectedWindowRecordEvidence() {
        let provider = RuntimeSnapshotProvider()
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

        let result = provider.reconcileAppWindows(
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
            snapshotProvider: provider,
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
            snapshotProvider: provider,
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
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppLaunchSignal",
            snapshotProvider: provider,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalAppLaunched(appID: "com.example.new", pid: 18_407)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.target, .app(18_407))
        XCTAssertEqual(request.appID, "com.example.new")
        XCTAssertEqual(request.reasons, Set([.appLaunched]))
        XCTAssertEqual(request.state, .inFlight)
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
            generatedAt: 10
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppLaunchRepairCommit",
            snapshotProvider: provider,
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
            snapshotProvider: provider
        )

        service.signalAppTerminated(appID: "com.example.terminated", pid: pid)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 11)

        XCTAssertNil(provider.windowMappingStateByPID[pid])
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
            snapshotProvider: provider,
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
            snapshotProvider: provider,
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
            snapshotProvider: provider,
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

    func testRuntimeProjectionServiceSchedulesRetryWhenDrainSeesTransientEmptyAXSnapshot() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [0.1])
        )
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.TransientAXRetry",
            snapshotProvider: provider,
            reconciliationExecutor: { _, _ in
                .transientEmptyAXSnapshot
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
            snapshotProvider: provider,
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

    func testRuntimeProjectionServiceSearchFreshnessBarrierDrainsReadyRequestsBySchedulerPriority() {
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
        let expectation = expectation(description: "search freshness barrier drains ready requests")
        expectation.expectedFulfillmentCount = 2
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SearchFreshnessBarrier",
            snapshotProvider: provider,
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

        XCTAssertEqual(executedRequests.map(\.id), [highPriority.id, lowPriority.id])
        XCTAssertEqual(executedRequests.map(\.priority), [.high, .low])
        XCTAssertTrue(coordinator.readyRequests(now: 11).isEmpty)
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
            snapshotProvider: provider,
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
        XCTAssertEqual(read.readiness, .currentGenerationCommitted)
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
            generatedAt: 10
        )
        store.markAppWindowsDirty(
            appID: repairedApp.id,
            pid: pid,
            pendingScope: "appWindows:\(repairedApp.id)"
        )
        store.stageSearchIndexApp(
            repairedApp,
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
            snapshotProvider: provider,
            readModelStore: store,
            reconciliationExecutor: { _, _ in
                expectation.fulfill()
                return .transientEmptyAXSnapshot
            }
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        wait(for: [expectation], timeout: 1)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10.1)

        let read = store.readCommittedSearchIndexForSearch()
        let projection = try XCTUnwrap(read.projection)
        XCTAssertEqual(read.readiness, .staleCommitted)
        XCTAssertEqual(
            projection.windowEntries.filter { $0.appID == repairedApp.id }.map(\.windowID),
            ["browser-1"]
        )
        XCTAssertTrue(store.diagnostics().hasStagingSearchIndex)
        XCTAssertTrue(coordinator.readyRequests(now: 10.49).isEmpty)
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
            )
        )
    }
}
