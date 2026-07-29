import XCTest
@testable import FlowTab

private let terminatePressFeedbackInterval =
    TerminatePressFeedbackPolicy.default.completionInterval

extension FlowTabTests {
    @MainActor
    func testTerminatePressFeedbackCompletionOwnerPublishesScheduledCompletionOnce() {
        let scheduler = ManualTerminatePressFeedbackScheduler()
        let owner = TerminatePressFeedbackCompletionOwner(
            scheduler: scheduler
        )
        var completions: [TerminatePressFeedbackCompletion] = []

        let generation = owner.start(
            after: TerminatePressFeedbackPolicy.default.completionInterval
        ) {
            completions.append($0)
        }

        XCTAssertTrue(owner.isPending)
        XCTAssertEqual(
            scheduler.scheduledIntervals,
            [TerminatePressFeedbackPolicy.default.completionInterval]
        )
        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertFalse(owner.isPending)
        XCTAssertEqual(
            completions,
            [
                TerminatePressFeedbackCompletion(
                    generation: generation,
                    interval:
                        TerminatePressFeedbackPolicy.default
                        .completionInterval
                )
            ]
        )
        XCTAssertFalse(scheduler.fire(at: 0))
        XCTAssertEqual(completions.count, 1)
    }

    @MainActor
    func testTerminatePressFeedbackCompletionOwnerRejectsCancelledAndReplacedCallbacks() {
        let scheduler = ManualTerminatePressFeedbackScheduler()
        let owner = TerminatePressFeedbackCompletionOwner(
            scheduler: scheduler
        )
        var completedGenerations: [Int] = []

        let firstGeneration = owner.start(
            after: terminatePressFeedbackInterval
        ) {
            completedGenerations.append($0.generation)
        }
        let secondGeneration = owner.start(
            after: terminatePressFeedbackInterval
        ) {
            completedGenerations.append($0.generation)
        }

        XCTAssertGreaterThan(secondGeneration, firstGeneration)
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertTrue(owner.isPending)
        XCTAssertTrue(scheduler.fire(at: 1))
        XCTAssertEqual(completedGenerations, [secondGeneration])

        _ = owner.start(after: terminatePressFeedbackInterval) {
            completedGenerations.append($0.generation)
        }
        owner.cancel()
        XCTAssertTrue(
            scheduler.fire(
                at: 2,
                includingCancelled: true
            )
        )
        XCTAssertEqual(completedGenerations, [secondGeneration])
    }

    @MainActor
    func testTerminatePressFeedbackCompletionOwnerSupportsSynchronousScheduler() {
        let scheduler =
            SynchronousTerminatePressFeedbackScheduler()
        let owner = TerminatePressFeedbackCompletionOwner(
            scheduler: scheduler
        )
        var completion: TerminatePressFeedbackCompletion?

        let generation = owner.start(
            after: terminatePressFeedbackInterval
        ) {
            completion = $0
        }

        XCTAssertEqual(
            completion,
            TerminatePressFeedbackCompletion(
                generation: generation,
                interval: terminatePressFeedbackInterval
            )
        )
        XCTAssertFalse(owner.isPending)
        XCTAssertTrue(scheduler.token.isCancelled)
    }

    @MainActor
    func testSwitcherTerminateRequestUsesPressFeedbackCompletionEvidence() {
        let scheduler = ManualTerminatePressFeedbackScheduler()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: terminateScenarioApps()
        )
        let model = LiveSwitcherModel(
            runtimeProjectionService: runtimeProjectionService
        )
        var requestedAppIDs: [String] = []
        model.terminateRequestOverride = { appID in
            requestedAppIDs.append(appID)
            return (sent: true, pid: 42_401)
        }
        let controller = SwitcherPanelController(
            model: model,
            terminatePressFeedbackScheduler: scheduler
        )

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        let selectedAppID = model.selectedApp?.id

        controller.terminateSelectedApp()

        XCTAssertEqual(model.terminatingAppID, selectedAppID)
        XCTAssertNil(model.pendingTerminateRequest)
        XCTAssertTrue(
            controller.terminatePressFeedbackCompletionOwner.isPending
        )
        XCTAssertTrue(requestedAppIDs.isEmpty)

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(requestedAppIDs, [selectedAppID].compactMap { $0 })
        XCTAssertEqual(model.pendingTerminateRequest?.appID, selectedAppID)
        XCTAssertFalse(
            controller.terminatePressFeedbackCompletionOwner.isPending
        )
    }

    @MainActor
    func testSwitcherTerminatePressFeedbackCancellationRejectsLateCompletion() {
        let scheduler = ManualTerminatePressFeedbackScheduler()
        let model = LiveSwitcherModel(
            runtimeProjectionService: RecordingRuntimeProjectionService(
                appSwitcherApps: terminateScenarioApps()
            )
        )
        var terminateRequestCount = 0
        model.terminateRequestOverride = { _ in
            terminateRequestCount += 1
            return (sent: true, pid: 42_402)
        }
        let controller = SwitcherPanelController(
            model: model,
            terminatePressFeedbackScheduler: scheduler
        )

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        controller.terminateSelectedApp()
        controller.removeEventMonitors()

        XCTAssertFalse(
            controller.terminatePressFeedbackCompletionOwner.isPending
        )
        XCTAssertNil(model.terminatingAppID)
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertEqual(terminateRequestCount, 0)
        XCTAssertNil(model.pendingTerminateRequest)
    }

    @MainActor
    func testTerminatePressFeedbackCompletionOwnerPressurePreservesGenerationOracle() {
        let scheduler = ManualTerminatePressFeedbackScheduler()
        let owner = TerminatePressFeedbackCompletionOwner(
            scheduler: scheduler
        )
        var completedGenerations: [Int] = []
        let cycleCount = 500

        for cycle in 0..<cycleCount {
            let generation = owner.start(
                after: terminatePressFeedbackInterval
            ) {
                completedGenerations.append($0.generation)
            }
            if cycle.isMultiple(of: 2) {
                owner.cancel()
            }
            XCTAssertTrue(
                scheduler.fire(
                    at: cycle,
                    includingCancelled: true
                )
            )
            if cycle.isMultiple(of: 2) {
                XCTAssertFalse(
                    completedGenerations.contains(generation)
                )
            }
        }

        XCTAssertEqual(completedGenerations.count, cycleCount / 2)
        XCTAssertEqual(
            completedGenerations,
            completedGenerations.sorted()
        )
        XCTAssertFalse(owner.isPending)
    }
}

@MainActor
private final class ManualTerminatePressFeedbackScheduler:
    TerminatePressFeedbackScheduling
{
    private struct ScheduledAction {
        let interval: TimeInterval
        let token: ManualTerminatePressFeedbackToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var scheduledIntervals: [TimeInterval] {
        scheduled.map(\.interval)
    }

    func scheduleCompletion(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminatePressFeedbackCancellable {
        let token = ManualTerminatePressFeedbackToken()
        scheduled.append(
            ScheduledAction(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    @discardableResult
    func fire(
        at index: Int,
        includingCancelled: Bool = false
    ) -> Bool {
        guard scheduled.indices.contains(index) else { return false }
        let scheduledAction = scheduled[index]
        guard !scheduledAction.token.didFire else { return false }
        guard includingCancelled || !scheduledAction.token.isCancelled
        else {
            return false
        }
        scheduledAction.token.didFire = true
        scheduledAction.action()
        return true
    }
}

@MainActor
private final class ManualTerminatePressFeedbackToken:
    TerminatePressFeedbackCancellable
{
    private(set) var isCancelled = false
    var didFire = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
private final class SynchronousTerminatePressFeedbackScheduler:
    TerminatePressFeedbackScheduling
{
    let token = ManualTerminatePressFeedbackToken()

    func scheduleCompletion(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminatePressFeedbackCancellable {
        action()
        return token
    }
}
