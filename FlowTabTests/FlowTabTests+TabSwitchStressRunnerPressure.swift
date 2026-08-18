import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testTabSwitchStressRunnerExecutesFiveThousandPlannedSwitches() {
        let clock = ManualTabSwitchStressClock()
        let scheduler =
            ManualTabSwitchStressScheduler()
        let policy = TabSwitchStressPolicy(
            durationSeconds: 5,
            cadenceMilliseconds: 1
        )
        var selectionCount: UInt64 = 0
        var sequenceMatches = true
        var terminalEvidence:
            TabSwitchStressEvidence?
        var terminationCount = 0
        let runner = TabSwitchStressRunner(
            policyProvider: { policy },
            clock: clock,
            scheduler: scheduler,
            selectTarget: { target in
                let targets =
                    TabSwitchStressTarget.allCases
                let expected = targets[
                    Int(
                        selectionCount
                            % UInt64(targets.count)
                    )
                ]
                sequenceMatches =
                    sequenceMatches
                    && target == expected
                selectionCount &+= 1
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
        var nextWake = 0
        while runner.isRunning {
            let delay = scheduler.delays[nextWake]
            clock.advance(by: delay)
            scheduler.fire(at: nextWake)
            nextWake += 1
        }

        XCTAssertTrue(sequenceMatches)
        XCTAssertEqual(
            selectionCount,
            policy.requiredSwitchCount
        )
        XCTAssertEqual(nextWake, 5_000)
        XCTAssertEqual(terminationCount, 1)
        XCTAssertEqual(
            terminalEvidence?.switchCount,
            5_000
        )
        XCTAssertEqual(
            terminalEvidence?.elapsedNanoseconds,
            5_000_000_000
        )
        XCTAssertTrue(
            scheduler.tokens
                .allSatisfy(\.isCancelled)
        )
    }

    @MainActor
    func testTabSwitchStressRunnerReplacementPressureRejectsEveryStaleWake() {
        let clock = ManualTabSwitchStressClock()
        let scheduler =
            ManualTabSwitchStressScheduler()
        let policy = TabSwitchStressPolicy(
            durationSeconds: 1,
            cadenceMilliseconds: 1_000
        )
        var selectionCount = 0
        var cancelledCount = 0
        var completedCount = 0
        var terminationCount = 0
        let runner = TabSwitchStressRunner(
            policyProvider: { policy },
            clock: clock,
            scheduler: scheduler,
            selectTarget: { target in
                selectionCount += 1
                return target
            },
            terminate: {
                terminationCount += 1
            },
            onEvidence: {
                switch $0.phase {
                case .cancelled:
                    cancelledCount += 1
                case .completed:
                    completedCount += 1
                case .started,
                     .selectionObserved:
                    break
                }
            }
        )

        for _ in 0..<1_000 {
            runner.startIfNeeded()
            runner.stop()
        }
        runner.startIfNeeded()

        for index in 0..<1_000 {
            scheduler.fire(
                at: index,
                includingCancelled: true
            )
        }
        XCTAssertEqual(selectionCount, 1_001)
        XCTAssertEqual(terminationCount, 0)

        clock.advance(by: 1_000_000_000)
        scheduler.fire(at: 1_000)

        XCTAssertEqual(cancelledCount, 1_000)
        XCTAssertEqual(completedCount, 1)
        XCTAssertEqual(terminationCount, 1)
        XCTAssertEqual(
            runner.ownerGeneration,
            1_001
        )
        XCTAssertTrue(
            scheduler.tokens
                .allSatisfy(\.isCancelled)
        )
    }
}
