import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testTransientRepairObservationPolicyRepeatsLastNamedCadence() {
        let policy = RuntimeTransientRepairObservationPolicy(
            intervals: [0.1, 0.3, 0.8]
        )

        XCTAssertEqual(policy.interval(forAttempt: 1), 0.1)
        XCTAssertEqual(policy.interval(forAttempt: 2), 0.3)
        XCTAssertEqual(policy.interval(forAttempt: 3), 0.8)
        XCTAssertEqual(policy.interval(forAttempt: 4), 0.8)
        XCTAssertEqual(policy.watchdogInterval, 30)
    }
    func testRuntimeProjectionServiceInitialReadbackCompletesWithoutSchedulingObservation() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        let service = makeTransientRepairObservationService(
            coordinator: coordinator,
            scheduler: scheduler
        ) { _, _ in
            .completed
        }
        let dirty = coordinator.markAppDirty(
            appID: "com.example.initial-readback",
            pid: 18_419,
            reason: .axNotification,
            now: 10
        )
        XCTAssertEqual(
            service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10)
                .map(\.id),
            [dirty.id]
        )
        XCTAssertTrue(scheduler.entries.isEmpty)
        XCTAssertFalse(coordinator.hasPendingRequests())
    }
    func testRuntimeProjectionServiceConditionObservationActivelyRequestsReadback() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        let lock = NSLock()
        var executionCount = 0
        let service = makeTransientRepairObservationService(
            coordinator: coordinator,
            scheduler: scheduler
        ) { _, _ in
            lock.lock()
            executionCount += 1
            let currentCount = executionCount
            lock.unlock()
            return currentCount == 1
                ? .transientEmptyCurrentAppWindowPayload
                : .completed
        }
        let dirty = coordinator.markAppDirty(
            appID: "com.example.poll-readback",
            pid: 18_420,
            reason: .axNotification,
            now: 10
        )
        XCTAssertEqual(
            service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10)
                .map(\.id),
            [dirty.id]
        )
        XCTAssertEqual(scheduler.entries.map(\.interval), [30, 0.1])
        XCTAssertTrue(coordinator.readyRequests().isEmpty)

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()
        lock.lock()
        let countBeforeReadback = executionCount
        lock.unlock()
        XCTAssertEqual(countBeforeReadback, 1)
        scheduler.fireFirstEntry(after: 0.1)
        service.waitForMaintenanceQueueForTesting()

        lock.lock()
        let finalExecutionCount = executionCount
        lock.unlock()
        XCTAssertEqual(finalExecutionCount, 2)
        XCTAssertFalse(coordinator.hasPendingRequests())
    }
    func testRuntimeProjectionServiceWindowEvidenceCancelsPollAndRequestsReadbackImmediately() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        let lock = NSLock()
        var executionCount = 0
        let service = makeTransientRepairObservationService(
            coordinator: coordinator,
            scheduler: scheduler
        ) { _, _ in
            lock.lock()
            executionCount += 1
            let currentCount = executionCount
            lock.unlock()
            return currentCount == 1
                ? .transientEmptyCurrentAppWindowPayload
                : .completed
        }
        let appID = "com.example.event-readback"
        let pid: pid_t = 18_421
        coordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10)
        service.signalAppWindowsChanged(appID: appID, pid: pid)
        service.waitForMaintenanceQueueForTesting()

        XCTAssertTrue(scheduler.entries.allSatisfy(\.token.isCancelled))
        lock.lock()
        let countAfterEvidence = executionCount
        lock.unlock()
        XCTAssertEqual(countAfterEvidence, 2)
        XCTAssertFalse(coordinator.hasPendingRequests())

        scheduler.fireFirstEntry(after: 0.1)
        service.waitForMaintenanceQueueForTesting()
        lock.lock()
        let countAfterStaleCallback = executionCount
        lock.unlock()
        XCTAssertEqual(countAfterStaleCallback, 2)
    }
    func testRuntimeProjectionServiceIgnoresOutOfOrderPollAfterNewEvidenceGeneration() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        let lock = NSLock()
        var executionCount = 0
        let service = makeTransientRepairObservationService(
            coordinator: coordinator,
            scheduler: scheduler
        ) { _, _ in
            lock.lock()
            executionCount += 1
            let currentCount = executionCount
            lock.unlock()
            return currentCount < 3
                ? .transientEmptyCurrentAppWindowPayload
                : .completed
        }
        let appID = "com.example.out-of-order"
        let pid: pid_t = 18_422
        coordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10)
        service.signalAppWindowsChanged(appID: appID, pid: pid)
        service.waitForMaintenanceQueueForTesting()
        XCTAssertEqual(scheduler.entries.map(\.interval), [30, 0.1, 30, 0.3])

        scheduler.fireFirstEntry(after: 0.1)
        service.waitForMaintenanceQueueForTesting()
        lock.lock()
        let countAfterStalePoll = executionCount
        lock.unlock()
        XCTAssertEqual(countAfterStalePoll, 2)

        scheduler.fireFirstEntry(after: 0.3)
        service.waitForMaintenanceQueueForTesting()
        lock.lock()
        let finalExecutionCount = executionCount
        lock.unlock()
        XCTAssertEqual(finalExecutionCount, 3)
        XCTAssertFalse(coordinator.hasPendingRequests())
    }
    func testRuntimeProjectionServiceTerminationCancelsConditionObservation() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        let lock = NSLock()
        var executionCount = 0
        let service = makeTransientRepairObservationService(
            coordinator: coordinator,
            scheduler: scheduler
        ) { _, _ in
            lock.lock()
            executionCount += 1
            lock.unlock()
            return .transientEmptyCurrentAppWindowPayload
        }
        let appID = "com.example.terminated-observation"
        let pid: pid_t = 18_423
        coordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            now: 10
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10)

        service.signalAppTerminated(appID: appID, pid: pid)
        XCTAssertTrue(scheduler.entries.allSatisfy(\.token.isCancelled))

        scheduler.fireFirstEntry(after: 0.1)
        service.waitForMaintenanceQueueForTesting()
        lock.lock()
        let finalExecutionCount = executionCount
        lock.unlock()
        XCTAssertEqual(finalExecutionCount, 1)
        XCTAssertFalse(coordinator.hasPendingRequests())
    }

    func testRuntimeProjectionServiceStaleTerminationPreservesReusedPIDObservation() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        let windowRecordStore = RuntimeWindowRecordStore()
        let pid = pid_t(18_424)
        windowRecordStore.setState(RuntimeWindowMappingState(), for: pid)
        let lock = NSLock()
        var executionCount = 0
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.ReusedPIDObservation",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: coordinator
            ),
            transientRepairObservationScheduler: scheduler,
            reconciliationExecutor: { _, _ in
                lock.lock()
                executionCount += 1
                let currentCount = executionCount
                lock.unlock()
                return currentCount == 1
                    ? .transientEmptyCurrentAppWindowPayload
                    : .completed
            }
        )
        coordinator.markAppDirty(
            appID: "com.example.reused-pid",
            pid: pid,
            reason: .appLaunched,
            now: 10
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(now: 10)

        service.signalAppTerminated(
            appID: "com.example.previous-pid-owner",
            pid: pid
        )

        XCTAssertTrue(scheduler.entries.allSatisfy { !$0.token.isCancelled })
        XCTAssertNotNil(windowRecordStore.state(for: pid))
        XCTAssertEqual(coordinator.pendingAppID(pid: pid), "com.example.reused-pid")

        scheduler.fireFirstEntry(after: 0.1)
        service.waitForMaintenanceQueueForTesting()

        XCTAssertFalse(coordinator.hasPendingRequests())
    }

    func testRuntimeProjectionServiceLifetimeCancelsConditionObservation() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        var service: RuntimeProjectionService? = makeTransientRepairObservationService(
            coordinator: coordinator,
            scheduler: scheduler
        ) { _, _ in
            .transientEmptyCurrentAppWindowPayload
        }
        coordinator.markAppDirty(
            appID: "com.example.service-lifetime",
            pid: 18_424,
            reason: .axNotification,
            now: 10
        )

        _ = service?.drainReadyReconciliationRequestsSynchronouslyForTesting(
            now: 10
        )
        XCTAssertTrue(scheduler.entries.allSatisfy { !$0.token.isCancelled })
        weak var weakService = service

        service = nil

        XCTAssertNil(weakService)
        XCTAssertTrue(scheduler.entries.allSatisfy(\.token.isCancelled))
    }

    func testRuntimeProjectionServiceWatchdogTerminatesWithIncompleteEvidence() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        let lock = NSLock()
        var executionCount = 0
        let service = makeTransientRepairObservationService(
            coordinator: coordinator,
            scheduler: scheduler,
            policy: RuntimeTransientRepairObservationPolicy(
                intervals: [0.1],
                watchdogInterval: 2
            )
        ) { _, _ in
            lock.lock()
            executionCount += 1
            lock.unlock()
            return .transientEmptyCurrentAppWindowPayload
        }
        coordinator.markAppDirty(
            appID: "com.example.observation-watchdog",
            pid: 18_425,
            reason: .axNotification,
            now: 10
        )
        _ = service.drainReadyReconciliationRequestsSynchronouslyForTesting(
            now: 10
        )

        XCTAssertEqual(scheduler.entries.map(\.interval), [2, 0.1])
        scheduler.fireFirstEntry(after: 2)
        service.waitForMaintenanceQueueForTesting()

        XCTAssertFalse(coordinator.hasPendingRequests())
        XCTAssertTrue(scheduler.entries.allSatisfy(\.token.isCancelled))

        scheduler.fireFirstEntry(after: 0.1)
        service.waitForMaintenanceQueueForTesting()
        lock.lock()
        let finalExecutionCount = executionCount
        lock.unlock()
        XCTAssertEqual(finalExecutionCount, 1)
    }

    private func makeTransientRepairObservationService(
        coordinator: RuntimeReconciliationCoordinator,
        scheduler: ManualTransientRepairObservationScheduler,
        policy: RuntimeTransientRepairObservationPolicy = .standard,
        executor: @escaping RuntimeProjectionReconciliationExecutor
    ) -> RuntimeProjectionService {
        RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.TransientRepairObservation",
            repairProvider: RuntimeProjectionRepairProvider(
                reconciliationCoordinator: coordinator
            ),
            transientRepairObservationScheduler: scheduler,
            transientRepairObservationPolicy: policy,
            reconciliationExecutor: executor
        )
    }
}

final class ManualTransientRepairObservationToken:
    RuntimeTransientRepairObservationCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

final class ManualTransientRepairObservationScheduler:
    RuntimeTransientRepairObservationScheduling
{
    struct Entry {
        let interval: TimeInterval
        let queue: DispatchQueue
        let token: ManualTransientRepairObservationToken
        let action: @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []

    func schedule(
        after interval: TimeInterval,
        on queue: DispatchQueue,
        _ action: @escaping @Sendable () -> Void
    ) -> any RuntimeTransientRepairObservationCancellable {
        let token = ManualTransientRepairObservationToken()
        entries.append(
            Entry(
                interval: interval,
                queue: queue,
                token: token,
                action: action
            )
        )
        return token
    }

    func fireEntry(at index: Int) {
        let entry = entries[index]
        entry.queue.async(execute: entry.action)
    }

    func fireFirstEntry(after interval: TimeInterval) {
        guard let index = entries.firstIndex(where: { $0.interval == interval }) else {
            XCTFail("No scheduled transient-repair entry after \(interval) seconds")
            return
        }
        fireEntry(at: index)
    }
}
