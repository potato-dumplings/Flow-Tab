import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
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
}
