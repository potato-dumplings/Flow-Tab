import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
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
        XCTAssertEqual(retry.state, .waitingRetry)
        XCTAssertEqual(retry.attempt, 1)
        XCTAssertEqual(retry.notBefore, 11.1, accuracy: 0.0001)
        XCTAssertTrue(coordinator.readyRequests(now: 11.09).isEmpty)
        XCTAssertEqual(coordinator.readyRequests(now: 11.1).map(\.id), [retry.id])

        coordinator.completeRequest(id: retry.id)
        XCTAssertTrue(coordinator.readyRequests(now: 12).isEmpty)
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

    func testRuntimeSnapshotServiceDrainsAppWindowChangesThroughCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeSnapshotService(
            label: "FlowTabTests.RuntimeSnapshotService.AppWindowSignal",
            snapshotProvider: provider,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalAppWindowsChanged(appID: "com.example.editor", pid: 18_405)
        _ = service.lightweightAppSnapshot()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.reasons, Set([.axNotification]))
        XCTAssertEqual(request.state, .inFlight)
        XCTAssertTrue(coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).isEmpty)
    }

    func testRuntimeSnapshotServiceDrainsVerifiedFocusThroughCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeSnapshotService(
            label: "FlowTabTests.RuntimeSnapshotService.VerifiedFocusSignal",
            snapshotProvider: provider,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalWindowFocusVerified(appID: "com.example.editor", pid: 18_405)
        _ = service.lightweightAppSnapshot()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.target, .app(18_405))
        XCTAssertEqual(request.reasons, Set([.activationVerified]))
        XCTAssertEqual(request.state, .inFlight)
        XCTAssertTrue(coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).isEmpty)
    }

    func testRuntimeSnapshotServiceSchedulesRetryWhenDrainSeesTransientEmptyAXSnapshot() throws {
        let coordinator = RuntimeReconciliationCoordinator(
            retryPolicy: RuntimeReconciliationRetryPolicy(delays: [0.1])
        )
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let service = RuntimeSnapshotService(
            label: "FlowTabTests.RuntimeSnapshotService.TransientAXRetry",
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
}
