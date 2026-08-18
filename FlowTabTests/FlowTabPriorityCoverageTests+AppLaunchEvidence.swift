import ApplicationServices
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeProjectionServiceReconcilesLaunchedAppAgainFromWindowEvidence() {
        let reconciliationCoordinator = RuntimeReconciliationCoordinator()
        let windowRecordStore = RuntimeWindowRecordStore()
        let requestLock = NSLock()
        var executedRequests: [RuntimeReconciliationRequest] = []
        let initialRepair = expectation(
            description: "unmetCondition=initialAppLaunchMaintenanceExecuted"
        )
        initialRepair.assertForOverFulfill = true
        let windowEvidenceRepair = expectation(
            description: "unmetCondition=axWindowEvidenceMaintenanceExecuted"
        )
        windowEvidenceRepair.assertForOverFulfill = true
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AppLaunchWindowEvidence",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: reconciliationCoordinator
            ),
            reconciliationExecutor: { request, _ in
                requestLock.lock()
                executedRequests.append(request)
                let executionCount = executedRequests.count
                requestLock.unlock()
                if executionCount == 1 {
                    initialRepair.fulfill()
                } else if executionCount == 2 {
                    windowEvidenceRepair.fulfill()
                }
                return .completed
            }
        )

        service.signalAppLaunched(
            appID: "com.example.launch-evidence",
            pid: 18_408
        )
        wait(
            for: [initialRepair],
            timeout: FlowTabPriorityCoverageWatchdogPolicy.runtimeMaintenanceExecution
        )
        service.waitForMaintenanceQueueForTesting()

        requestLock.lock()
        let requestsBeforeWindowEvidence = executedRequests
        requestLock.unlock()
        XCTAssertEqual(requestsBeforeWindowEvidence.count, 1)
        XCTAssertEqual(requestsBeforeWindowEvidence.first?.reasons, Set([.appLaunched]))

        service.signalAppWindowsChanged(
            appID: "com.example.launch-evidence",
            pid: 18_408
        )
        wait(
            for: [windowEvidenceRepair],
            timeout: FlowTabPriorityCoverageWatchdogPolicy.runtimeMaintenanceExecution
        )
        service.waitForMaintenanceQueueForTesting()

        requestLock.lock()
        let finalRequests = executedRequests
        requestLock.unlock()
        XCTAssertEqual(finalRequests.map(\.target), [.app(18_408), .app(18_408)])
        XCTAssertEqual(
            finalRequests.map(\.reasons),
            [Set([.appLaunched]), Set([.axNotification])]
        )
    }

    @MainActor
    func testAppLaunchWindowEvidenceUsesImmediateObserverInstallation() {
        let monitor = ManualAppLaunchWindowMonitor(installEvidence: [.installed])
        let retryScheduler = ManualAppLaunchObservationRetryScheduler()
        var windowChangeSignals: [(String, pid_t)] = []
        var destroyedSignals: [(String, pid_t, String)] = []
        let coordinator = RuntimeAppLaunchWindowEvidenceCoordinator(
            monitor: monitor,
            retryScheduler: retryScheduler,
            currentPID: 99_999,
            onAppWindowChanged: { windowChangeSignals.append(($0, $1)) },
            onAXWindowDestroyed: { destroyedSignals.append(($0, $1, $2)) }
        )

        coordinator.prepareObservation(
            appID: "com.example.immediate",
            pid: 18_410
        )

        XCTAssertEqual(monitor.observations.map(\.appID), ["com.example.immediate"])
        XCTAssertEqual(monitor.observations.map(\.pid), [18_410])
        XCTAssertTrue(retryScheduler.entries.isEmpty)

        monitor.sendWindowChanged(appID: "com.example.immediate", pid: 18_410)
        monitor.sendWindowDestroyed(
            appID: "com.example.immediate",
            pid: 18_410,
            axWindowID: "ax:18410:1"
        )
        XCTAssertEqual(windowChangeSignals.map(\.0), ["com.example.immediate"])
        XCTAssertEqual(windowChangeSignals.map(\.1), [18_410])
        XCTAssertEqual(destroyedSignals.map(\.0), ["com.example.immediate"])
        XCTAssertEqual(destroyedSignals.map(\.1), [18_410])
        XCTAssertEqual(destroyedSignals.map(\.2), ["ax:18410:1"])
    }

    @MainActor
    func testAppLaunchWindowEvidenceDeliversEarlyConsecutiveAXTransitions() {
        let monitor = ManualAppLaunchWindowMonitor(
            installEvidence: [.installed]
        )
        var changedEvents: [(String, pid_t)] = []
        let pid: pid_t = 18_410
        let coordinator = RuntimeAppLaunchWindowEvidenceCoordinator(
            monitor: monitor,
            retryScheduler: ManualAppLaunchObservationRetryScheduler(),
            currentPID: 99_999,
            onAppWindowChanged: { changedEvents.append(($0, $1)) },
            onAXWindowDestroyed: { _, _, _ in }
        )
        coordinator.prepareObservation(
            appID: "com.example.early-events",
            pid: pid
        )
        monitor.sendWindowChanged(
            appID: "com.example.early-events",
            pid: pid
        )
        monitor.sendWindowChanged(
            appID: "com.example.early-events",
            pid: pid
        )

        XCTAssertEqual(changedEvents.map(\.0), [
            "com.example.early-events",
            "com.example.early-events"
        ])
        XCTAssertEqual(changedEvents.map(\.1), [pid, pid])
    }

    @MainActor
    func testAppLaunchWindowEvidenceRetriesInstallationThenRequestsReadback() {
        let monitor = ManualAppLaunchWindowMonitor(
            installEvidence: [
                .unavailable(error: .cannotComplete),
                .installed
            ]
        )
        let retryScheduler = ManualAppLaunchObservationRetryScheduler()
        var windowChangeSignals: [(String, pid_t)] = []
        let coordinator = RuntimeAppLaunchWindowEvidenceCoordinator(
            monitor: monitor,
            retryScheduler: retryScheduler,
            currentPID: 99_999,
            onAppWindowChanged: { windowChangeSignals.append(($0, $1)) },
            onAXWindowDestroyed: { _, _, _ in }
        )

        coordinator.prepareObservation(
            appID: "com.example.delayed",
            pid: 18_411
        )

        XCTAssertEqual(monitor.observations.count, 1)
        XCTAssertEqual(retryScheduler.entries.count, 1)
        XCTAssertTrue(windowChangeSignals.isEmpty)
        retryScheduler.fireEntry(at: 0)

        XCTAssertEqual(monitor.observations.count, 2)
        XCTAssertEqual(windowChangeSignals.map(\.0), ["com.example.delayed"])
        XCTAssertEqual(windowChangeSignals.map(\.1), [18_411])

        retryScheduler.fireEntry(at: 0)
        XCTAssertEqual(monitor.observations.count, 2)
        XCTAssertEqual(windowChangeSignals.count, 1)
    }

    @MainActor
    func testAppLaunchWindowEvidenceCancelsRetryAtProcessTermination() {
        let monitor = ManualAppLaunchWindowMonitor(
            installEvidence: [.unavailable(error: .cannotComplete)]
        )
        let retryScheduler = ManualAppLaunchObservationRetryScheduler()
        var windowChangeSignals: [(String, pid_t)] = []
        let coordinator = RuntimeAppLaunchWindowEvidenceCoordinator(
            monitor: monitor,
            retryScheduler: retryScheduler,
            currentPID: 99_999,
            onAppWindowChanged: { windowChangeSignals.append(($0, $1)) },
            onAXWindowDestroyed: { _, _, _ in }
        )

        coordinator.prepareObservation(
            appID: "com.example.terminated",
            pid: 18_412
        )
        coordinator.cancelObservation(
            appID: "com.example.terminated",
            pid: 18_412
        )

        XCTAssertTrue(retryScheduler.entries[0].token.isCancelled)
        XCTAssertEqual(monitor.stoppedPIDs, [18_412])
        retryScheduler.fireEntry(at: 0)
        XCTAssertEqual(monitor.observations.count, 1)
        XCTAssertTrue(windowChangeSignals.isEmpty)
    }

    @MainActor
    func testAppLaunchWindowEvidenceIgnoresStaleTerminationForReusedPID() {
        let monitor = ManualAppLaunchWindowMonitor(
            installEvidence: [.installed, .installed]
        )
        let coordinator = RuntimeAppLaunchWindowEvidenceCoordinator(
            monitor: monitor,
            retryScheduler: ManualAppLaunchObservationRetryScheduler(),
            currentPID: 99_999,
            onAppWindowChanged: { _, _ in },
            onAXWindowDestroyed: { _, _, _ in }
        )
        let reusedPID: pid_t = 18_413

        coordinator.prepareObservation(appID: "com.example.first", pid: reusedPID)
        coordinator.prepareObservation(appID: "com.example.second", pid: reusedPID)
        coordinator.cancelObservation(appID: "com.example.first", pid: reusedPID)

        XCTAssertTrue(monitor.stoppedPIDs.isEmpty)

        coordinator.cancelObservation(appID: "com.example.second", pid: reusedPID)
        XCTAssertEqual(monitor.stoppedPIDs, [reusedPID])
    }

    @MainActor
    func testAppLaunchWindowEvidenceCancelsPendingRetryWhenCoordinatorStops() {
        let monitor = ManualAppLaunchWindowMonitor(
            installEvidence: [.unavailable(error: .cannotComplete)]
        )
        let retryScheduler = ManualAppLaunchObservationRetryScheduler()
        let coordinator = RuntimeAppLaunchWindowEvidenceCoordinator(
            monitor: monitor,
            retryScheduler: retryScheduler,
            currentPID: 99_999,
            onAppWindowChanged: { _, _ in },
            onAXWindowDestroyed: { _, _, _ in }
        )

        coordinator.prepareObservation(appID: "com.example.shutdown", pid: 18_414)
        coordinator.stop()

        XCTAssertTrue(retryScheduler.entries[0].token.isCancelled)
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    @MainActor
    func testAppLaunchWindowEvidenceIgnoresSupersededRetryGeneration() {
        let monitor = ManualAppLaunchWindowMonitor(
            installEvidence: [
                .unavailable(error: .cannotComplete),
                .installed
            ]
        )
        let retryScheduler = ManualAppLaunchObservationRetryScheduler()
        var windowChangeSignals: [(String, pid_t)] = []
        let coordinator = RuntimeAppLaunchWindowEvidenceCoordinator(
            monitor: monitor,
            retryScheduler: retryScheduler,
            currentPID: 99_999,
            onAppWindowChanged: { windowChangeSignals.append(($0, $1)) },
            onAXWindowDestroyed: { _, _, _ in }
        )

        coordinator.prepareObservation(appID: "com.example.first", pid: 18_413)
        coordinator.prepareObservation(appID: "com.example.second", pid: 18_413)

        XCTAssertTrue(retryScheduler.entries[0].token.isCancelled)
        retryScheduler.fireEntry(at: 0)
        XCTAssertEqual(monitor.observations.map(\.appID), [
            "com.example.first",
            "com.example.second"
        ])
        XCTAssertTrue(windowChangeSignals.isEmpty)
    }
}

@MainActor
final class SpyAppLaunchWindowEvidenceCoordinator:
    RuntimeAppLaunchWindowEvidenceCoordinating
{
    var onPrepareObservation: ((String, pid_t) -> Void)?
    private(set) var preparedObservations: [(appID: String, pid: pid_t)] = []
    private(set) var cancelledObservations: [(appID: String, pid: pid_t)] = []
    private(set) var stopCallCount = 0

    func prepareObservation(appID: String, pid: pid_t) {
        onPrepareObservation?(appID, pid)
        preparedObservations.append((appID, pid))
    }

    func cancelObservation(appID: String, pid: pid_t) {
        cancelledObservations.append((appID, pid))
    }

    func stop() {
        stopCallCount += 1
    }
}

@MainActor
private final class ManualAppLaunchWindowMonitor: RuntimeAXWindowChangeMonitoring {
    var onAppWindowChanged: ((RuntimeAXWindowChangeEvidence) -> Void)?
    var onAXWindowDestroyed: ((String, pid_t, String) -> Void)?
    private var installEvidence: [RuntimeAXWindowObservationInstallEvidence]
    private(set) var observations: [(appID: String, pid: pid_t)] = []
    private(set) var stoppedPIDs: [pid_t] = []
    private(set) var stopCallCount = 0

    init(installEvidence: [RuntimeAXWindowObservationInstallEvidence]) {
        self.installEvidence = installEvidence
    }

    func observe(
        appID: String,
        pid: pid_t
    ) -> RuntimeAXWindowObservationInstallEvidence {
        observations.append((appID, pid))
        return installEvidence.isEmpty ? .installed : installEvidence.removeFirst()
    }

    func stopObserving(pid: pid_t) {
        stoppedPIDs.append(pid)
    }

    func stop() {
        stopCallCount += 1
    }

    func sendWindowChanged(appID: String, pid: pid_t) {
        onAppWindowChanged?(
            RuntimeAXWindowChangeEvidence(
                appID: appID,
                pid: pid,
                generation: 1,
                source: .observedTransition,
                observedTransitionCount: 1,
                initialReadback: nil
            )
        )
    }

    func sendWindowDestroyed(appID: String, pid: pid_t, axWindowID: String) {
        onAXWindowDestroyed?(appID, pid, axWindowID)
    }
}

@MainActor
private final class ManualAppLaunchObservationRetryToken:
    RuntimeAppLaunchObservationRetryCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
private final class ManualAppLaunchObservationRetryScheduler:
    RuntimeAppLaunchObservationRetryScheduling
{
    struct Entry {
        let token: ManualAppLaunchObservationRetryToken
        let action: @MainActor @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []

    func schedule(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAppLaunchObservationRetryCancellable {
        let token = ManualAppLaunchObservationRetryToken()
        entries.append(Entry(token: token, action: action))
        return token
    }

    func fireEntry(at index: Int) {
        entries[index].action()
    }
}
