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
