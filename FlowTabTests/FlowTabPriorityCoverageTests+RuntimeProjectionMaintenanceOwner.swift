import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeProjectionMaintenanceOwnerDrainsPriorityFIFOAfterActiveWorkBeforeBacklog() async {
        let owner = RuntimeProjectionMaintenanceOwner(
            label: "FlowTabTests.RuntimeProjectionMaintenanceOwner.FIFO"
        )
        defer { owner.cancelPendingPriorityWork() }
        let recorder = RuntimeProjectionMaintenanceEventRecorder()
        let activeStarted = expectation(
            description: "unmetCondition=activeMaintenanceStarted"
        )
        let releaseActive = DispatchSemaphore(value: 0)
        let launchApplied = expectation(
            description: "unmetCondition=priorityLaunchApplied"
        )
        let terminationApplied = expectation(
            description: "unmetCondition=priorityTerminationApplied"
        )
        let duplicateTerminationApplied = expectation(
            description: "unmetCondition=duplicatePriorityTerminationApplied"
        )
        let backlogApplied = expectation(
            description: "unmetCondition=normalBacklogApplied"
        )

        owner.enqueue {
            activeStarted.fulfill()
            releaseActive.wait()
            recorder.append("active")
        }
        owner.enqueue {
            recorder.append("backlog")
            backlogApplied.fulfill()
        }
        await fulfillment(
            of: [activeStarted],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        let launchGeneration = owner.enqueuePriority { generation in
            recorder.append("launch:\(generation)")
            launchApplied.fulfill()
        }
        let terminationGeneration = owner.enqueuePriority { generation in
            recorder.append("terminate:\(generation)")
            terminationApplied.fulfill()
        }
        let duplicateTerminationGeneration = owner.enqueuePriority { generation in
            recorder.append("terminate:\(generation)")
            duplicateTerminationApplied.fulfill()
        }

        XCTAssertEqual(launchGeneration?.rawValue, 1)
        XCTAssertEqual(terminationGeneration?.rawValue, 2)
        XCTAssertEqual(duplicateTerminationGeneration?.rawValue, 3)
        releaseActive.signal()
        await fulfillment(
            of: [
                launchApplied,
                terminationApplied,
                duplicateTerminationApplied,
                backlogApplied
            ],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        owner.performSynchronously {}

        XCTAssertEqual(
            recorder.snapshot(),
            [
                "active",
                "launch:1",
                "terminate:2",
                "terminate:3",
                "backlog"
            ]
        )
        XCTAssertEqual(owner.pendingPriorityWorkCount, 0)
    }

    func testRuntimeProjectionMaintenanceOwnerImmediatelyDrainsIdlePriorityWork() async {
        let owner = RuntimeProjectionMaintenanceOwner(
            label: "FlowTabTests.RuntimeProjectionMaintenanceOwner.Immediate"
        )
        defer { owner.cancelPendingPriorityWork() }
        let applied = expectation(
            description: "unmetCondition=idlePriorityWorkApplied"
        )
        let recorder = RuntimeProjectionMaintenanceEventRecorder()

        let generation = owner.enqueuePriority { generation in
            recorder.append("applied:\(generation)")
            applied.fulfill()
        }

        await fulfillment(
            of: [applied],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        owner.performSynchronously {}
        XCTAssertEqual(generation?.rawValue, 1)
        XCTAssertEqual(recorder.snapshot(), ["applied:1"])
    }

    func testRuntimeProjectionMaintenanceOwnerCancellationDropsPendingPriorityWork() async {
        let owner = RuntimeProjectionMaintenanceOwner(
            label: "FlowTabTests.RuntimeProjectionMaintenanceOwner.Cancel"
        )
        let activeStarted = expectation(
            description: "unmetCondition=cancellationActiveMaintenanceStarted"
        )
        let releaseActive = DispatchSemaphore(value: 0)
        let recorder = RuntimeProjectionMaintenanceEventRecorder()

        owner.enqueue {
            activeStarted.fulfill()
            releaseActive.wait()
        }
        await fulfillment(
            of: [activeStarted],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        XCTAssertNotNil(
            owner.enqueuePriority { generation in
                recorder.append("unexpected:\(generation)")
            }
        )
        XCTAssertEqual(owner.pendingPriorityWorkCount, 1)

        owner.cancelPendingPriorityWork()
        XCTAssertEqual(owner.pendingPriorityWorkCount, 0)
        XCTAssertNil(
            owner.enqueuePriority { generation in
                recorder.append("late:\(generation)")
            }
        )
        releaseActive.signal()
        owner.performSynchronously {}

        XCTAssertTrue(recorder.snapshot().isEmpty)
    }

    func testRuntimeProjectionMaintenanceOwnerDeinitCancelsQueuedPriorityWork() async {
        var owner: RuntimeProjectionMaintenanceOwner? =
            RuntimeProjectionMaintenanceOwner(
                label: "FlowTabTests.RuntimeProjectionMaintenanceOwner.Deinit"
            )
        weak var weakOwner = owner
        let queueBlocked = expectation(
            description: "unmetCondition=deinitQueueBlockStarted"
        )
        let queueReleased = expectation(
            description: "unmetCondition=deinitQueueBlockReleased"
        )
        let releaseQueue = DispatchSemaphore(value: 0)
        let recorder = RuntimeProjectionMaintenanceEventRecorder()

        owner?.queue.async {
            queueBlocked.fulfill()
            releaseQueue.wait()
            queueReleased.fulfill()
        }
        await fulfillment(
            of: [queueBlocked],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        XCTAssertNotNil(
            owner?.enqueuePriority { generation in
                recorder.append("unexpected:\(generation)")
            }
        )
        XCTAssertEqual(owner?.pendingPriorityWorkCount, 1)

        owner = nil
        XCTAssertNil(weakOwner)
        releaseQueue.signal()
        await fulfillment(
            of: [queueReleased],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        XCTAssertTrue(recorder.snapshot().isEmpty)
    }

    func testRuntimeProjectionMaintenanceOwnerPressureKeepsPriorityAheadOfNormalBacklog() async {
        let owner = RuntimeProjectionMaintenanceOwner(
            label: "FlowTabTests.RuntimeProjectionMaintenanceOwner.Pressure"
        )
        defer { owner.cancelPendingPriorityWork() }
        let activeStarted = expectation(
            description: "unmetCondition=pressureActiveMaintenanceStarted"
        )
        let releaseActive = DispatchSemaphore(value: 0)
        let priorityApplied = expectation(
            description: "unmetCondition=pressurePriorityApplied"
        )
        let recorder = RuntimeProjectionMaintenanceCounter()
        let normalWorkCount = 2_000

        owner.enqueue {
            activeStarted.fulfill()
            releaseActive.wait()
        }
        await fulfillment(
            of: [activeStarted],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        for _ in 0..<normalWorkCount {
            owner.enqueue {
                recorder.increment()
            }
        }
        owner.enqueuePriority { _ in
            recorder.recordPriorityObservation()
            priorityApplied.fulfill()
        }

        releaseActive.signal()
        await fulfillment(
            of: [priorityApplied],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        owner.performSynchronously {}

        XCTAssertEqual(recorder.priorityObservation, 0)
        XCTAssertEqual(recorder.count, normalWorkCount)
    }

    func testRuntimeProjectionMaintenanceOwnerKeepsOnlyLatestPriorityWorkPerKey() async {
        let owner = RuntimeProjectionMaintenanceOwner(
            label: "FlowTabTests.RuntimeProjectionMaintenanceOwner.PriorityCoalescing"
        )
        defer { owner.cancelPendingPriorityWork() }
        let queueBlocked = expectation(
            description: "unmetCondition=priorityCoalescingQueueBlocked"
        )
        let latestApplied = expectation(
            description: "unmetCondition=latestPriorityWorkApplied"
        )
        let distinctApplied = expectation(
            description: "unmetCondition=distinctPriorityWorkApplied"
        )
        let releaseQueue = DispatchSemaphore(value: 0)
        let recorder = RuntimeProjectionMaintenanceEventRecorder()
        let selectedAppKey = RuntimeProjectionMaintenanceCoalescingKey(
            rawValue: "selectedCurrentAppWindows:18405:com.example.editor"
        )
        let distinctKey = RuntimeProjectionMaintenanceCoalescingKey(
            rawValue: "selectedCurrentAppWindows:18406:com.example.browser"
        )

        owner.queue.async {
            queueBlocked.fulfill()
            releaseQueue.wait()
        }
        await fulfillment(
            of: [queueBlocked],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        let discardedGeneration = owner.enqueueLatestPriority(
            key: selectedAppKey
        ) { generation in
            recorder.append("discarded:\(generation)")
        }
        let latestGeneration = owner.enqueueLatestPriority(
            key: selectedAppKey
        ) { generation in
            recorder.append("latest:\(generation)")
            latestApplied.fulfill()
        }
        let distinctGeneration = owner.enqueueLatestPriority(
            key: distinctKey
        ) { generation in
            recorder.append("distinct:\(generation)")
            distinctApplied.fulfill()
        }

        XCTAssertEqual(discardedGeneration?.rawValue, 1)
        XCTAssertEqual(latestGeneration?.rawValue, 2)
        XCTAssertEqual(distinctGeneration?.rawValue, 3)
        XCTAssertEqual(owner.pendingPriorityWorkCount, 2)
        releaseQueue.signal()
        await fulfillment(
            of: [latestApplied, distinctApplied],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        owner.performSynchronously {}

        XCTAssertEqual(
            recorder.snapshot(),
            ["latest:2", "distinct:3"]
        )
        XCTAssertEqual(owner.pendingPriorityWorkCount, 0)
    }

    func testRuntimeProjectionServiceCoalescesRepeatedSelectedCurrentAppPriorityWork() async {
        let owner = RuntimeProjectionMaintenanceOwner(
            label: "FlowTabTests.RuntimeProjectionService.SelectedAppPriorityCoalescing"
        )
        defer { owner.cancelPendingPriorityWork() }
        let queueBlocked = expectation(
            description: "unmetCondition=selectedAppPriorityQueueBlocked"
        )
        let releaseQueue = DispatchSemaphore(value: 0)
        let coordinator = RuntimeReconciliationCoordinator()
        let executionLock = NSLock()
        var executedRequestCount = 0
        let service = RuntimeProjectionService(
            maintenanceOwner: owner,
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: RuntimeWindowRecordStore(),
                reconciliationCoordinator: coordinator
            ),
            reconciliationExecutor: { _, _ in
                executionLock.lock()
                executedRequestCount += 1
                executionLock.unlock()
                return .completed
            }
        )

        owner.queue.async {
            queueBlocked.fulfill()
            releaseQueue.wait()
        }
        await fulfillment(
            of: [queueBlocked],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        for _ in 0..<1_000 {
            service.signalSelectedCurrentAppWindowsChanged(
                appID: "com.example.editor",
                pid: 18_405
            )
        }
        XCTAssertEqual(owner.pendingPriorityWorkCount, 1)

        releaseQueue.signal()
        service.waitForMaintenanceQueueForTesting()
        executionLock.lock()
        let finalExecutedRequestCount = executedRequestCount
        executionLock.unlock()

        XCTAssertEqual(finalExecutedRequestCount, 1)
        XCTAssertEqual(owner.pendingPriorityWorkCount, 0)
    }

    func testRuntimeProjectionMaintenanceOwnerKeepsLatestCoalescedWorkAcrossQueuedAndActiveBursts() async {
        let owner = RuntimeProjectionMaintenanceOwner(
            label: "FlowTabTests.RuntimeProjectionMaintenanceOwner.Coalescing"
        )
        defer { owner.cancelPendingPriorityWork() }
        let key = RuntimeProjectionMaintenanceCoalescingKey(
            rawValue: "spaceTopology"
        )
        let queueBlocked = expectation(
            description: "unmetCondition=coalescingQueueBlocked"
        )
        let firstWorkStarted = expectation(
            description: "unmetCondition=firstCoalescedWorkStarted"
        )
        let latestWorkApplied = expectation(
            description: "unmetCondition=latestCoalescedWorkApplied"
        )
        let releaseQueue = DispatchSemaphore(value: 0)
        let releaseFirstWork = DispatchSemaphore(value: 0)
        let recorder = RuntimeProjectionMaintenanceEventRecorder()

        owner.queue.async {
            queueBlocked.fulfill()
            releaseQueue.wait()
        }
        await fulfillment(
            of: [queueBlocked],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        owner.enqueueLatest(key: key) {
            recorder.append("discardedQueued")
        }
        owner.enqueueLatest(key: key) {
            firstWorkStarted.fulfill()
            releaseFirstWork.wait()
            recorder.append("first")
        }
        XCTAssertEqual(owner.pendingCoalescedWorkCount, 1)
        releaseQueue.signal()
        await fulfillment(
            of: [firstWorkStarted],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        owner.enqueueLatest(key: key) {
            recorder.append("discardedActive")
        }
        owner.enqueueLatest(key: key) {
            recorder.append("latest")
            latestWorkApplied.fulfill()
        }
        XCTAssertEqual(owner.pendingCoalescedWorkCount, 1)
        releaseFirstWork.signal()
        await fulfillment(
            of: [latestWorkApplied],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )
        owner.performSynchronously {}

        XCTAssertEqual(recorder.snapshot(), ["first", "latest"])
        XCTAssertEqual(owner.pendingCoalescedWorkCount, 0)
    }
}

private final class RuntimeProjectionMaintenanceEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private final class RuntimeProjectionMaintenanceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var normalCount = 0
    private var observedNormalCountAtPriority: Int?

    func increment() {
        lock.lock()
        normalCount += 1
        lock.unlock()
    }

    func recordPriorityObservation() {
        lock.lock()
        observedNormalCountAtPriority = normalCount
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return normalCount
    }

    var priorityObservation: Int? {
        lock.lock()
        defer { lock.unlock() }
        return observedNormalCountAtPriority
    }
}
