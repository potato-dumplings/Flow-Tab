import XCTest
@testable import FlowTab

private enum MockWindowPreviewLatencyLifecycleWatchdogPolicy {
    static let eventDelivery: TimeInterval = 1
}

extension FlowTabTests {
    func testMockWindowPreviewLatencyLifecycleWatchdogPolicyPreservesEventDeliveryBound() {
        let eventDelivery =
            MockWindowPreviewLatencyLifecycleWatchdogPolicy
                .eventDelivery

        XCTAssertEqual(eventDelivery, 1)
        XCTAssertTrue(eventDelivery.isFinite)
        XCTAssertGreaterThan(eventDelivery, 0)
    }

    func testUITestMockWindowPreviewLatencyPolicyAndEvidence() {
        XCTAssertEqual(
            FlowTabUITestMockWindowPreviewLatencyPolicy(
                rawMilliseconds: 0
            ).milliseconds,
            1
        )
        XCTAssertEqual(
            FlowTabUITestMockWindowPreviewLatencyPolicy(
                rawMilliseconds: 5_000
            ).milliseconds,
            1_000
        )

        let waiter =
            ImmediateMockWindowPreviewLatencyWaiter(
                outcome: .elapsed
            )
        let evidenceStore =
            LockedMockWindowPreviewLatencyEvidenceStore()
        let owner =
            FlowTabUITestMockWindowPreviewLatencyOwner(
                generation: 17,
                policy:
                    FlowTabUITestMockWindowPreviewLatencyPolicy(
                        rawMilliseconds: 80
                    ),
                waiter: waiter,
                onEvidence: {
                    evidenceStore.append($0)
                }
            )

        let result = owner.waitBeforeCapture(
            requestCount: 2
        )

        XCTAssertEqual(
            result,
            FlowTabUITestMockWindowPreviewLatencyEvidence(
                ownerGeneration: 17,
                batchGeneration: 1,
                requestCount: 2,
                policy:
                    FlowTabUITestMockWindowPreviewLatencyPolicy(
                        rawMilliseconds: 80
                    ),
                outcome: .elapsed
            )
        )
        XCTAssertEqual(
            evidenceStore.values,
            [result]
        )
        XCTAssertEqual(
            waiter.intervals,
            [0.08]
        )
    }

    func testUITestMockWindowPreviewLatencyCancellationReleasesWait() {
        let waiter =
            BlockingMockWindowPreviewLatencyWaiter()
        let evidenceStore =
            LockedMockWindowPreviewLatencyEvidenceStore()
        let owner =
            FlowTabUITestMockWindowPreviewLatencyOwner(
                generation: 23,
                policy:
                    FlowTabUITestMockWindowPreviewLatencyPolicy(
                        rawMilliseconds: 1_000
                    ),
                waiter: waiter,
                onEvidence: {
                    evidenceStore.append($0)
                }
            )
        let completed = expectation(
            description:
                "unmetCondition=cancelledPreviewLatencyWaitPublishesExactEvidence ownerGeneration=23 requestCount=3"
        )
        completed.assertForOverFulfill = true
        let expectedEvidence =
            FlowTabUITestMockWindowPreviewLatencyEvidence(
                ownerGeneration: 23,
                batchGeneration: 1,
                requestCount: 3,
                policy:
                    FlowTabUITestMockWindowPreviewLatencyPolicy(
                        rawMilliseconds: 1_000
                    ),
                outcome: .cancelled
            )
        let returnedEvidenceStore =
            LockedMockWindowPreviewLatencyEvidenceStore()
        let workItem = DispatchWorkItem {
            let result = owner.waitBeforeCapture(
                requestCount: 3
            )
            returnedEvidenceStore.append(result)
            if result == expectedEvidence {
                completed.fulfill()
            }
        }
        defer {
            owner.cancel()
            workItem.cancel()
        }

        XCTAssertEqual(
            waiter.snapshot,
            BlockingMockWindowPreviewLatencyWaiter
                .Snapshot(
                    waitCount: 0,
                    isWaiting: false,
                    cancelCount: 0
                )
        )
        XCTAssertTrue(evidenceStore.values.isEmpty)
        XCTAssertTrue(returnedEvidenceStore.values.isEmpty)

        DispatchQueue.global().async(execute: workItem)

        let startResult = waiter.started.wait(
            timeout:
                .now()
                + MockWindowPreviewLatencyLifecycleWatchdogPolicy
                    .eventDelivery
        )
        XCTAssertEqual(
            startResult,
            .success,
            "unmetCondition=previewLatencyWaitEnteredControlledBlock "
                + "finalWaiterSnapshot=\(waiter.snapshot) "
                + "finalPublishedEvidence=\(evidenceStore.values) "
                + "finalReturnedEvidence=\(returnedEvidenceStore.values)"
        )
        XCTAssertEqual(
            waiter.snapshot,
            BlockingMockWindowPreviewLatencyWaiter
                .Snapshot(
                    waitCount: 1,
                    isWaiting: true,
                    cancelCount: 0
                )
        )
        XCTAssertTrue(evidenceStore.values.isEmpty)
        XCTAssertTrue(returnedEvidenceStore.values.isEmpty)

        owner.cancel()
        wait(
            for: [completed],
            timeout:
                MockWindowPreviewLatencyLifecycleWatchdogPolicy
                    .eventDelivery
        )

        XCTAssertEqual(
            waiter.snapshot,
            BlockingMockWindowPreviewLatencyWaiter
                .Snapshot(
                    waitCount: 1,
                    isWaiting: false,
                    cancelCount: 1
                ),
            "unmetCondition=previewLatencyWaitReleasedAfterCancellation "
                + "finalPublishedEvidence=\(evidenceStore.values) "
                + "finalReturnedEvidence=\(returnedEvidenceStore.values)"
        )
        XCTAssertEqual(
            returnedEvidenceStore.values,
            [expectedEvidence]
        )
        XCTAssertEqual(
            evidenceStore.values,
            [expectedEvidence]
        )
        XCTAssertEqual(
            waiter.cancelCount,
            1
        )
    }

    @MainActor
    func testUITestBootstrapperOwnsMockWindowPreviewLatencyLifecycle() {
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        let controller = SwitcherPanelController(
            model: model
        )
        let baselineGeneration =
            FlowTabUITestBootstrapper
                .mockWindowPreviewLatencyGenerationForTesting
        defer {
            FlowTabUITestBootstrapper
                .stopMockWindowPreviewLatencyInjection()
        }

        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-window-previews",
                "--flowtab-ui-mock-window-preview-delay-ms",
                "80"
            ]
        ) {
            FlowTabUITestBootstrapper
                .configurePanelControllerIfNeeded(
                    panelController: controller
                )
            XCTAssertTrue(
                FlowTabUITestBootstrapper
                    .isMockWindowPreviewLatencyInjectionActiveForTesting
            )
            XCTAssertEqual(
                FlowTabUITestBootstrapper
                    .mockWindowPreviewLatencyGenerationForTesting,
                baselineGeneration &+ 1
            )
            XCTAssertNotNil(
                model.previewCaptureBatchOverride
            )

            FlowTabUITestBootstrapper
                .configurePanelControllerIfNeeded(
                    panelController: controller
                )
            XCTAssertEqual(
                FlowTabUITestBootstrapper
                    .mockWindowPreviewLatencyGenerationForTesting,
                baselineGeneration &+ 2
            )

            FlowTabUITestBootstrapper
                .stopMockWindowPreviewLatencyInjection()
            XCTAssertFalse(
                FlowTabUITestBootstrapper
                    .isMockWindowPreviewLatencyInjectionActiveForTesting
            )
            XCTAssertNil(
                model.previewCaptureBatchOverride
            )
        }
    }

    func testUITestMockWindowPreviewLatencyReplacementPressure() {
        var owners:
            [FlowTabUITestMockWindowPreviewLatencyOwner] =
                []
        let evidenceStore =
            LockedMockWindowPreviewLatencyEvidenceStore()

        for generation in 1...500 {
            owners.last?.cancel()
            owners.append(
                FlowTabUITestMockWindowPreviewLatencyOwner(
                    generation: UInt64(generation),
                    policy:
                        FlowTabUITestMockWindowPreviewLatencyPolicy(
                            rawMilliseconds: 80
                        ),
                    waiter:
                        ImmediateMockWindowPreviewLatencyWaiter(
                            outcome: .elapsed
                        ),
                    onEvidence: {
                        evidenceStore.append($0)
                    }
                )
            )
        }

        for owner in owners.dropLast() {
            XCTAssertEqual(
                owner.waitBeforeCapture(
                    requestCount: 1
                ).outcome,
                .cancelled
            )
        }
        XCTAssertEqual(
            owners.last?
                .waitBeforeCapture(requestCount: 2)
                .outcome,
            .elapsed
        )
        let evidence = evidenceStore.values
        XCTAssertEqual(evidence.count, 500)
        XCTAssertEqual(
            evidence.filter {
                $0.outcome == .elapsed
            }.map(\.ownerGeneration),
            [500]
        )
    }
}

private final class
    ImmediateMockWindowPreviewLatencyWaiter:
    FlowTabUITestMockWindowPreviewLatencyWaiting
{
    let outcome:
        FlowTabUITestMockWindowPreviewLatencyOutcome
    private(set) var intervals: [TimeInterval] = []
    private(set) var cancelCount = 0

    init(
        outcome:
            FlowTabUITestMockWindowPreviewLatencyOutcome
    ) {
        self.outcome = outcome
    }

    func wait(
        for interval: TimeInterval
    ) -> FlowTabUITestMockWindowPreviewLatencyOutcome {
        intervals.append(interval)
        return outcome
    }

    func cancel() {
        cancelCount += 1
    }
}

private final class
    BlockingMockWindowPreviewLatencyWaiter:
    FlowTabUITestMockWindowPreviewLatencyWaiting,
    @unchecked Sendable
{
    struct Snapshot: Equatable {
        let waitCount: Int
        let isWaiting: Bool
        let cancelCount: Int
    }

    let started = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var storedWaitCount = 0
    private var storedIsWaiting = false
    private var storedCancelCount = 0

    var snapshot: Snapshot {
        lock.lock()
        let result = Snapshot(
            waitCount: storedWaitCount,
            isWaiting: storedIsWaiting,
            cancelCount: storedCancelCount
        )
        lock.unlock()
        return result
    }

    var cancelCount: Int {
        snapshot.cancelCount
    }

    func wait(
        for _: TimeInterval
    ) -> FlowTabUITestMockWindowPreviewLatencyOutcome {
        lock.lock()
        storedWaitCount += 1
        storedIsWaiting = true
        lock.unlock()
        started.signal()
        release.wait()
        lock.lock()
        storedIsWaiting = false
        lock.unlock()
        return .cancelled
    }

    func cancel() {
        lock.lock()
        storedCancelCount += 1
        lock.unlock()
        release.signal()
    }
}

private final class
    LockedMockWindowPreviewLatencyEvidenceStore:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage:
        [FlowTabUITestMockWindowPreviewLatencyEvidence]
            = []

    var values:
        [FlowTabUITestMockWindowPreviewLatencyEvidence]
    {
        lock.lock()
        let result = storage
        lock.unlock()
        return result
    }

    func append(
        _ evidence:
            FlowTabUITestMockWindowPreviewLatencyEvidence
    ) {
        lock.lock()
        storage.append(evidence)
        lock.unlock()
    }
}
