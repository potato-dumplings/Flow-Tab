import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testPanelPresentationDiagnosticProbeUsesNamedScheduleAndMeasuredClock() {
        let scheduler = ManualPanelPresentationDiagnosticScheduler()
        let owner = PanelPresentationDiagnosticProbeOwner(
            scheduler: scheduler
        )
        var nowMs = 106.0
        var probes: [PanelPresentationDiagnosticProbe] = []

        let generation = owner.start(
            presentationGeneration: 7,
            kind: "global",
            showStartMs: 100,
            presentedMs: 104,
            now: { nowMs },
            onProbe: { probes.append($0) }
        )

        XCTAssertEqual(scheduler.scheduledKinds, [.nextMainTurn])
        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(
            probes,
            [
                PanelPresentationDiagnosticProbe(
                    source: .nextMainTurn,
                    observationGeneration: generation,
                    presentationGeneration: 7,
                    kind: "global",
                    showStartMs: 100,
                    presentedMs: 104,
                    probeMs: 106
                )
            ]
        )
        XCTAssertEqual(
            scheduler.scheduledKinds,
            [
                .nextMainTurn,
                .frameSample(
                    PanelPresentationDiagnosticPolicy.default
                        .frameSampleInterval
                )
            ]
        )

        nowMs = 410
        XCTAssertTrue(scheduler.fire(at: 1))

        XCTAssertEqual(probes.count, 2)
        XCTAssertEqual(probes.last?.source, .scheduledFrameSample)
        XCTAssertEqual(probes.last?.elapsedMs, 310)
        XCTAssertEqual(probes.last?.sincePresentedMs, 306)
        XCTAssertFalse(owner.isPending)
    }

    @MainActor
    func testPanelPresentationDiagnosticProbeRejectsReplacedAndCancelledCallbacks() {
        let scheduler = ManualPanelPresentationDiagnosticScheduler()
        let owner = PanelPresentationDiagnosticProbeOwner(
            scheduler: scheduler
        )
        var probes: [PanelPresentationDiagnosticProbe] = []

        let firstGeneration = owner.start(
            presentationGeneration: 1,
            kind: "first",
            showStartMs: 1,
            presentedMs: 2,
            now: { 3 },
            onProbe: { probes.append($0) }
        )
        let secondGeneration = owner.start(
            presentationGeneration: 2,
            kind: "second",
            showStartMs: 10,
            presentedMs: 20,
            now: { 30 },
            onProbe: { probes.append($0) }
        )

        XCTAssertGreaterThan(secondGeneration, firstGeneration)
        XCTAssertTrue(scheduler.token(at: 0).isCancelled)
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertTrue(probes.isEmpty)
        XCTAssertTrue(scheduler.fire(at: 1))
        XCTAssertEqual(probes.map(\.observationGeneration), [secondGeneration])
        XCTAssertEqual(probes.map(\.source), [.nextMainTurn])

        owner.cancel()

        XCTAssertTrue(scheduler.token(at: 2).isCancelled)
        XCTAssertTrue(
            scheduler.fire(
                at: 2,
                includingCancelled: true
            )
        )
        XCTAssertEqual(probes.map(\.source), [.nextMainTurn])
        XCTAssertFalse(owner.isPending)
    }

    @MainActor
    func testPresentationEndCancelsPanelDiagnosticFrameSample() {
        let scheduler = ManualPanelPresentationDiagnosticScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    RecordingRuntimeProjectionService(
                        appSwitcherApps: terminateScenarioApps()
                    )
            ),
            panelPresentationDiagnosticScheduler: scheduler
        )

        XCTAssertTrue(
            controller.presentGlobalHotkeySessionForTesting()
        )
        XCTAssertTrue(
            controller.hasPendingPanelPresentationDiagnosticProbe
        )

        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(
            controller.lastPanelPresentationDiagnosticProbe?.source,
            .nextMainTurn
        )

        controller.endPresentationSession()

        XCTAssertFalse(
            controller.hasPendingPanelPresentationDiagnosticProbe
        )
        XCTAssertTrue(scheduler.token(at: 1).isCancelled)
        XCTAssertTrue(
            scheduler.fire(
                at: 1,
                includingCancelled: true
            )
        )
        XCTAssertEqual(
            controller.lastPanelPresentationDiagnosticProbe?.source,
            .nextMainTurn
        )
    }

    @MainActor
    func testPanelPresentationDiagnosticProbePressurePreservesGenerationOracle() {
        let scheduler = ManualPanelPresentationDiagnosticScheduler()
        let owner = PanelPresentationDiagnosticProbeOwner(
            scheduler: scheduler
        )
        var nowMs = 0.0
        var frameSampleGenerations: [Int] = []
        let cycleCount = 500

        for cycle in 0..<cycleCount {
            let nextMainTurnIndex = scheduler.scheduledCount
            let generation = owner.start(
                presentationGeneration: cycle,
                kind: "pressure",
                showStartMs: 0,
                presentedMs: 0,
                now: { nowMs },
                onProbe: {
                    if $0.source == .scheduledFrameSample {
                        frameSampleGenerations.append(
                            $0.observationGeneration
                        )
                    }
                }
            )
            nowMs = Double(cycle * 100)
            if cycle.isMultiple(of: 2) {
                owner.cancel()
                XCTAssertTrue(
                    scheduler.fire(
                        at: nextMainTurnIndex,
                        includingCancelled: true
                    )
                )
                XCTAssertFalse(
                    frameSampleGenerations.contains(generation)
                )
                continue
            }

            XCTAssertTrue(scheduler.fire(at: nextMainTurnIndex))
            let frameSampleIndex = scheduler.scheduledCount - 1
            nowMs += 75
            XCTAssertTrue(scheduler.fire(at: frameSampleIndex))
        }

        XCTAssertEqual(
            frameSampleGenerations.count,
            cycleCount / 2
        )
        XCTAssertEqual(
            frameSampleGenerations,
            frameSampleGenerations.sorted()
        )
        XCTAssertFalse(owner.isPending)
    }
}

@MainActor
private final class ManualPanelPresentationDiagnosticScheduler:
    PanelPresentationDiagnosticScheduling
{
    enum ScheduledKind: Equatable {
        case nextMainTurn
        case frameSample(TimeInterval)
    }

    private struct ScheduledAction {
        let kind: ScheduledKind
        let token: ManualPanelPresentationDiagnosticToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var scheduledKinds: [ScheduledKind] {
        scheduled.map(\.kind)
    }

    var scheduledCount: Int {
        scheduled.count
    }

    func scheduleNextMainTurn(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelPresentationDiagnosticCancellable {
        schedule(kind: .nextMainTurn, action: action)
    }

    func scheduleFrameSample(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelPresentationDiagnosticCancellable {
        schedule(kind: .frameSample(interval), action: action)
    }

    func token(at index: Int) -> ManualPanelPresentationDiagnosticToken {
        scheduled[index].token
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

    private func schedule(
        kind: ScheduledKind,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelPresentationDiagnosticCancellable {
        let token = ManualPanelPresentationDiagnosticToken()
        scheduled.append(
            ScheduledAction(
                kind: kind,
                token: token,
                action: action
            )
        )
        return token
    }
}

@MainActor
private final class ManualPanelPresentationDiagnosticToken:
    PanelPresentationDiagnosticCancellable
{
    private(set) var isCancelled = false
    var didFire = false

    func cancel() {
        isCancelled = true
    }
}
