import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testCurrentAppRepairEvidenceScopesReconciledPIDsToItsAppIdentity() {
        let appID = "com.example.multi-process"
        let selectedPID = pid_t(6_520)
        let siblingPID = pid_t(83_885)
        let unrelatedPID = pid_t(56_956)
        let entries = [
            RuntimeAppDirectoryEntry(
                pid: siblingPID,
                appID: appID,
                bundleIdentifier: appID,
                localizedName: "Multi Process",
                launchDate: nil
            ),
            RuntimeAppDirectoryEntry(
                pid: unrelatedPID,
                appID: "com.example.unrelated",
                bundleIdentifier: "com.example.unrelated",
                localizedName: "Unrelated",
                launchDate: nil
            )
        ]
        let evidence = RuntimeCurrentAppRepairEvidence(
            appID: appID,
            pid: selectedPID,
            appDirectoryEntries: entries,
            currentAppWindowPayloadWasEmpty: false
        )

        XCTAssertEqual(
            evidence.reconciledPIDs,
            [selectedPID, siblingPID]
        )
    }

    func testMainTableHomeSummaryUsesWindowBackedPrimaryPID() throws {
        let appID = "com.example.multi-process"
        let windowApp = NSRunningApplication.current
        let windowPID = windowApp.processIdentifier
        let rankPreferredPID: pid_t =
            windowPID == 83_885 ? 83_886 : 83_885
        let windowEntry = RuntimeAppDirectoryEntry(
            pid: windowPID,
            appID: appID,
            bundleIdentifier: appID,
            localizedName: "Multi Process",
            launchDate: nil,
            activationRank: 1,
            runningApplication: windowApp
        )
        let rankPreferredEntry = RuntimeAppDirectoryEntry(
            pid: rankPreferredPID,
            appID: appID,
            bundleIdentifier: appID,
            localizedName: "Multi Process Helper",
            launchDate: nil,
            activationRank: 0
        )
        let cgWindowID = CGWindowID(240_172)
        let axWindowID = "ax:\(windowPID):primary-window"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                windowPID: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: windowPID,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasRecordedWindowCollection: true,
                    hasObservedAXWindowHandle: true
                ),
                rankPreferredPID: RuntimeWindowMappingState(
                    hasRecordedWindowCollection: true
                )
            ]
        )
        let payload = try XCTUnwrap(
            RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ).appSwitcherProjectionPayloadFromMainTables(
                appDirectoryEntries: [
                    rankPreferredEntry,
                    windowEntry
                ],
                generatedAt: 10
            )
        )
        let context = try XCTUnwrap(payload.contextsByID[appID])
        let summary = try XCTUnwrap(
            payload.homeSummaries.first { $0.appID == appID }
        )

        XCTAssertEqual(context.ownerPID, windowPID)
        XCTAssertEqual(summary.pid, windowPID)
        XCTAssertEqual(summary.windowCount, 1)
    }

    func testRuntimeProjectionServiceSearchFreshnessBarrierCommitsAfterScheduledCoverageRepairUpdatesMainTable() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let cgWindowID = CGWindowID(240_170)
        let axWindowID = "ax:\(pid):scheduled-search-coverage"
        let readModelStore = RuntimeReadModelStore()
        let windowRecordStore = RuntimeWindowRecordStore()
        let builder = RuntimeMainTableProjectionBuilder(windowRecordStore: windowRecordStore)
        let expectedReasons: Set<RuntimeReconciliationReason> = [
            .searchFreshnessBarrier
        ]
        let requestLock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let expectation = expectation(
            description:
                "unmetCondition=scheduledSearchCoverageRepairExecutesExactAppRequest"
        )
        expectation.assertForOverFulfill = true
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.SearchScheduledCoverageRepairCommit",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: builder,
            appDirectoryProvider: FixedRuntimeAppDirectoryProvider(entries: [appDirectoryEntry]),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                executedRequests.append(request)
                requestLock.unlock()
                windowRecordStore.setState(
                    RuntimeWindowMappingState(
                        windowRecordsByCGWindowID: [
                            cgWindowID: self.makeMainTableProjectionWindowRecord(
                                pid: pid,
                                cgWindowID: cgWindowID,
                                axWindowID: axWindowID
                            )
                        ],
                        currentAXToCG: [axWindowID: cgWindowID],
                        validCGWindowIDs: [cgWindowID],
                        lastAXWindowIDs: [axWindowID],
                        hasObservedAXWindowHandle: true
                    ),
                    for: pid
                )
                if request.target == .app(pid),
                   request.appID == appID,
                   request.priority == .high,
                   request.reasons == expectedReasons
                {
                    expectation.fulfill()
                }
                return .completedWithCurrentAppRepairEvidence([
                    RuntimeCurrentAppRepairEvidence(
                        appID: appID,
                        pid: pid,
                        appDirectoryEntries: [appDirectoryEntry],
                        currentAppWindowPayloadWasEmpty: false
                    )
                ])
            }
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        let waitResult = XCTWaiter.wait(
            for: [expectation],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .runtimeMaintenanceExecution
        )
        service.waitForMaintenanceQueueForTesting()

        let diagnostics = readModelStore.diagnostics()
        requestLock.lock()
        let finalExecutedRequests = executedRequests
        requestLock.unlock()
        let requestEvidence = finalExecutedRequests.map { request in
            [
                "id=\(request.id)",
                "target=\(request.target)",
                "appID=\(request.appID ?? "nil")",
                "priority=\(request.priority.rawValue)",
                "reasons=\(request.reasons.map(\.rawValue).sorted())",
                "state=\(request.state.rawValue)",
                "attempt=\(request.attempt)"
            ].joined(separator: " ")
        }
        XCTAssertEqual(
            waitResult,
            .completed,
            """
            unmetCondition=scheduledSearchCoverageRepairExecutesExactAppRequest \
            lastRequests=\(requestEvidence) \
            dirtyAppIDs=\(diagnostics.dirtyAppIDs.sorted()) \
            dirtyPIDs=\(diagnostics.dirtyPIDs.sorted()) \
            pendingScopes=\(diagnostics.pendingRepairScopes.sorted()) \
            hasCommittedSearchIndex=\(diagnostics.hasCommittedSearchIndex)
            """
        )
        XCTAssertEqual(finalExecutedRequests.count, 1)
        let executedRequest = try XCTUnwrap(finalExecutedRequests.first)
        XCTAssertEqual(executedRequest.target, .app(pid))
        XCTAssertEqual(executedRequest.appID, appID)
        XCTAssertEqual(executedRequest.priority, .high)
        XCTAssertEqual(executedRequest.reasons, expectedReasons)
        XCTAssertTrue(diagnostics.dirtyAppIDs.isEmpty)
        XCTAssertTrue(diagnostics.dirtyPIDs.isEmpty)
        XCTAssertTrue(diagnostics.dirtyCGWindowIDs.isEmpty)
        XCTAssertTrue(diagnostics.pendingRepairScopes.isEmpty)
        XCTAssertTrue(diagnostics.hasCommittedSearchIndex)

        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        let projection = try XCTUnwrap(searchRead.projection)
        XCTAssertEqual(searchRead.readiness, .committedGenerationValidated)
        XCTAssertEqual(searchRead.resultState, .committedGenerationResult)
        XCTAssertTrue(searchRead.committedIndexCoversCurrentGeneration)
        XCTAssertEqual(
            projection.windowEntries.map(\.windowID),
            [RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)]
        )
    }

    func testSearchFreshnessBarrierCommitsWhenMultiProcessRepairSelectsSiblingPID() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let selectedPID = runningApp.processIdentifier
        let requestPID: pid_t = selectedPID == 83_885 ? 83_886 : 83_885
        let selectedEntry = RuntimeAppDirectoryEntry(
            app: runningApp,
            activationRank: 0
        )
        let requestEntry = RuntimeAppDirectoryEntry(
            pid: requestPID,
            appID: appID,
            bundleIdentifier: runningApp.bundleIdentifier,
            localizedName: runningApp.localizedName,
            bundleURL: runningApp.bundleURL,
            launchDate: nil,
            activationRank: 1
        )
        let appDirectoryEntries = [selectedEntry, requestEntry]
        let cgWindowID = CGWindowID(240_171)
        let axWindowID = "ax:\(selectedPID):multi-process-search-barrier"
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                selectedPID: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: makeMainTableProjectionWindowRecord(
                            pid: selectedPID,
                            cgWindowID: cgWindowID,
                            axWindowID: axWindowID
                        )
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasRecordedWindowCollection: true,
                    hasObservedAXWindowHandle: true
                ),
                requestPID: RuntimeWindowMappingState(
                    hasRecordedWindowCollection: true
                )
            ]
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.markAppWindowsDirty(
            appID: appID,
            pid: requestPID,
            pendingScope: "appWindows:\(appID)"
        )
        let coordinator = RuntimeReconciliationCoordinator()
        coordinator.markAppDirty(
            appID: appID,
            pid: requestPID,
            reason: .axNotification,
            now: 10
        )
        let repairExecution = expectation(
            description:
                "unmetCondition=multiProcessRepairExecutesRequestedPID"
        )
        repairExecution.assertForOverFulfill = true
        let service = RuntimeProjectionService(
            label:
                "FlowTabTests.RuntimeProjectionService.MultiProcessSearchBarrier",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: coordinator
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            appDirectoryProvider: FixedRuntimeAppDirectoryProvider(
                entries: appDirectoryEntries
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                XCTAssertEqual(request.target, .app(requestPID))
                XCTAssertEqual(request.appID, appID)
                repairExecution.fulfill()
                return .completedWithCurrentAppRepairEvidence([
                    RuntimeCurrentAppRepairEvidence(
                        appID: appID,
                        pid: selectedPID,
                        appDirectoryEntries: appDirectoryEntries,
                        currentAppWindowPayloadWasEmpty: false,
                        authoritativeCGWindowIDs: [cgWindowID]
                    )
                ])
            }
        )
        let publication = expectation(
            forNotification: .runtimeCommittedSearchIndexDidUpdate,
            object: service
        )

        service.requestSearchIndexFreshnessBarrier(
            reason: .searchFreshnessBarrier
        )
        wait(
            for: [repairExecution, publication],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .committedSearchIndexPublication
        )
        service.waitForMaintenanceQueueForTesting()

        let diagnostics = readModelStore.diagnostics()
        XCTAssertTrue(diagnostics.dirtyAppIDs.isEmpty)
        XCTAssertTrue(diagnostics.dirtyPIDs.isEmpty)
        XCTAssertTrue(diagnostics.dirtyCGWindowIDs.isEmpty)
        XCTAssertTrue(diagnostics.pendingRepairScopes.isEmpty)
        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(
            searchRead.readiness,
            .committedGenerationValidated
        )
        XCTAssertEqual(
            searchRead.resultState,
            .committedGenerationResult
        )
        XCTAssertTrue(searchRead.committedIndexCoversCurrentGeneration)
    }

    func testCompleteMainTableCommitClearsEmptySpaceTopologyScope() {
        let store = RuntimeReadModelStore()
        let completePayload = RuntimeAppSwitcherProjectionPayload(
            apps: [],
            contextsByID: [:],
            hasCompleteWindowCoverage: true
        )
        let incompletePayload = RuntimeAppSwitcherProjectionPayload(
            apps: [],
            contextsByID: [:],
            hasCompleteWindowCoverage: false
        )
        _ = store.commitMainTableAppSwitcherProjectionPayload(
            completePayload,
            generatedAt: 10
        )
        store.markSpaceTopologyDirty(
            affectedCGWindowIDs: [],
            signatureSummary: "empty-topology-transition",
            pendingScope: "spaceTopology",
            generatedAt: 11
        )

        _ = store.commitMainTableAppSwitcherProjectionPayload(
            incompletePayload,
            clearsDirtyCGWindowIDs: [],
            generatedAt: 12
        )
        XCTAssertEqual(store.diagnostics().pendingRepairScopes, ["spaceTopology"])

        _ = store.commitMainTableAppSwitcherProjectionPayload(
            completePayload,
            clearsDirtyCGWindowIDs: [],
            generatedAt: 13
        )
        XCTAssertTrue(store.diagnostics().pendingRepairScopes.isEmpty)
    }
}
