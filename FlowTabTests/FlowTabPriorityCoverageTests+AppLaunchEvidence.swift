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
        let monitor = ManualRuntimeAppWindowBindingMonitor()
        var evidence: [RuntimeAXWindowChangeEvidence] = []
        let coordinator = RuntimeAppWindowEvidenceCoordinator(
            monitor: monitor,
            currentPID: 99_999,
            readAccessibilityPermission: { true },
            bindingProvider: { [] },
            onAppWindowEvidence: { evidence.append($0) }
        )
        defer { coordinator.stop() }

        coordinator.start()
        coordinator.applicationDidLaunch(
            appID: "com.example.immediate",
            pid: 18_410
        )

        XCTAssertEqual(
            monitor.rebinds,
            [[
                RuntimeAXWindowObservationBinding(
                    appID: "com.example.immediate",
                    pid: 18_410,
                    expectedWindowCount: 0
                )
            ]]
        )

        monitor.sendWindowChanged(
            appID: "com.example.immediate",
            pid: 18_410,
            changeKind: .created
        )
        XCTAssertEqual(evidence.map(\.appID), ["com.example.immediate"])
        XCTAssertEqual(evidence.map(\.pid), [18_410])
        XCTAssertEqual(evidence.map(\.changeKinds), [[.created]])
    }
}

@MainActor
final class SpyAppWindowEvidenceCoordinator:
    RuntimeAppWindowEvidenceCoordinating
{
    var onApplicationDidLaunch: ((String, pid_t) -> Void)?
    var onApplicationDidTerminate: ((String, pid_t) -> Void)?
    private(set) var launchedApplications: [(appID: String, pid: pid_t)] = []
    private(set) var terminatedApplications: [(appID: String, pid: pid_t)] = []
    private(set) var startCallCount = 0
    private(set) var reconcileCallCount = 0
    private(set) var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func reconcileNow() {
        reconcileCallCount += 1
    }

    func applicationDidLaunch(appID: String, pid: pid_t) {
        onApplicationDidLaunch?(appID, pid)
        launchedApplications.append((appID, pid))
    }

    func applicationDidTerminate(appID: String, pid: pid_t) {
        onApplicationDidTerminate?(appID, pid)
        terminatedApplications.append((appID, pid))
    }

    func stop() {
        stopCallCount += 1
    }
}

@MainActor
private final class ManualRuntimeAppWindowBindingMonitor:
    RuntimeAXWindowChangeMonitoring
{
    var onAppWindowChanged: ((RuntimeAXWindowChangeEvidence) -> Void)?
    private(set) var rebinds: [[RuntimeAXWindowObservationBinding]] = []

    func rebind(_ bindings: [RuntimeAXWindowObservationBinding]) {
        rebinds.append(bindings)
    }

    func stop() {}

    func sendWindowChanged(
        appID: String,
        pid: pid_t,
        changeKind: RuntimeAXWindowChangeEvidence.ChangeKind
    ) {
        onAppWindowChanged?(
            RuntimeAXWindowChangeEvidence(
                appID: appID,
                pid: pid,
                generation: 1,
                source: .observedTransition,
                observedTransitionCount: 1,
                changeKinds: [changeKind],
                initialReadback: nil
            )
        )
    }
}
