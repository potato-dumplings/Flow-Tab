import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testHomeInitialProjectionBootstrapRequestsMaintenanceOnlyWhenProjectionIsMissing() {
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        let missingProjectionRead = HomeAppSummaryProjectionRead(
            summaries: [],
            freshness: nil,
            isProjectionBacked: false
        )
        let availableProjectionRead = HomeAppSummaryProjectionRead(
            summaries: [],
            freshness: nil,
            isProjectionBacked: true
        )

        XCTAssertTrue(
            HomeInitialRuntimeProjectionBootstrapper.requestIfNeeded(
                projectionRead: missingProjectionRead,
                currentAppSummaryCount: 0,
                from: runtimeProjectionService
            )
        )
        XCTAssertFalse(
            HomeInitialRuntimeProjectionBootstrapper.requestIfNeeded(
                projectionRead: availableProjectionRead,
                currentAppSummaryCount: 0,
                from: runtimeProjectionService
            )
        )
        XCTAssertFalse(
            HomeInitialRuntimeProjectionBootstrapper.requestIfNeeded(
                projectionRead: missingProjectionRead,
                currentAppSummaryCount: 1,
                from: runtimeProjectionService
            )
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.homeProjectionMissing]
        )
    }

    func testRuntimeProjectionServiceDoesNotDrainQueuedRepairsWithoutAccessibility() {
        let coordinator = RuntimeReconciliationCoordinator()
        let repairProvider = RuntimeProjectionRepairProvider(
            reconciliationCoordinator: coordinator
        )
        let lock = NSLock()
        var executionCount = 0
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AXUnavailableCentralGate",
            repairProvider: repairProvider,
            axWindowRepairAvailability: { false },
            reconciliationExecutor: { _, _ in
                lock.lock()
                executionCount += 1
                lock.unlock()
                return .completed
            }
        )
        let request = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .appLaunched,
            now: 10
        )

        let startedRequests = service.drainReadyReconciliationRequestsSynchronouslyForTesting(
            now: 10
        )

        lock.lock()
        let finalExecutionCount = executionCount
        lock.unlock()
        XCTAssertTrue(startedRequests.isEmpty)
        XCTAssertEqual(finalExecutionCount, 0)
        XCTAssertEqual(coordinator.readyRequests().map(\.id), [request.id])
    }
}
