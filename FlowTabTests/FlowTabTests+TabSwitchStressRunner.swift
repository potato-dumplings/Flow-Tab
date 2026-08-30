import Darwin
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testTabSwitchStressSystemClockUsesCrossProcessMonotonicDomain() {
        let before = clock_gettime_nsec_np(CLOCK_MONOTONIC)
        let observed =
            TabSwitchStressSystemMonotonicClock()
                .nowNanoseconds
        let after = clock_gettime_nsec_np(CLOCK_MONOTONIC)

        XCTAssertGreaterThanOrEqual(observed, before)
        XCTAssertLessThanOrEqual(observed, after)
    }

    @MainActor
    func testTabSwitchStressPolicyNormalizesLaunchInputsAndWorkload() {
        let previousArguments =
            FlowTabTestLaunchOptions
                .argumentsOverrideForTesting
        defer {
            FlowTabTestLaunchOptions
                .argumentsOverrideForTesting =
                    previousArguments
        }

        FlowTabTestLaunchOptions
            .argumentsOverrideForTesting = [
                "FlowTab",
                "--flowtab-tab-stress",
                "--flowtab-tab-stress-duration",
                "1.2",
                "--flowtab-tab-stress-interval-ms",
                "400"
            ]
        let launchPolicy =
            TabSwitchStressPolicy.launchPolicy
        XCTAssertEqual(
            launchPolicy.durationNanoseconds,
            1_200_000_000
        )
        XCTAssertEqual(
            launchPolicy.cadenceNanoseconds,
            400_000_000
        )
        XCTAssertEqual(
            launchPolicy.requiredSwitchCount,
            3
        )

        let minimumPolicy =
            TabSwitchStressPolicy(
                durationSeconds: 0,
                cadenceMilliseconds: 0
            )
        XCTAssertEqual(
            minimumPolicy.durationNanoseconds,
            1_000_000_000
        )
        XCTAssertEqual(
            minimumPolicy.cadenceNanoseconds,
            1_000_000
        )
        XCTAssertEqual(
            TabSwitchStressPolicy(
                durationSeconds: .nan,
                cadenceMilliseconds: .infinity
            ),
            TabSwitchStressPolicy(
                durationSeconds: 30,
                cadenceMilliseconds: 20
            )
        )
    }

    @MainActor
    func testTabSwitchStressRunnerRequiresExactWorkloadAndDurationEvidence() {
        let clock = ManualTabSwitchStressClock()
        let scheduler =
            ManualTabSwitchStressScheduler()
        let policy = TabSwitchStressPolicy(
            durationSeconds: 1,
            cadenceMilliseconds: 400
        )
        var selectedTargets:
            [TabSwitchStressTarget] = []
        var evidence:
            [TabSwitchStressEvidence] = []
        var terminationCount = 0
        let runner = TabSwitchStressRunner(
            policyProvider: { policy },
            clock: clock,
            scheduler: scheduler,
            selectTarget: { target in
                selectedTargets.append(target)
                return target
            },
            terminate: {
                terminationCount += 1
            },
            onEvidence: {
                evidence.append($0)
            }
        )

        runner.startIfNeeded()
        XCTAssertEqual(
            selectedTargets,
            [.home]
        )
        XCTAssertEqual(
            scheduler.delays,
            [400_000_000]
        )

        clock.advance(by: 400_000_000)
        scheduler.fire(at: 0)
        clock.advance(by: 400_000_000)
        scheduler.fire(at: 1)

        XCTAssertEqual(
            selectedTargets,
            [.home, .logs, .settings]
        )
        XCTAssertEqual(terminationCount, 0)
        XCTAssertEqual(
            scheduler.delays,
            [
                400_000_000,
                400_000_000,
                200_000_000
            ]
        )

        clock.advance(by: 200_000_000)
        scheduler.fire(at: 2)

        XCTAssertEqual(terminationCount, 1)
        XCTAssertFalse(runner.isRunning)
        XCTAssertEqual(
            evidence.last?.phase,
            .completed
        )
        XCTAssertEqual(
            evidence.last?.switchCount,
            policy.requiredSwitchCount
        )
        XCTAssertEqual(evidence.last?.homeSwitchCount, 1)
        XCTAssertEqual(evidence.last?.logsSwitchCount, 1)
        XCTAssertEqual(evidence.last?.settingsSwitchCount, 1)
        XCTAssertEqual(
            evidence.last?.elapsedNanoseconds,
            1_000_000_000
        )
        XCTAssertEqual(
            evidence.last?.startedAtUptimeNanoseconds,
            0
        )
        XCTAssertEqual(
            evidence.last?.observedAtUptimeNanoseconds,
            1_000_000_000
        )
        XCTAssertTrue(
            evidence.last?.durationSatisfied == true
        )
        XCTAssertTrue(
            evidence.last?.workloadSatisfied == true
        )
        XCTAssertTrue(
            scheduler.tokens
                .allSatisfy(\.isCancelled)
        )
    }

    @MainActor
    func testTabSwitchStressRunnerSlowSchedulingChangesCompletionTimeOnly() {
        let clock = ManualTabSwitchStressClock()
        let scheduler =
            ManualTabSwitchStressScheduler()
        let policy = TabSwitchStressPolicy(
            durationSeconds: 1,
            cadenceMilliseconds: 400
        )
        var selectedTargets:
            [TabSwitchStressTarget] = []
        var terminalEvidence:
            TabSwitchStressEvidence?
        var terminationCount = 0
        let runner = TabSwitchStressRunner(
            policyProvider: { policy },
            clock: clock,
            scheduler: scheduler,
            selectTarget: { target in
                selectedTargets.append(target)
                return target
            },
            terminate: {
                terminationCount += 1
            },
            onEvidence: {
                if $0.phase == .completed {
                    terminalEvidence = $0
                }
            }
        )

        runner.startIfNeeded()
        clock.advance(by: 5_000_000_000)
        scheduler.fire(at: 0)

        XCTAssertEqual(terminationCount, 0)
        XCTAssertEqual(
            selectedTargets,
            [.home, .logs]
        )

        scheduler.fire(at: 1)

        XCTAssertEqual(terminationCount, 1)
        XCTAssertEqual(
            selectedTargets,
            [.home, .logs, .settings]
        )
        XCTAssertEqual(
            terminalEvidence?.switchCount,
            policy.requiredSwitchCount
        )
        XCTAssertEqual(
            terminalEvidence?.elapsedNanoseconds,
            5_000_000_000
        )
        XCTAssertEqual(
            terminalEvidence?.startedAtUptimeNanoseconds,
            0
        )
        XCTAssertEqual(
            terminalEvidence?.observedAtUptimeNanoseconds,
            5_000_000_000
        )
    }

    @MainActor
    func testTabSwitchStressRunnerRetriesMismatchedSelectionReadback() {
        let clock = ManualTabSwitchStressClock()
        let scheduler =
            ManualTabSwitchStressScheduler()
        let policy = TabSwitchStressPolicy(
            durationSeconds: 1,
            cadenceMilliseconds: 1_000
        )
        var selectionAttempt = 0
        var terminationCount = 0
        var terminalEvidence:
            TabSwitchStressEvidence?
        let runner = TabSwitchStressRunner(
            policyProvider: { policy },
            clock: clock,
            scheduler: scheduler,
            selectTarget: { target in
                selectionAttempt += 1
                return selectionAttempt == 1
                    ? nil
                    : target
            },
            terminate: {
                terminationCount += 1
            },
            onEvidence: {
                if $0.phase == .completed {
                    terminalEvidence = $0
                }
            }
        )

        runner.startIfNeeded()
        XCTAssertEqual(
            runner.lastEvidence?.switchCount,
            0
        )

        clock.advance(by: 1_000_000_000)
        scheduler.fire(at: 0)

        XCTAssertEqual(selectionAttempt, 2)
        XCTAssertEqual(terminationCount, 1)
        XCTAssertEqual(
            terminalEvidence?.attemptCount,
            2
        )
        XCTAssertEqual(
            terminalEvidence?.switchCount,
            1
        )
    }

    @MainActor
    func testTabSwitchStressRunnerCancellationRejectsStaleWake() {
        let clock = ManualTabSwitchStressClock()
        let scheduler =
            ManualTabSwitchStressScheduler()
        let policy = TabSwitchStressPolicy(
            durationSeconds: 1,
            cadenceMilliseconds: 1_000
        )
        var selectedTargets:
            [TabSwitchStressTarget] = []
        var phases: [TabSwitchStressPhase] = []
        var terminationCount = 0
        let runner = TabSwitchStressRunner(
            policyProvider: { policy },
            clock: clock,
            scheduler: scheduler,
            selectTarget: { target in
                selectedTargets.append(target)
                return target
            },
            terminate: {
                terminationCount += 1
            },
            onEvidence: {
                phases.append($0.phase)
            }
        )

        runner.startIfNeeded()
        let firstGeneration =
            runner.ownerGeneration
        runner.stop()
        runner.startIfNeeded()
        let secondGeneration =
            runner.ownerGeneration

        XCTAssertEqual(
            secondGeneration,
            firstGeneration &+ 1
        )
        scheduler.fire(
            at: 0,
            includingCancelled: true
        )
        XCTAssertEqual(
            selectedTargets,
            [.home, .home]
        )
        XCTAssertEqual(terminationCount, 0)

        clock.advance(by: 1_000_000_000)
        scheduler.fire(at: 1)

        XCTAssertEqual(terminationCount, 1)
        XCTAssertEqual(
            phases.filter { $0 == .cancelled }.count,
            1
        )
        XCTAssertEqual(
            phases.filter { $0 == .completed }.count,
            1
        )
    }

    @MainActor
    func testTabSwitchStressRunnerSupportsSynchronousScheduling() {
        let clock = ManualTabSwitchStressClock()
        let scheduler =
            SynchronousTabSwitchStressScheduler(
                clock: clock
            )
        let policy = TabSwitchStressPolicy(
            durationSeconds: 1,
            cadenceMilliseconds: 400
        )
        var selectedTargets:
            [TabSwitchStressTarget] = []
        var terminationCount = 0
        let runner = TabSwitchStressRunner(
            policyProvider: { policy },
            clock: clock,
            scheduler: scheduler,
            selectTarget: { target in
                selectedTargets.append(target)
                return target
            },
            terminate: {
                terminationCount += 1
            },
            onEvidence: { _ in }
        )

        runner.startIfNeeded()
        XCTAssertEqual(
            selectedTargets,
            [.home, .logs, .settings]
        )
        XCTAssertEqual(terminationCount, 1)
        XCTAssertFalse(runner.isRunning)
        XCTAssertTrue(
            scheduler.tokens
                .allSatisfy(\.isCancelled)
        )
    }

    @MainActor
    func testTabSwitchStressRunnerDeinitCancelsOwnedWake() {
        let clock = ManualTabSwitchStressClock()
        let scheduler =
            ManualTabSwitchStressScheduler()
        let policy = TabSwitchStressPolicy(
            durationSeconds: 1,
            cadenceMilliseconds: 1_000
        )
        var runner: TabSwitchStressRunner? =
            TabSwitchStressRunner(
                policyProvider: { policy },
                clock: clock,
                scheduler: scheduler,
                selectTarget: { $0 },
                terminate: {},
                onEvidence: { _ in }
            )
        weak var retainedRunner = runner

        runner?.startIfNeeded()
        runner = nil

        XCTAssertNil(retainedRunner)
        XCTAssertTrue(
            scheduler.tokens[0].isCancelled
        )
    }

    @MainActor
    func testTabSwitchStressStartCommandStartsRunnerExactlyOnce() {
        let runner = SpyStressRunner()
        let owner = TabSwitchStressStartCommandOwner(
            notificationName: Notification.Name(
                "flowtab.test.tab-stress.start"
            ),
            runner: runner
        )

        owner.receiveStartCommand()
        owner.receiveStartCommand()

        XCTAssertTrue(owner.didReceiveStartCommand)
        XCTAssertEqual(runner.startCallCount, 1)
    }

    @MainActor
    func testTabSwitchStressPrewarmSettlesAllTabsBeforeStartingRunner() {
        let runner = SpyStressRunner()
        let scheduler = ManualTabSwitchStressScheduler()
        var selectedTargets: [TabSwitchStressTarget] = []
        let owner = TabSwitchStressPrewarmOwner(
            runner: runner,
            scheduler: scheduler,
            selectTarget: { target in
                selectedTargets.append(target)
                return target
            }
        )

        owner.start()
        owner.start()

        XCTAssertEqual(scheduler.tokens.count, 1)
        XCTAssertEqual(runner.startCallCount, 0)

        for index in 0..<4 {
            scheduler.fire(at: index)
            XCTAssertEqual(runner.startCallCount, 0)
        }
        scheduler.fire(at: 4)

        XCTAssertEqual(
            selectedTargets,
            [.home, .logs, .settings, .home]
        )
        XCTAssertEqual(
            scheduler.delays,
            Array(
                repeating:
                    TabSwitchStressPrewarmOwner
                        .sharedSettlementNanoseconds,
                count: 5
            )
        )
        XCTAssertTrue(owner.didComplete)
        XCTAssertFalse(owner.isStarted)
        XCTAssertEqual(runner.startCallCount, 1)
    }

    func testTabSwitchStressLaunchOptionsExposeDeferredStartRoute() {
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-tab-stress",
                FlowTabTestLaunchOptions
                    .tabSwitchStressStartNotificationArgument,
                "flowtab.test.tab-stress.start"
            ],
            environment: [
                FlowTabTestLaunchOptions
                    .uiTestingEnvironmentKey:
                        FlowTabTestLaunchOptions
                            .uiTestingEnvironmentValue
            ]
        ) {
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .tabSwitchStressStartNotificationName,
                "flowtab.test.tab-stress.start"
            )
        }
    }

    func testTabSwitchStressLaunchOptionsExposeTabPrewarm() {
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-tab-stress",
                FlowTabTestLaunchOptions
                    .tabSwitchStressPrewarmTabsArgument
            ],
            environment: [
                FlowTabTestLaunchOptions
                    .uiTestingEnvironmentKey:
                        FlowTabTestLaunchOptions
                            .uiTestingEnvironmentValue
            ]
        ) {
            XCTAssertTrue(
                FlowTabTestLaunchOptions
                    .prewarmsTabsBeforeTabSwitchStress
            )
        }
    }
}
