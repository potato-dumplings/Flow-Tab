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

    func testRuntimeReconciliationCoordinatorMarksVerifiedFocusReadbackAffectedWindows() throws {
        let coordinator = RuntimeReconciliationCoordinator()

        let request = coordinator.markWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: "com.example.editor",
                windowID: "cg:18405:240001",
                ownerPID: 18_405,
                targetCGWindowID: 240_001,
                focusedCGWindowID: 240_002,
                title: "Requested Window",
                frame: CGRect(x: 10, y: 20, width: 800, height: 600),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            ),
            now: 10
        )

        XCTAssertEqual(request.target, .app(18_405))
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.reasons, Set([.activationVerified]))
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

    func testRuntimeSnapshotServiceDrainsSpaceTopologySignalThroughCoordinator() throws {
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
        let service = RuntimeSnapshotService(
            label: "FlowTabTests.RuntimeSnapshotService.SpaceTopologySignal",
            snapshotProvider: provider,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalSpaceTopologyChanged()
        _ = service.lightweightAppSnapshot()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.target, .spaceTopology)
        XCTAssertEqual(request.reasons, Set([.spaceTopologyChanged]))
        XCTAssertEqual(request.affectedCGWindowIDs, [affectedWindowID])
        XCTAssertEqual(request.state, .inFlight)
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

    func testRuntimeSnapshotServiceDrainsLaunchedAppThroughCoordinator() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let provider = RuntimeSnapshotProvider(reconciliationCoordinator: coordinator)
        let lock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let service = RuntimeSnapshotService(
            label: "FlowTabTests.RuntimeSnapshotService.AppLaunchSignal",
            snapshotProvider: provider,
            reconciliationExecutor: { request, _ in
                lock.lock()
                executedRequests.append(request)
                lock.unlock()
                return .completed
            }
        )

        service.signalAppLaunched(appID: "com.example.new", pid: 18_407)
        _ = service.lightweightAppSnapshot()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.target, .app(18_407))
        XCTAssertEqual(request.appID, "com.example.new")
        XCTAssertEqual(request.reasons, Set([.appLaunched]))
        XCTAssertEqual(request.state, .inFlight)
        XCTAssertTrue(coordinator.readyRequests(now: Date.timeIntervalSinceReferenceDate).isEmpty)
    }

    func testRuntimeSnapshotServiceClearsTerminatedAppRuntimeState() {
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
        let service = RuntimeSnapshotService(
            label: "FlowTabTests.RuntimeSnapshotService.AppTerminated",
            snapshotProvider: provider
        )

        service.signalAppTerminated(appID: "com.example.terminated", pid: pid)
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 11)

        XCTAssertNil(provider.windowMappingStateByPID[pid])
        XCTAssertFalse(coordinator.readyRequests(now: 11).contains { $0.id == request.id })
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

        service.signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: "com.example.editor",
                windowID: "cg:18405:240001",
                ownerPID: 18_405,
                targetCGWindowID: 240_001,
                focusedCGWindowID: 240_001,
                title: "Verified Window",
                frame: CGRect(x: 10, y: 20, width: 800, height: 600),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )
        )
        _ = service.lightweightAppSnapshot()

        let request = try XCTUnwrap(executedRequests.first)
        XCTAssertEqual(request.appID, "com.example.editor")
        XCTAssertEqual(request.target, .app(18_405))
        XCTAssertEqual(request.reasons, Set([.activationVerified]))
        XCTAssertEqual(request.affectedCGWindowIDs, Set<CGWindowID>([240_001]))
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
