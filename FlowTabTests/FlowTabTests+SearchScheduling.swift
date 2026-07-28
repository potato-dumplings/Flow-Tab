import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testSearchSchedulingKeepsOnlyLatestDebounceAndRevision() {
        let scheduler = ManualSwitcherSearchScheduler()
        let clock = ManualSwitcherSearchClock()
        let executor = ManualSwitcherSearchExecutor()
        let model = makeSearchSchedulingModel(
            scheduler: scheduler,
            clock: clock,
            executor: executor
        )
        var resultPublicationCount = 0
        model.onSearchStateChanged = {
            resultPublicationCount += 1
        }

        XCTAssertTrue(model.appendSearchQuery("s"))
        XCTAssertEqual(scheduler.entries.count, 1)
        XCTAssertEqual(scheduler.entries[0].interval, 0.020)
        XCTAssertEqual(scheduler.activeEntryCount, 1)

        XCTAssertTrue(model.appendSearchQuery("a"))
        XCTAssertEqual(scheduler.entries.count, 2)
        XCTAssertTrue(scheduler.entries[0].token.isCancelled)
        XCTAssertEqual(scheduler.activeEntryCount, 1)

        scheduler.fire(at: 0, ignoringCancellation: true)
        XCTAssertTrue(executor.entries.isEmpty)

        scheduler.fire(at: 1)
        XCTAssertEqual(executor.entries.count, 1)
        XCTAssertEqual(executor.entries[0].input.query, "sa")
        XCTAssertNil(model.searchSchedulingOwner.pendingDebounceToken)
        XCTAssertNotNil(model.searchSchedulingOwner.pendingComputationToken)

        clock.monotonicNanoseconds = 5_000_000
        executor.complete(at: 0)

        XCTAssertNil(model.searchSchedulingOwner.pendingComputationToken)
        XCTAssertEqual(
            model.searchViewState.results.map(\.primaryText),
            ["Safari"]
        )
        XCTAssertEqual(model.searchSchedulingOwner.debounceInterval, 0.014)
        XCTAssertEqual(resultPublicationCount, 1)
    }

    @MainActor
    func testSearchSchedulingRejectsCancelledAndOutOfOrderCompletions() {
        let scheduler = ManualSwitcherSearchScheduler()
        let clock = ManualSwitcherSearchClock()
        let executor = ManualSwitcherSearchExecutor()
        let model = makeSearchSchedulingModel(
            scheduler: scheduler,
            clock: clock,
            executor: executor
        )
        var resultPublicationCount = 0
        model.onSearchStateChanged = {
            resultPublicationCount += 1
        }

        XCTAssertTrue(model.appendSearchQuery("f"))
        scheduler.fire(at: 0)
        XCTAssertEqual(executor.entries.count, 1)

        XCTAssertTrue(model.appendSearchQuery("a"))
        scheduler.fire(at: 1)
        XCTAssertEqual(executor.entries.count, 2)
        XCTAssertTrue(executor.entries[0].token.isCancelled)

        clock.monotonicNanoseconds = 8_000_000
        executor.complete(at: 1)
        let acceptedResults = model.searchViewState.results
        XCTAssertEqual(acceptedResults.map(\.primaryText), ["Safari"])

        executor.complete(at: 0, ignoringCancellation: true)
        XCTAssertEqual(model.searchViewState.results, acceptedResults)
        XCTAssertEqual(resultPublicationCount, 1)

        XCTAssertTrue(model.appendSearchQuery("r"))
        model.cancelPendingSearchComputation()
        scheduler.fire(at: 2, ignoringCancellation: true)
        XCTAssertEqual(executor.entries.count, 2)
        XCTAssertNil(model.searchSchedulingOwner.pendingDebounceToken)
        XCTAssertNil(model.searchSchedulingOwner.pendingComputationToken)
    }

    @MainActor
    func testSearchSchedulingHandlesSynchronousSchedulerAndExecutorCallbacks() {
        let scheduler = ManualSwitcherSearchScheduler()
        scheduler.firesSynchronously = true
        let clock = ManualSwitcherSearchClock()
        clock.monotonicNanoseconds = 100
        let executor = ManualSwitcherSearchExecutor()
        executor.completesSynchronously = true
        let model = makeSearchSchedulingModel(
            scheduler: scheduler,
            clock: clock,
            executor: executor
        )

        XCTAssertTrue(model.appendSearchQuery("vsc"))

        XCTAssertEqual(
            model.searchViewState.results.map(\.primaryText),
            ["Visual Studio Code"]
        )
        XCTAssertNil(model.searchSchedulingOwner.pendingDebounceToken)
        XCTAssertNil(model.searchSchedulingOwner.pendingComputationToken)
        XCTAssertEqual(scheduler.activeEntryCount, 0)
        XCTAssertEqual(executor.activeEntryCount, 0)
    }

    @MainActor
    func testSearchSchedulingLatencyChangesCompletionTimeOnly() {
        var resultIDsBySchedulerLatency: [[String]] = []

        for schedulerLatency in [20_000_000, 2_000_000_000] as [UInt64] {
            let scheduler = ManualSwitcherSearchScheduler()
            let clock = ManualSwitcherSearchClock()
            let executor = ManualSwitcherSearchExecutor()
            let model = makeSearchSchedulingModel(
                scheduler: scheduler,
                clock: clock,
                executor: executor
            )

            XCTAssertTrue(model.appendSearchQuery("wechat"))
            clock.monotonicNanoseconds = schedulerLatency
            scheduler.fire(at: 0)
            clock.monotonicNanoseconds += 5_000_000
            executor.complete(at: 0)

            resultIDsBySchedulerLatency.append(
                model.searchViewState.results.map(\.id)
            )
            XCTAssertEqual(model.searchSchedulingOwner.debounceInterval, 0.014)
        }

        XCTAssertEqual(resultIDsBySchedulerLatency.count, 2)
        XCTAssertEqual(
            resultIDsBySchedulerLatency[0],
            resultIDsBySchedulerLatency[1]
        )
        XCTAssertFalse(resultIDsBySchedulerLatency[0].isEmpty)
    }

    @MainActor
    func testSearchSchedulingPressureRetainsOneLatestOwner() {
        let scheduler = ManualSwitcherSearchScheduler()
        let clock = ManualSwitcherSearchClock()
        let executor = ManualSwitcherSearchExecutor()
        let model = makeSearchSchedulingModel(
            scheduler: scheduler,
            clock: clock,
            executor: executor
        )

        for index in 0..<2_000 {
            if index.isMultiple(of: 2) {
                XCTAssertTrue(model.appendSearchQuery("s"))
            } else {
                XCTAssertTrue(model.deleteSearchQueryBackward())
            }
        }

        XCTAssertEqual(scheduler.entries.count, 2_000)
        XCTAssertEqual(scheduler.activeEntryCount, 1)
        for index in 0..<1_999 {
            scheduler.fire(at: index, ignoringCancellation: true)
        }
        XCTAssertTrue(executor.entries.isEmpty)

        scheduler.fire(at: 1_999)
        XCTAssertEqual(executor.entries.count, 1)
        XCTAssertEqual(executor.entries[0].input.query, "")
        executor.complete(at: 0)

        XCTAssertEqual(scheduler.activeEntryCount, 0)
        XCTAssertEqual(executor.activeEntryCount, 0)
        XCTAssertNil(model.searchSchedulingOwner.pendingDebounceToken)
        XCTAssertNil(model.searchSchedulingOwner.pendingComputationToken)
    }

    func testSearchSchedulingPolicyKeepsNamedAdaptiveBoundaries() {
        let policy = SwitcherSearchSchedulingPolicy.standard

        XCTAssertEqual(
            policy.debounceInterval(
                afterComputationNanoseconds: 6_000_000
            ),
            0.014
        )
        XCTAssertEqual(
            policy.debounceInterval(
                afterComputationNanoseconds: 6_000_001
            ),
            0.025
        )
        XCTAssertEqual(
            policy.debounceInterval(
                afterComputationNanoseconds: 10_000_001
            ),
            0.035
        )
        XCTAssertEqual(
            policy.debounceInterval(
                afterComputationNanoseconds: 16_000_001
            ),
            0.045
        )
    }

    @MainActor
    private func makeSearchSchedulingModel(
        scheduler: ManualSwitcherSearchScheduler,
        clock: ManualSwitcherSearchClock,
        executor: ManualSwitcherSearchExecutor
    ) -> LiveSwitcherModel {
        let model = LiveSwitcherModel(
            runtimeProjectionService: RecordingRuntimeProjectionService(),
            searchSchedulingOwner: SwitcherSearchSchedulingOwner(
                scheduler: scheduler,
                clock: clock,
                computationExecutor: executor
            )
        )
        model.searchCoordinator.rebuildIndex(
            with: runtimeSearchIndexProjection(from: searchSampleApps())
        )
        XCTAssertTrue(
            model.searchCoordinator.activate(defaultScope: .app)
        )
        model.publishSearchStateIfNeeded()
        return model
    }
}

private final class ManualSwitcherSearchToken:
    SwitcherSearchCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
private final class ManualSwitcherSearchScheduler:
    SwitcherSearchScheduling
{
    @MainActor
    final class Entry {
        let interval: TimeInterval
        let token: ManualSwitcherSearchToken
        let action: @MainActor @Sendable () -> Void
        private(set) var didFire = false

        init(
            interval: TimeInterval,
            token: ManualSwitcherSearchToken,
            action: @escaping @MainActor @Sendable () -> Void
        ) {
            self.interval = interval
            self.token = token
            self.action = action
        }

        func fire(ignoringCancellation: Bool) {
            guard !didFire else { return }
            didFire = true
            guard ignoringCancellation || !token.isCancelled else { return }
            action()
        }
    }

    var firesSynchronously = false
    private(set) var entries: [Entry] = []

    var activeEntryCount: Int {
        entries.filter {
            !$0.didFire && !$0.token.isCancelled
        }.count
    }

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any SwitcherSearchCancellable {
        let token = ManualSwitcherSearchToken()
        let entry = Entry(
            interval: interval,
            token: token,
            action: action
        )
        entries.append(entry)
        if firesSynchronously {
            entry.fire(ignoringCancellation: false)
        }
        return token
    }

    func fire(
        at index: Int,
        ignoringCancellation: Bool = false
    ) {
        entries[index].fire(
            ignoringCancellation: ignoringCancellation
        )
    }
}

@MainActor
private final class ManualSwitcherSearchClock:
    SwitcherSearchClockReading
{
    var monotonicNanoseconds: UInt64 = 0
}

@MainActor
private final class ManualSwitcherSearchExecutor:
    SwitcherSearchComputationExecuting
{
    @MainActor
    final class Entry {
        let input: SwitcherSearchCoordinator.ComputationInput
        let token: ManualSwitcherSearchToken
        let completion: @MainActor @Sendable (
            SwitcherSearchCoordinator.ComputationOutput
        ) -> Void
        private(set) var didComplete = false

        init(
            input: SwitcherSearchCoordinator.ComputationInput,
            token: ManualSwitcherSearchToken,
            completion: @escaping @MainActor @Sendable (
                SwitcherSearchCoordinator.ComputationOutput
            ) -> Void
        ) {
            self.input = input
            self.token = token
            self.completion = completion
        }

        func complete(ignoringCancellation: Bool) {
            guard !didComplete else { return }
            didComplete = true
            guard ignoringCancellation || !token.isCancelled else { return }
            completion(
                SwitcherSearchCoordinator.computeOutput(from: input)
            )
        }
    }

    var completesSynchronously = false
    private(set) var entries: [Entry] = []

    var activeEntryCount: Int {
        entries.filter {
            !$0.didComplete && !$0.token.isCancelled
        }.count
    }

    func execute(
        input: SwitcherSearchCoordinator.ComputationInput,
        completion: @escaping @MainActor @Sendable (
            SwitcherSearchCoordinator.ComputationOutput
        ) -> Void
    ) -> any SwitcherSearchCancellable {
        let token = ManualSwitcherSearchToken()
        let entry = Entry(
            input: input,
            token: token,
            completion: completion
        )
        entries.append(entry)
        if completesSynchronously {
            entry.complete(ignoringCancellation: false)
        }
        return token
    }

    func complete(
        at index: Int,
        ignoringCancellation: Bool = false
    ) {
        entries[index].complete(
            ignoringCancellation: ignoringCancellation
        )
    }
}
