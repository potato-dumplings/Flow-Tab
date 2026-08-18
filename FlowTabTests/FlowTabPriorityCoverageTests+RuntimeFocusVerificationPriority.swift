import ApplicationServices
import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeProjectionServiceAppliesVerifiedFocusAheadOfMaintenanceBacklog() async throws {
        let owner = RuntimeProjectionMaintenanceOwner(
            label: "FlowTabTests.RuntimeProjectionService.VerifiedFocusPriority"
        )
        defer { owner.cancelPendingPriorityWork() }
        let coordinator = RuntimeReconciliationCoordinator()
        let windowRecordStore = RuntimeWindowRecordStore()
        let pid = pid_t(18_408)
        let focusedCGWindowID = CGWindowID(240_301)
        let focusedAXWindow = AXUIElementCreateApplication(pid)
        let focusedAXWindowID = AXWindowInspectorForTesting.makeWindowID(
            pid: pid,
            index: 0
        )
        windowRecordStore.setState(
            RuntimeWindowMappingState(
                windowRecordsByCGWindowID: [
                    focusedCGWindowID: RuntimeWindowRecord(
                        cgWindowID: focusedCGWindowID,
                        stableWindowID: "cg:\(pid):\(focusedCGWindowID)",
                        firstSeenAt: 1
                    )
                ],
                validCGWindowIDs: [focusedCGWindowID]
            ),
            for: pid
        )
        AXLiveWindowRegistry.shared.replaceWindows(
            forPID: pid,
            with: [focusedAXWindow]
        )
        defer { AXLiveWindowRegistry.shared.remove(pid: pid) }

        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.VerifiedFocusPriority",
            maintenanceOwner: owner,
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: coordinator
            ),
            reconciliationExecutor: { _, _ in .completed }
        )
        let activeStarted = expectation(
            description: "unmetCondition=activeMaintenanceStarted"
        )
        let backlogObserved = expectation(
            description: "unmetCondition=backlogObservedVerifiedFocus"
        )
        let releaseActive = DispatchSemaphore(value: 0)
        let probe = RuntimeFocusVerificationPriorityProbe(
            windowRecordStore: windowRecordStore,
            pid: pid,
            cgWindowID: focusedCGWindowID
        )

        owner.enqueue {
            activeStarted.fulfill()
            releaseActive.wait()
        }
        owner.enqueue {
            probe.recordBacklogObservation()
            backlogObserved.fulfill()
        }
        await fulfillment(
            of: [activeStarted],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        service.signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: "com.example.priority-focus",
                windowID: "cg:\(pid):\(focusedCGWindowID)",
                ownerPID: pid,
                targetCGWindowID: focusedCGWindowID,
                focusedCGWindowID: focusedCGWindowID,
                focusedAXWindow: focusedAXWindow,
                title: "Priority Focus Window",
                frame: CGRect(x: 40, y: 50, width: 720, height: 520),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )
        )
        releaseActive.signal()
        await fulfillment(
            of: [backlogObserved],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        service.waitForMaintenanceQueueForTesting()

        XCTAssertTrue(probe.backlogObservedVerifiedFocus)
        let mappingState = try XCTUnwrap(windowRecordStore.state(for: pid))
        let record = try XCTUnwrap(
            mappingState.windowRecordsByCGWindowID[focusedCGWindowID]
        )
        XCTAssertEqual(record.bindingConfidence, .exact)
        XCTAssertEqual(record.lastConfirmationSource, .verifiedFocusReadback)
        XCTAssertEqual(record.lastExactAXWindowID, focusedAXWindowID)
        XCTAssertEqual(
            mappingState.currentAXToCG[focusedAXWindowID],
            focusedCGWindowID
        )
        XCTAssertEqual(owner.pendingPriorityWorkCount, 0)
    }
}

private final class RuntimeFocusVerificationPriorityProbe: @unchecked Sendable {
    private let windowRecordStore: RuntimeWindowRecordStore
    private let pid: pid_t
    private let cgWindowID: CGWindowID
    private let lock = NSLock()
    private var observedVerifiedFocus = false

    init(
        windowRecordStore: RuntimeWindowRecordStore,
        pid: pid_t,
        cgWindowID: CGWindowID
    ) {
        self.windowRecordStore = windowRecordStore
        self.pid = pid
        self.cgWindowID = cgWindowID
    }

    func recordBacklogObservation() {
        let source = windowRecordStore.state(for: pid)?
            .windowRecordsByCGWindowID[cgWindowID]?
            .lastConfirmationSource
        lock.lock()
        observedVerifiedFocus = source == .verifiedFocusReadback
        lock.unlock()
    }

    var backlogObservedVerifiedFocus: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedVerifiedFocus
    }
}
