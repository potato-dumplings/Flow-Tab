import ApplicationServices
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testAXWindowObservationRetryPolicyClassifiesTransientFailuresAndCapsBackoff() {
        let policy = RuntimeAXWindowObservationRetryPolicy.standard

        XCTAssertEqual(
            (1...7).map(policy.interval(forAttempt:)),
            [0.25, 0.5, 1, 2, 4, 4, 4]
        )
        for error in [
            AXError.failure,
            .cannotComplete,
            .invalidUIElement,
            .invalidUIElementObserver
        ] {
            XCTAssertTrue(policy.shouldRetry(error), "axError=\(error.rawValue)")
        }
        XCTAssertFalse(policy.shouldRetry(.apiDisabled))
        XCTAssertFalse(policy.shouldRetry(.notificationUnsupported))
    }

    @MainActor
    func testAXWindowObservationRetryCoordinatorOwnsOneAttemptPerPIDAndRejectsStaleWork() {
        let scheduler = ManualAXWindowObservationRetryScheduler()
        let coordinator = RuntimeAXWindowObservationRetryCoordinator(
            policy: .standard,
            scheduler: scheduler
        )
        let pid = pid_t(18_417)
        var firedAttempts: [String] = []

        let first = coordinator.schedule(
            appID: "com.example.retry-owner",
            pid: pid,
            installGeneration: 1,
            error: .cannotComplete
        ) { attempt in
            firedAttempts.append("first:\(attempt)")
        }
        let duplicate = coordinator.schedule(
            appID: "com.example.retry-owner",
            pid: pid,
            installGeneration: 1,
            error: .cannotComplete
        ) { attempt in
            firedAttempts.append("duplicate:\(attempt)")
        }

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(scheduler.entries.map(\.interval), [0.25])

        scheduler.fireEntry(at: 0)
        XCTAssertEqual(firedAttempts, ["first:1"])

        let second = coordinator.schedule(
            appID: "com.example.retry-owner",
            pid: pid,
            installGeneration: 2,
            error: .failure
        ) { attempt in
            firedAttempts.append("second:\(attempt)")
        }
        XCTAssertEqual(second?.attempt, 2)
        XCTAssertEqual(scheduler.entries.map(\.interval), [0.25, 0.5])

        coordinator.retainBindings([pid: "com.example.replacement"])
        XCTAssertTrue(scheduler.entries[1].token.isCancelled)
        scheduler.fireEntry(at: 1)
        XCTAssertEqual(firedAttempts, ["first:1"])

        let replacement = coordinator.schedule(
            appID: "com.example.replacement",
            pid: pid,
            installGeneration: 3,
            error: .cannotComplete
        ) { attempt in
            firedAttempts.append("replacement:\(attempt)")
        }
        XCTAssertEqual(replacement?.attempt, 1)
        scheduler.fireEntry(at: 2)
        XCTAssertEqual(firedAttempts, ["first:1", "replacement:1"])
        XCTAssertEqual(
            coordinator.complete(pid: pid, appID: "com.example.replacement"),
            1
        )

        _ = coordinator.schedule(
            appID: "com.example.success",
            pid: 18_419,
            installGeneration: 4,
            error: .cannotComplete
        ) { attempt in
            firedAttempts.append("completed:\(attempt)")
        }
        XCTAssertEqual(
            coordinator.complete(pid: 18_419, appID: "com.example.success"),
            1
        )
        XCTAssertTrue(scheduler.entries[3].token.isCancelled)
        scheduler.fireEntry(at: 3)
        XCTAssertEqual(firedAttempts, ["first:1", "replacement:1"])

        _ = coordinator.schedule(
            appID: "com.example.stop",
            pid: 18_420,
            installGeneration: 5,
            error: .cannotComplete
        ) { attempt in
            firedAttempts.append("stop:\(attempt)")
        }
        coordinator.stop()
        XCTAssertTrue(scheduler.entries[4].token.isCancelled)
        scheduler.fireEntry(at: 4)
        XCTAssertEqual(firedAttempts, ["first:1", "replacement:1"])
    }

    @MainActor
    func testAXWindowChangeMonitorRetriesTransientInstallAndPublishesInitialReadback() async {
        let workScheduler = ManualAXWindowObservationWorkScheduler()
        let retryScheduler = ManualAXWindowObservationRetryScheduler()
        let retryScheduled = expectation(
            description: "unmetCondition=axObserverTransientFailureScheduledRetry"
        )
        retryScheduler.onSchedule = { _ in retryScheduled.fulfill() }
        let changedReadback = RuntimeAXWindowInitialReadbackEvidence.evaluate(
            expectedWindowCount: 1,
            knownSwitchableWindowCount: 2,
            observedSwitchableWindowCount: 2,
            exactKnownWindowCount: 2,
            fetchErrorRawValue: 0,
            rawValueTypeDescription: "CFArray"
        )
        let installer = StubAXWindowObserverInstaller(
            outcomes: [
                .unavailable(.cannotComplete),
                .installed(initialReadback: changedReadback)
            ]
        )
        let monitor = RuntimeAXWindowChangeMonitor(
            observationWorkScheduler: workScheduler,
            observerInstaller: installer,
            retryPolicy: .standard,
            retryScheduler: retryScheduler,
            accessibilityTrustProvider: { true }
        )
        let delivered = expectation(
            description: "unmetCondition=axObserverRetryInitialReadbackPublished"
        )
        var deliveredEvidence: [RuntimeAXWindowChangeEvidence] = []
        monitor.onAppWindowChanged = { evidence in
            deliveredEvidence.append(evidence)
            delivered.fulfill()
        }
        let summary = RuntimeHomeAppSummary(
            appID: "com.example.transient-observer",
            displayName: "Transient Observer",
            groupID: "com.example.transient-observer",
            lastActiveAt: 1,
            windowCount: 1,
            pid: 2_000_000_000
        )

        monitor.rebind([summary])
        XCTAssertEqual(workScheduler.workItems.count, 1)
        workScheduler.fireWorkItem(at: 0)
        await fulfillment(of: [retryScheduled], timeout: 5)

        XCTAssertEqual(retryScheduler.entries.map(\.interval), [0.25])
        retryScheduler.fireEntry(at: 0)
        XCTAssertEqual(workScheduler.workItems.count, 2)
        workScheduler.fireWorkItem(at: 1)
        await fulfillment(of: [delivered], timeout: 5)

        XCTAssertEqual(deliveredEvidence.count, 1)
        XCTAssertEqual(deliveredEvidence[0].appID, summary.appID)
        XCTAssertEqual(deliveredEvidence[0].pid, summary.pid)
        XCTAssertEqual(deliveredEvidence[0].source, .initialReadback)
        XCTAssertEqual(deliveredEvidence[0].initialReadback, changedReadback)
        XCTAssertTrue(deliveredEvidence[0].requiresReconciliation)

        monitor.stop()
    }

    @MainActor
    func testAXWindowChangeMonitorRebindDefersRemoteTransportAndCoalescesRepeatedHomeReads() {
        let scheduler = ManualAXWindowObservationWorkScheduler()
        let monitor = RuntimeAXWindowChangeMonitor(
            observationWorkScheduler: scheduler,
            accessibilityTrustProvider: { true }
        )
        let summary = RuntimeHomeAppSummary(
            appID: "com.example.home-rebind",
            displayName: "Home Rebind",
            groupID: "com.example.home-rebind",
            lastActiveAt: 1,
            windowCount: 1,
            pid: 18_418
        )

        monitor.rebind([summary])
        monitor.rebind([summary])

        XCTAssertEqual(scheduler.workItems.count, 1)

        monitor.stop()
        monitor.rebind([summary])

        XCTAssertEqual(scheduler.workItems.count, 2)
    }

    func testAXWindowObservationRegistrationBoundsRemoteTransportFailure() {
        XCTAssertEqual(
            RuntimeAXMessagingTimeoutPolicy.perElementSeconds,
            0.5,
            accuracy: 0.001
        )
        let appElement = AXUIElementCreateApplication(18_419)
        let notifications = [
            kAXWindowCreatedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString,
            kAXMainWindowChangedNotification as CFString
        ]
        var events: [String] = []

        let evidence = RuntimeAXWindowObservationRegistrationPolicy.register(
            element: appElement,
            notifications: notifications,
            applyMessagingTimeout: { element in
                XCTAssertTrue(CFEqual(element, appElement))
                events.append("timeout")
            },
            addNotification: { element, notification in
                XCTAssertTrue(CFEqual(element, appElement))
                events.append(notification as String)
                return notification as String == kAXWindowCreatedNotification as String
                    ? .success
                    : .cannotComplete
            }
        )

        XCTAssertEqual(
            events,
            [
                "timeout",
                kAXWindowCreatedNotification as String,
                kAXFocusedWindowChangedNotification as String
            ]
        )
        XCTAssertEqual(
            evidence.registeredNotifications.map { $0 as String },
            [kAXWindowCreatedNotification as String]
        )
        XCTAssertEqual(evidence.lastResult, .cannotComplete)
    }

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

private final class ManualAXWindowObservationWorkScheduler:
    RuntimeAXWindowObservationWorkScheduling
{
    private(set) var workItems: [@Sendable () -> Void] = []

    func schedule(_ work: @escaping @Sendable () -> Void) {
        workItems.append(work)
    }

    func fireWorkItem(at index: Int) {
        workItems[index]()
    }
}

private final class StubAXWindowObserverInstaller:
    RuntimeAXWindowObserverInstalling,
    @unchecked Sendable
{
    enum Outcome {
        case unavailable(AXError)
        case installed(initialReadback: RuntimeAXWindowInitialReadbackEvidence)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func install(
        _ request: RuntimeAXWindowObserverInstallRequest
    ) -> RuntimeAXWindowObserverInstallResult {
        let outcome = lock.withLock { outcomes.removeFirst() }
        switch outcome {
        case .unavailable(let error):
            return RuntimeAXWindowObserverInstallResult(
                observer: nil,
                context: request.context,
                registeredNotifications: [],
                lastResult: error,
                destroyedWindowElements: [:],
                initialReadback: nil
            )
        case .installed(let initialReadback):
            var observer: AXObserver?
            let result = AXObserverCreate(
                request.pid,
                request.callback,
                &observer
            )
            precondition(result == .success && observer != nil)
            return RuntimeAXWindowObserverInstallResult(
                observer: observer,
                context: request.context,
                registeredNotifications: [
                    kAXWindowCreatedNotification as CFString
                ],
                lastResult: .success,
                destroyedWindowElements: [:],
                initialReadback: initialReadback
            )
        }
    }
}

@MainActor
private final class ManualAXWindowObservationRetryToken:
    RuntimeAXWindowObservationRetryCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
private final class ManualAXWindowObservationRetryScheduler:
    RuntimeAXWindowObservationRetryScheduling
{
    struct Entry {
        let interval: TimeInterval
        let token: ManualAXWindowObservationRetryToken
        let action: @MainActor @Sendable () -> Void
    }

    var onSchedule: ((Entry) -> Void)?
    private(set) var entries: [Entry] = []

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAXWindowObservationRetryCancellable {
        let token = ManualAXWindowObservationRetryToken()
        let entry = Entry(
            interval: interval,
            token: token,
            action: action
        )
        entries.append(entry)
        onSchedule?(entry)
        return token
    }

    func fireEntry(at index: Int) {
        entries[index].action()
    }
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
