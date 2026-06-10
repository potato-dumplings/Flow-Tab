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

    func testRuntimeSnapshotServiceSignalsAppWindowChangesToCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let service = RuntimeSnapshotService(
            label: "FlowTabTests.RuntimeSnapshotService.AppWindowSignal",
            snapshotProvider: provider
        )

        service.signalAppWindowsChanged(appID: "com.example.editor", pid: 18_405)
        _ = service.lightweightAppSnapshot()

        let request = try XCTUnwrap(
            coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).first {
                $0.target == .app(18_405)
            }
        )
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.reasons, Set([.axNotification]))
        XCTAssertEqual(request.state, .pending)
    }
}
