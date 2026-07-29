#if FLOWTAB_TESTING

@MainActor
protocol TabSwitchStressRunning:
    AnyObject
{
    func startIfNeeded()
    func stop()
}

@MainActor
final class TabSwitchStressRunner:
    TabSwitchStressRunning
{
    typealias PolicyProvider =
        @MainActor () -> TabSwitchStressPolicy?
    typealias Selection =
        @MainActor (
            TabSwitchStressTarget
        ) -> TabSwitchStressTarget?
    typealias Termination =
        @MainActor () -> Void
    typealias EvidenceHandler =
        @MainActor (
            TabSwitchStressEvidence
        ) -> Void

    private struct ActiveRun {
        let ownerGeneration: UInt64
        let policy: TabSwitchStressPolicy
        let startNanoseconds: UInt64
        let deadlineNanoseconds: UInt64
        var attemptCount: UInt64
        var switchCount: UInt64
        var requestedTarget:
            TabSwitchStressTarget?
        var observedTarget:
            TabSwitchStressTarget?
        var wakeGeneration: UInt64
        var wakeToken:
            (any TabSwitchStressCancellable)?
    }

    static let shared = makeShared()

    private let policyProvider: PolicyProvider
    private let clock:
        any TabSwitchStressMonotonicClock
    private let scheduler:
        any TabSwitchStressScheduling
    private let selectTarget: Selection
    private let terminate: Termination
    private let onEvidence: EvidenceHandler

    private var active: ActiveRun?

    private(set) var ownerGeneration: UInt64 = 0
    private(set) var transitionGeneration: UInt64 = 0
    private(set) var lastEvidence:
        TabSwitchStressEvidence?

    init(
        policyProvider:
            @escaping PolicyProvider,
        clock:
            any TabSwitchStressMonotonicClock,
        scheduler:
            any TabSwitchStressScheduling,
        selectTarget:
            @escaping Selection,
        terminate:
            @escaping Termination,
        onEvidence:
            @escaping EvidenceHandler
    ) {
        self.policyProvider = policyProvider
        self.clock = clock
        self.scheduler = scheduler
        self.selectTarget = selectTarget
        self.terminate = terminate
        self.onEvidence = onEvidence
    }

    var isRunning: Bool {
        active != nil
    }

    func startIfNeeded() {
        guard active == nil,
              let policy = policyProvider()
        else {
            return
        }

        ownerGeneration &+= 1
        let generation = ownerGeneration
        let startNanoseconds =
            clock.nowNanoseconds
        active = ActiveRun(
            ownerGeneration: generation,
            policy: policy,
            startNanoseconds: startNanoseconds,
            deadlineNanoseconds:
                policy.deadline(
                    after: startNanoseconds
                ),
            attemptCount: 0,
            switchCount: 0,
            requestedTarget: nil,
            observedTarget: nil,
            wakeGeneration: 0,
            wakeToken: nil
        )

        guard let started = active else { return }
        publish(
            phase: .started,
            run: started,
            observedAtNanoseconds:
                startNanoseconds
        )
        guard active?.ownerGeneration == generation
        else {
            return
        }
        performSelection(
            generation: generation
        )
    }

    func stop() {
        guard let cancelled = takeActive()
        else {
            return
        }
        publish(
            phase: .cancelled,
            run: cancelled,
            observedAtNanoseconds:
                clock.nowNanoseconds
        )
    }

    deinit {
        active?.wakeToken?.cancel()
    }

    private func continueRun(
        generation: UInt64
    ) {
        guard let current = active,
              current.ownerGeneration == generation
        else {
            return
        }
        if current.switchCount
            >= current.policy.requiredSwitchCount
        {
            finishOrSchedule(
                generation: generation
            )
        } else {
            performSelection(
                generation: generation
            )
        }
    }

    private func performSelection(
        generation: UInt64
    ) {
        guard var current = active,
              current.ownerGeneration == generation
        else {
            return
        }
        let targets =
            TabSwitchStressTarget.allCases
        let targetIndex = Int(
            current.switchCount
                % UInt64(targets.count)
        )
        let requestedTarget =
            targets[targetIndex]
        current.attemptCount &+= 1
        current.requestedTarget =
            requestedTarget
        active = current

        let observedTarget =
            selectTarget(requestedTarget)

        guard var observed = active,
              observed.ownerGeneration == generation
        else {
            return
        }
        observed.observedTarget = observedTarget
        if observedTarget == requestedTarget {
            observed.switchCount &+= 1
        }
        active = observed
        publish(
            phase: .selectionObserved,
            run: observed,
            observedAtNanoseconds:
                clock.nowNanoseconds
        )
        guard active?.ownerGeneration == generation
        else {
            return
        }
        finishOrSchedule(
            generation: generation
        )
    }

    private func finishOrSchedule(
        generation: UInt64
    ) {
        guard let current = active,
              current.ownerGeneration == generation
        else {
            return
        }
        let now = clock.nowNanoseconds
        let workloadSatisfied =
            current.switchCount
                >= current.policy.requiredSwitchCount
        let durationSatisfied =
            now >= current.deadlineNanoseconds
        if workloadSatisfied && durationSatisfied {
            complete(
                generation: generation,
                observedAtNanoseconds: now
            )
            return
        }

        let delayNanoseconds: UInt64
        if workloadSatisfied {
            delayNanoseconds =
                current.deadlineNanoseconds - now
        } else {
            delayNanoseconds =
                current.policy.cadenceNanoseconds
        }
        scheduleWake(
            generation: generation,
            afterNanoseconds: delayNanoseconds
        )
    }

    private func scheduleWake(
        generation: UInt64,
        afterNanoseconds nanoseconds: UInt64
    ) {
        guard var current = active,
              current.ownerGeneration == generation
        else {
            return
        }
        current.wakeToken?.cancel()
        current.wakeToken = nil
        current.wakeGeneration &+= 1
        let wakeGeneration =
            current.wakeGeneration
        active = current

        let token = scheduler.schedule(
            afterNanoseconds: nanoseconds
        ) { [weak self] in
            self?.handleWake(
                ownerGeneration: generation,
                wakeGeneration: wakeGeneration
            )
        }

        guard var scheduled = active,
              scheduled.ownerGeneration
                == generation,
              scheduled.wakeGeneration
                == wakeGeneration
        else {
            token.cancel()
            return
        }
        scheduled.wakeToken = token
        active = scheduled
    }

    private func handleWake(
        ownerGeneration: UInt64,
        wakeGeneration: UInt64
    ) {
        guard var current = active,
              current.ownerGeneration
                == ownerGeneration,
              current.wakeGeneration
                == wakeGeneration
        else {
            return
        }
        current.wakeToken?.cancel()
        current.wakeToken = nil
        active = current
        continueRun(
            generation: ownerGeneration
        )
    }

    private func complete(
        generation: UInt64,
        observedAtNanoseconds: UInt64
    ) {
        guard let completed = takeActive(
            generation: generation
        ) else {
            return
        }
        publish(
            phase: .completed,
            run: completed,
            observedAtNanoseconds:
                observedAtNanoseconds
        )
        terminate()
    }

    private func takeActive(
        generation: UInt64? = nil
    ) -> ActiveRun? {
        guard let active,
              generation == nil
                || active.ownerGeneration == generation
        else {
            return nil
        }
        self.active = nil
        active.wakeToken?.cancel()
        return active
    }

    private func publish(
        phase: TabSwitchStressPhase,
        run: ActiveRun,
        observedAtNanoseconds: UInt64
    ) {
        transitionGeneration &+= 1
        let elapsedNanoseconds =
            observedAtNanoseconds
                >= run.startNanoseconds
            ? observedAtNanoseconds
                - run.startNanoseconds
            : 0
        let evidence = TabSwitchStressEvidence(
            ownerGeneration:
                run.ownerGeneration,
            transitionGeneration:
                transitionGeneration,
            phase: phase,
            policy: run.policy,
            attemptCount: run.attemptCount,
            switchCount: run.switchCount,
            requestedTarget:
                run.requestedTarget,
            observedTarget:
                run.observedTarget,
            elapsedNanoseconds:
                elapsedNanoseconds,
            durationSatisfied:
                observedAtNanoseconds
                    >= run.deadlineNanoseconds,
            workloadSatisfied:
                run.switchCount
                    >= run.policy.requiredSwitchCount
        )
        lastEvidence = evidence
        onEvidence(evidence)
    }

}
#endif
