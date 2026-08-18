import ApplicationServices
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testAXWindowInitialReadbackCountsExactIdentityWithoutReusingBaselineEntry() {
        let retainedWindow = AXUIElementCreateApplication(18_420)
        let replacedWindow = AXUIElementCreateApplication(18_421)
        let replacement = AXUIElementCreateApplication(18_422)

        XCTAssertEqual(
            RuntimeAXWindowChangeMonitor.exactKnownWindowCount(
                currentWindows: [retainedWindow, replacement, retainedWindow],
                knownWindows: [retainedWindow, replacedWindow]
            ),
            1
        )
    }

    func testAXWindowInitialReadbackMatchesOnlyExactBaselineIdentityAndCount() {
        let readback = RuntimeAXWindowInitialReadbackEvidence.evaluate(
            expectedWindowCount: 2,
            knownSwitchableWindowCount: 2,
            observedSwitchableWindowCount: 2,
            exactKnownWindowCount: 2,
            fetchErrorRawValue: 0,
            rawValueTypeDescription: "CFArray"
        )

        XCTAssertEqual(readback.state, .matchesBaseline)
        XCTAssertFalse(readback.requiresReconciliation)
    }

    func testAXWindowInitialReadbackDetectsSameCountIdentityReplacement() {
        let readback = RuntimeAXWindowInitialReadbackEvidence.evaluate(
            expectedWindowCount: 2,
            knownSwitchableWindowCount: 2,
            observedSwitchableWindowCount: 2,
            exactKnownWindowCount: 1,
            fetchErrorRawValue: 0,
            rawValueTypeDescription: "CFArray"
        )

        XCTAssertEqual(readback.state, .changedSinceBaseline)
        XCTAssertTrue(readback.requiresReconciliation)
    }

    func testAXWindowInitialReadbackDetectsCountChange() {
        let readback = RuntimeAXWindowInitialReadbackEvidence.evaluate(
            expectedWindowCount: 2,
            knownSwitchableWindowCount: 1,
            observedSwitchableWindowCount: 1,
            exactKnownWindowCount: 1,
            fetchErrorRawValue: 0,
            rawValueTypeDescription: "CFArray"
        )

        XCTAssertEqual(readback.state, .changedSinceBaseline)
        XCTAssertTrue(readback.requiresReconciliation)
    }

    func testAXWindowInitialReadbackAcceptsKnownPublicSubset() {
        let readback = RuntimeAXWindowInitialReadbackEvidence.evaluate(
            expectedWindowCount: 3,
            knownSwitchableWindowCount: 3,
            observedSwitchableWindowCount: 1,
            exactKnownWindowCount: 1,
            fetchErrorRawValue: 0,
            rawValueTypeDescription: "CFArray"
        )

        XCTAssertEqual(readback.state, .matchesBaseline)
        XCTAssertFalse(readback.requiresReconciliation)
    }

    func testAXWindowInitialReadbackUnavailableRequiresReconciliationWithLastEvidence() {
        let readback = RuntimeAXWindowInitialReadbackEvidence.evaluate(
            expectedWindowCount: 2,
            knownSwitchableWindowCount: 2,
            observedSwitchableWindowCount: nil,
            exactKnownWindowCount: 0,
            fetchErrorRawValue: -25204,
            rawValueTypeDescription: "nil"
        )

        XCTAssertEqual(readback.state, .unavailable)
        XCTAssertTrue(readback.requiresReconciliation)
        XCTAssertEqual(readback.fetchErrorRawValue, -25204)
        XCTAssertEqual(readback.rawValueTypeDescription, "nil")
    }

    @MainActor
    func testAXWindowChangeDeliveryPolicyNamesCoalescingCadence() {
        XCTAssertEqual(
            RuntimeAXWindowChangeDeliveryPolicy.standardCoalesced
                .coalescingInterval,
            0.16
        )
    }

    @MainActor
    func testAXWindowChangeDeliveryPublishesInitialReadbackAfterBinding() {
        let scheduler = ManualAXWindowChangeDeliveryScheduler()
        let coordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: .standardCoalesced,
            scheduler: scheduler
        )
        var evidence: [RuntimeAXWindowChangeEvidence] = []
        coordinator.onEvidence = { evidence.append($0) }

        let binding = coordinator.bind(
            appID: "com.example.initial-readback",
            pid: 18_430
        )
        let readback = matchedAXWindowInitialReadbackEvidence()
        coordinator.publishInitialReadback(
            pid: 18_430,
            bindingGeneration: binding,
            readback: readback
        )

        XCTAssertEqual(
            evidence,
            [
                RuntimeAXWindowChangeEvidence(
                    appID: "com.example.initial-readback",
                    pid: 18_430,
                    generation: 1,
                    source: .initialReadback,
                    observedTransitionCount: 0,
                    initialReadback: readback
                )
            ]
        )
        XCTAssertFalse(evidence[0].requiresReconciliation)
        XCTAssertTrue(scheduler.entries.isEmpty)
    }

    @MainActor
    func testAXWindowChangeDeliveryCapturesFirstTransitionWithoutWarmUp() {
        let scheduler = ManualAXWindowChangeDeliveryScheduler()
        let coordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: .standardCoalesced,
            scheduler: scheduler
        )
        var evidence: [RuntimeAXWindowChangeEvidence] = []
        coordinator.onEvidence = { evidence.append($0) }
        let binding = coordinator.bind(
            appID: "com.example.early-transition",
            pid: 18_431
        )

        coordinator.recordObservedTransition(
            pid: 18_431,
            bindingGeneration: binding
        )

        XCTAssertTrue(evidence.isEmpty)
        XCTAssertEqual(scheduler.entries.map(\.interval), [0.16])
        scheduler.fireEntry(at: 0)
        XCTAssertEqual(evidence.map(\.generation), [1])
        XCTAssertEqual(evidence.map(\.source), [.trailingReadback])
    }

    @MainActor
    func testAXWindowChangeDeliveryCoalescesBurstWithTrailingReadback() {
        let scheduler = ManualAXWindowChangeDeliveryScheduler()
        let coordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: .standardCoalesced,
            scheduler: scheduler
        )
        var evidence: [RuntimeAXWindowChangeEvidence] = []
        coordinator.onEvidence = { evidence.append($0) }
        let binding = coordinator.bind(
            appID: "com.example.coalesced-transitions",
            pid: 18_432
        )

        coordinator.recordObservedTransition(
            pid: 18_432,
            bindingGeneration: binding
        )
        coordinator.recordObservedTransition(
            pid: 18_432,
            bindingGeneration: binding
        )
        coordinator.recordObservedTransition(
            pid: 18_432,
            bindingGeneration: binding
        )

        XCTAssertTrue(evidence.isEmpty)
        XCTAssertEqual(scheduler.entries.count, 3)
        XCTAssertTrue(scheduler.entries[0].token.isCancelled)
        XCTAssertTrue(scheduler.entries[1].token.isCancelled)
        scheduler.fireEntry(at: 0)
        scheduler.fireEntry(at: 1)
        XCTAssertTrue(evidence.isEmpty)
        scheduler.fireEntry(at: 2)

        XCTAssertEqual(evidence.map(\.generation), [3])
        XCTAssertEqual(evidence.map(\.source), [.trailingReadback])
        XCTAssertEqual(evidence.last?.observedTransitionCount, 3)
    }

    @MainActor
    func testAXWindowChangeDeliverySingleTransitionPublishesTrailingReadback() {
        let scheduler = ManualAXWindowChangeDeliveryScheduler()
        let coordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: .standardCoalesced,
            scheduler: scheduler
        )
        var evidence: [RuntimeAXWindowChangeEvidence] = []
        coordinator.onEvidence = { evidence.append($0) }
        let binding = coordinator.bind(
            appID: "com.example.single-transition",
            pid: 18_433
        )

        coordinator.recordObservedTransition(
            pid: 18_433,
            bindingGeneration: binding
        )
        scheduler.fireEntry(at: 0)

        XCTAssertEqual(evidence.map(\.generation), [1])
        XCTAssertEqual(evidence.map(\.source), [.trailingReadback])
        XCTAssertEqual(evidence.map(\.observedTransitionCount), [1])
    }

    @MainActor
    func testAXWindowChangeDeliveryCancellationRejectsPendingTrailingReadback() {
        let scheduler = ManualAXWindowChangeDeliveryScheduler()
        let coordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: .standardCoalesced,
            scheduler: scheduler
        )
        var evidence: [RuntimeAXWindowChangeEvidence] = []
        coordinator.onEvidence = { evidence.append($0) }
        let binding = coordinator.bind(
            appID: "com.example.cancelled-transition",
            pid: 18_434
        )
        coordinator.recordObservedTransition(
            pid: 18_434,
            bindingGeneration: binding
        )
        coordinator.recordObservedTransition(
            pid: 18_434,
            bindingGeneration: binding
        )

        coordinator.unbind(pid: 18_434, bindingGeneration: binding)

        XCTAssertTrue(scheduler.entries.allSatisfy(\.token.isCancelled))
        scheduler.fireEntry(at: 0)
        scheduler.fireEntry(at: 1)
        XCTAssertTrue(evidence.isEmpty)
    }

    @MainActor
    func testAXWindowChangeDeliveryStopCancelsEveryPendingReadback() {
        let scheduler = ManualAXWindowChangeDeliveryScheduler()
        let coordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: .standardCoalesced,
            scheduler: scheduler
        )
        var evidence: [RuntimeAXWindowChangeEvidence] = []
        coordinator.onEvidence = { evidence.append($0) }

        for (appID, pid) in [
            ("com.example.stop-one", pid_t(18_437)),
            ("com.example.stop-two", pid_t(18_438))
        ] {
            let binding = coordinator.bind(appID: appID, pid: pid)
            coordinator.recordObservedTransition(
                pid: pid,
                bindingGeneration: binding
            )
            coordinator.recordObservedTransition(
                pid: pid,
                bindingGeneration: binding
            )
        }

        coordinator.stop()

        XCTAssertEqual(scheduler.entries.count, 4)
        XCTAssertTrue(scheduler.entries.allSatisfy(\.token.isCancelled))
        scheduler.fireEntry(at: 0)
        scheduler.fireEntry(at: 1)
        scheduler.fireEntry(at: 2)
        scheduler.fireEntry(at: 3)
        XCTAssertTrue(evidence.isEmpty)
    }

    @MainActor
    func testAXWindowChangeDeliveryRejectsStaleTimerAfterPIDRebind() {
        let scheduler = ManualAXWindowChangeDeliveryScheduler()
        let coordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: .standardCoalesced,
            scheduler: scheduler
        )
        var evidence: [RuntimeAXWindowChangeEvidence] = []
        coordinator.onEvidence = { evidence.append($0) }
        let oldBinding = coordinator.bind(
            appID: "com.example.previous-pid-owner",
            pid: 18_435
        )
        coordinator.recordObservedTransition(
            pid: 18_435,
            bindingGeneration: oldBinding
        )
        coordinator.recordObservedTransition(
            pid: 18_435,
            bindingGeneration: oldBinding
        )

        let newBinding = coordinator.bind(
            appID: "com.example.current-pid-owner",
            pid: 18_435
        )
        coordinator.publishInitialReadback(
            pid: 18_435,
            bindingGeneration: newBinding,
            readback: matchedAXWindowInitialReadbackEvidence()
        )
        scheduler.fireEntry(at: 0)

        XCTAssertEqual(evidence.map(\.appID), [
            "com.example.current-pid-owner"
        ])
        XCTAssertEqual(evidence.map(\.generation), [3])
        XCTAssertEqual(
            evidence.map(\.source),
            [.initialReadback]
        )
    }

}

private func matchedAXWindowInitialReadbackEvidence(
    windowCount: Int = 2
) -> RuntimeAXWindowInitialReadbackEvidence {
    RuntimeAXWindowInitialReadbackEvidence.evaluate(
        expectedWindowCount: windowCount,
        knownSwitchableWindowCount: windowCount,
        observedSwitchableWindowCount: windowCount,
        exactKnownWindowCount: windowCount,
        fetchErrorRawValue: 0,
        rawValueTypeDescription: "CFArray"
    )
}

@MainActor
private final class ManualAXWindowChangeDeliveryToken:
    RuntimeAXWindowChangeDeliveryCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
private final class ManualAXWindowChangeDeliveryScheduler:
    RuntimeAXWindowChangeDeliveryScheduling
{
    struct Entry {
        let interval: TimeInterval
        let token: ManualAXWindowChangeDeliveryToken
        let action: @MainActor @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAXWindowChangeDeliveryCancellable {
        let token = ManualAXWindowChangeDeliveryToken()
        entries.append(
            Entry(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    func fireEntry(at index: Int) {
        entries[index].action()
    }
}
