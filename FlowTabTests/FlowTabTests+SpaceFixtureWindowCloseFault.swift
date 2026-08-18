import CoreGraphics
import Darwin
import Foundation
import XCTest

extension FlowTabTests {
    func testSpaceFixtureWindowCloseFaultTransportParsesExactResolvedEvidence() {
        let notification = Notification(
            name: Notification.Name("window-close"),
            userInfo: [
                "requestGeneration": NSNumber(value: 7),
                "phase": "applied",
                "source": "retryReadback",
                "delayMilliseconds": NSNumber(value: 1_300),
                "awaitsExplicitTrigger": NSNumber(value: true),
                "bundleIdentifier": "fixture.bundle",
                "processIdentifier": NSNumber(value: 4321),
                "targetWindowPlanIndex": NSNumber(value: 2),
                "targetWindowNumber": NSNumber(value: 902),
                "targetWindowIsVisible": NSNumber(value: false),
                "targetCGWindowIsOnScreen": NSNumber(value: false),
                "remainingWindowPlanIndices": [
                    NSNumber(value: 1),
                    NSNumber(value: 3)
                ]
            ]
        )

        XCTAssertEqual(
            SpaceFixtureWindowCloseFaultEvidenceTransport
                .evidence(from: notification),
            SpaceFixtureWindowCloseFaultEvidence(
                requestGeneration: 7,
                phase: .applied,
                source: .retryReadback,
                delayMilliseconds: 1_300,
                awaitsExplicitTrigger: true,
                identity: SpaceFixtureWindowCloseFaultIdentity(
                    bundleIdentifier: "fixture.bundle",
                    processIdentifier: 4321
                ),
                snapshot:
                    SpaceFixtureWindowCloseTopologySnapshot(
                        targetWindowPlanIndex: 2,
                        targetWindowNumber: 902,
                        targetWindowIsVisible: false,
                        targetCGWindowIsOnScreen: false,
                        remainingWindowPlanIndices: [1, 3]
                    )
            )
        )

        var unresolvedUserInfo =
            notification.userInfo ?? [:]
        unresolvedUserInfo["targetWindowIsVisible"] =
            NSNumber(value: true)
        XCTAssertNil(
            SpaceFixtureWindowCloseFaultEvidenceTransport
                .evidence(
                    from: Notification(
                        name: notification.name,
                        userInfo: unresolvedUserInfo
                    )
                )
        )

        let triggerNotification = Notification(
            name: Notification.Name("window-close-trigger"),
            userInfo: [
                "requestGeneration": NSNumber(value: 7),
                "bundleIdentifier": "fixture.bundle",
                "processIdentifier": NSNumber(value: 4321),
                "targetWindowPlanIndex": NSNumber(value: 2)
            ]
        )
        XCTAssertEqual(
            SpaceFixtureWindowCloseFaultTriggerTransport
                .trigger(from: triggerNotification),
            SpaceFixtureWindowCloseFaultTrigger(
                requestGeneration: 7,
                identity: windowCloseFaultIdentity,
                targetWindowPlanIndex: 2
            )
        )

        var unorderedUserInfo = notification.userInfo ?? [:]
        unorderedUserInfo["remainingWindowPlanIndices"] =
            [NSNumber(value: 3), NSNumber(value: 1)]
        XCTAssertNil(
            SpaceFixtureWindowCloseFaultEvidenceTransport
                .evidence(
                    from: Notification(
                        name: notification.name,
                        userInfo: unorderedUserInfo
                    )
                )
        )
    }

    @MainActor
    func testSpaceFixtureWindowCloseFaultWaitsForExactTrigger() {
        let scheduler = ManualSpaceFixtureScheduler()
        let triggerObserver =
            ManualSpaceFixtureWindowCloseTriggerObserver()
        var snapshot = openWindowCloseSnapshot()
        let evidence =
            SpaceFixtureWindowCloseFaultEvidenceRecorder()
        var applyCount = 0
        let owner = makeWindowCloseFaultOwner(
            scheduler: scheduler,
            triggerObserverFactory: {
                route, onTrigger in
                triggerObserver.observe(
                    route: route,
                    onTrigger: onTrigger
                )
            },
            evidence: evidence
        )
        let route =
            SpaceFixtureWindowCloseFaultTriggerRoute(
                notificationName:
                    Notification.Name("trigger")
            )

        owner.start(
            policy: windowCloseFaultPolicy(),
            identity: windowCloseFaultIdentity,
            triggerRoute: route,
            snapshotProvider: { snapshot },
            applyClose: {
                applyCount += 1
                snapshot =
                    self.closedWindowCloseSnapshot()
            },
            onWatchdog: { _ in
                XCTFail("Exact trigger should resolve.")
            }
        )

        XCTAssertEqual(scheduler.scheduledCount, 0)
        XCTAssertEqual(
            evidence.values.last?
                .awaitsExplicitTrigger,
            true
        )
        triggerObserver.send(
            SpaceFixtureWindowCloseFaultTrigger(
                requestGeneration: 2,
                identity: windowCloseFaultIdentity,
                targetWindowPlanIndex: 2
            )
        )
        triggerObserver.send(
            SpaceFixtureWindowCloseFaultTrigger(
                requestGeneration: 1,
                identity:
                    SpaceFixtureWindowCloseFaultIdentity(
                        bundleIdentifier: "other.bundle",
                        processIdentifier: 4321
                    ),
                targetWindowPlanIndex: 2
            )
        )
        triggerObserver.send(
            SpaceFixtureWindowCloseFaultTrigger(
                requestGeneration: 1,
                identity: windowCloseFaultIdentity,
                targetWindowPlanIndex: 1
            )
        )
        XCTAssertEqual(scheduler.scheduledCount, 0)

        let exactTrigger =
            SpaceFixtureWindowCloseFaultTrigger(
                requestGeneration: 1,
                identity: windowCloseFaultIdentity,
                targetWindowPlanIndex: 2
            )
        triggerObserver.send(exactTrigger)
        XCTAssertEqual(scheduler.scheduledDelays, [600])
        XCTAssertTrue(
            triggerObserver.tokens.single?
                .isCancelled == true
        )
        triggerObserver.send(
            exactTrigger,
            includingCancelled: true
        )
        XCTAssertEqual(scheduler.scheduledCount, 1)
        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(applyCount, 1)
        XCTAssertEqual(evidence.values.last?.phase, .applied)

        snapshot = openWindowCloseSnapshot()
        owner.start(
            policy: windowCloseFaultPolicy(),
            identity: windowCloseFaultIdentity,
            triggerRoute: route,
            snapshotProvider: { snapshot },
            applyClose: {
                applyCount += 1
            },
            onWatchdog: { _ in }
        )
        owner.cancel()
        triggerObserver.send(
            SpaceFixtureWindowCloseFaultTrigger(
                requestGeneration: 2,
                identity: windowCloseFaultIdentity,
                targetWindowPlanIndex: 2
            ),
            at: 1,
            includingCancelled: true
        )
        XCTAssertEqual(scheduler.scheduledCount, 1)
        XCTAssertEqual(applyCount, 1)
    }

    @MainActor
    func testSpaceFixtureWindowCloseFaultPublishesScheduledAndAppliedReadbacks() {
        let scheduler = ManualSpaceFixtureScheduler()
        var snapshot = openWindowCloseSnapshot()
        let evidence =
            SpaceFixtureWindowCloseFaultEvidenceRecorder()
        var applyCount = 0
        let owner = makeWindowCloseFaultOwner(
            scheduler: scheduler,
            evidence: evidence
        )

        let generation = owner.start(
            policy: windowCloseFaultPolicy(),
            identity: windowCloseFaultIdentity,
            snapshotProvider: { snapshot },
            applyClose: {
                applyCount += 1
                snapshot = self.closedWindowCloseSnapshot()
            },
            onWatchdog: { _ in
                XCTFail("Resolved close should cancel its watchdog.")
            }
        )

        XCTAssertEqual(generation, 1)
        XCTAssertEqual(
            evidence.values.map(\.phase),
            [.scheduled]
        )
        XCTAssertEqual(scheduler.scheduledDelays, [600])
        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(applyCount, 1)
        XCTAssertEqual(
            evidence.values.map(\.phase),
            [.scheduled, .applied]
        )
        XCTAssertEqual(
            evidence.values.last?.source,
            .closeActionReadback
        )
        XCTAssertEqual(
            evidence.values.last?.snapshot,
            closedWindowCloseSnapshot()
        )
        XCTAssertFalse(owner.isPending)
        XCTAssertTrue(scheduler.token(at: 0).isCancelled)
    }

    @MainActor
    func testSpaceFixtureWindowCloseFaultCompletesFromInitiallySatisfiedReadback() {
        let scheduler = ManualSpaceFixtureScheduler()
        let evidence =
            SpaceFixtureWindowCloseFaultEvidenceRecorder()
        var applyCount = 0
        let owner = makeWindowCloseFaultOwner(
            scheduler: scheduler,
            evidence: evidence
        )

        owner.start(
            policy: windowCloseFaultPolicy(),
            identity: windowCloseFaultIdentity,
            snapshotProvider: {
                self.closedWindowCloseSnapshot()
            },
            applyClose: {
                applyCount += 1
            },
            onWatchdog: { _ in
                XCTFail("Initial readback is already resolved.")
            }
        )

        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(scheduler.scheduledCount, 0)
        XCTAssertEqual(
            evidence.values.map(\.phase),
            [.scheduled, .applied]
        )
        XCTAssertEqual(
            evidence.values.last?.source,
            .initialReadback
        )
    }

    @MainActor
    func testSpaceFixtureWindowCloseFaultRejectsCancelledAndReplacedCallbacks() {
        let scheduler = ManualSpaceFixtureScheduler()
        let evidence =
            SpaceFixtureWindowCloseFaultEvidenceRecorder()
        var applyGenerations: [Int] = []
        var snapshot = openWindowCloseSnapshot()
        let owner = makeWindowCloseFaultOwner(
            scheduler: scheduler,
            evidence: evidence
        )

        owner.start(
            policy: windowCloseFaultPolicy(),
            identity: windowCloseFaultIdentity,
            snapshotProvider: { snapshot },
            applyClose: {
                applyGenerations.append(1)
            },
            onWatchdog: { _ in }
        )
        owner.start(
            policy: windowCloseFaultPolicy(),
            identity: windowCloseFaultIdentity,
            snapshotProvider: { snapshot },
            applyClose: {
                applyGenerations.append(2)
                snapshot = self.closedWindowCloseSnapshot()
            },
            onWatchdog: { _ in }
        )

        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertEqual(applyGenerations, [])
        XCTAssertTrue(scheduler.fire(at: 1))
        XCTAssertEqual(applyGenerations, [2])
        XCTAssertEqual(
            evidence.values.map(\.requestGeneration),
            [1, 2, 2]
        )

        snapshot = openWindowCloseSnapshot()
        owner.start(
            policy: windowCloseFaultPolicy(),
            identity: windowCloseFaultIdentity,
            snapshotProvider: { snapshot },
            applyClose: {
                applyGenerations.append(3)
            },
            onWatchdog: { _ in }
        )
        owner.cancel()
        XCTAssertTrue(
            scheduler.fire(
                at: 2,
                includingCancelled: true
            )
        )
        XCTAssertEqual(applyGenerations, [2])
        XCTAssertFalse(owner.isPending)
    }

    @MainActor
    func testSpaceFixtureWindowCloseFaultRetriesUntilExactReadbackResolves() {
        let scheduler = ManualSpaceFixtureScheduler()
        var snapshot = openWindowCloseSnapshot()
        let evidence =
            SpaceFixtureWindowCloseFaultEvidenceRecorder()
        let owner = makeWindowCloseFaultOwner(
            scheduler: scheduler,
            evidence: evidence
        )

        owner.start(
            policy: windowCloseFaultPolicy(
                retryMilliseconds: 25,
                watchdogMilliseconds: 900
            ),
            identity: windowCloseFaultIdentity,
            snapshotProvider: { snapshot },
            applyClose: {
                snapshot =
                    SpaceFixtureWindowCloseTopologySnapshot(
                        targetWindowPlanIndex: 2,
                        targetWindowNumber: 902,
                        targetWindowIsVisible: false,
                        targetCGWindowIsOnScreen: true,
                        remainingWindowPlanIndices: [1]
                    )
            },
            onWatchdog: { _ in
                XCTFail("Delayed CG readback should resolve.")
            }
        )

        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(
            scheduler.scheduledDelays,
            [600, 25, 900]
        )
        XCTAssertTrue(owner.isPending)
        snapshot = closedWindowCloseSnapshot()
        XCTAssertTrue(scheduler.fire(at: 1))
        XCTAssertEqual(evidence.values.last?.phase, .applied)
        XCTAssertEqual(
            evidence.values.last?.source,
            .retryReadback
        )
        XCTAssertTrue(scheduler.token(at: 2).isCancelled)
    }

    @MainActor
    func testSpaceFixtureWindowCloseFaultWatchdogReportsLastReadback() {
        let scheduler = ManualSpaceFixtureScheduler()
        let snapshot = openWindowCloseSnapshot()
        let evidence =
            SpaceFixtureWindowCloseFaultEvidenceRecorder()
        var failures:
            [SpaceFixtureWindowCloseFaultWatchdogFailure] = []
        let owner = makeWindowCloseFaultOwner(
            scheduler: scheduler,
            evidence: evidence
        )

        owner.start(
            policy: windowCloseFaultPolicy(
                retryMilliseconds: 30,
                watchdogMilliseconds: 800
            ),
            identity: windowCloseFaultIdentity,
            snapshotProvider: { snapshot },
            applyClose: {},
            onWatchdog: { failures.append($0) }
        )

        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertTrue(scheduler.fire(at: 2))
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(
            failures[0].lastObservation.source,
            .closeActionReadback
        )
        XCTAssertEqual(
            failures[0].finalObservation.source,
            .watchdogReadback
        )
        XCTAssertEqual(
            failures[0].finalObservation.snapshot
                .unmetConditions(
                    expectedTargetWindowPlanIndex: 2
                ),
            [
                "targetWindowVisibilityReadback",
                "targetCGWindowReadback",
                "coordinatorTopologyReadback"
            ]
        )
        XCTAssertTrue(scheduler.token(at: 1).isCancelled)
        XCTAssertFalse(owner.isPending)
        XCTAssertEqual(
            evidence.values.map(\.phase),
            [.scheduled]
        )
    }

    @MainActor
    func testSpaceFixtureWindowCloseFaultHandlesSynchronousScheduling() {
        let scheduler =
            ImmediateSpaceFixtureWindowCloseScheduler()
        var snapshot = openWindowCloseSnapshot()
        let evidence =
            SpaceFixtureWindowCloseFaultEvidenceRecorder()
        let owner = makeWindowCloseFaultOwner(
            scheduler: scheduler,
            evidence: evidence
        )

        owner.start(
            policy: windowCloseFaultPolicy(),
            identity: windowCloseFaultIdentity,
            snapshotProvider: { snapshot },
            applyClose: {
                snapshot = self.closedWindowCloseSnapshot()
            },
            onWatchdog: { _ in
                XCTFail("Synchronous action should resolve.")
            }
        )

        XCTAssertEqual(
            evidence.values.map(\.phase),
            [.scheduled, .applied]
        )
        XCTAssertFalse(owner.isPending)
        XCTAssertTrue(scheduler.tokens.single?.isCancelled == true)
    }

    @MainActor
    func testSpaceFixtureWindowCloseFaultLifecyclePressure() {
        let scheduler = ManualSpaceFixtureScheduler()
        var snapshot = openWindowCloseSnapshot()
        let evidence =
            SpaceFixtureWindowCloseFaultEvidenceRecorder()
        var appliedGenerations: [Int] = []
        let owner = makeWindowCloseFaultOwner(
            scheduler: scheduler,
            evidence: evidence
        )

        for expectedGeneration in 1...500 {
            snapshot = openWindowCloseSnapshot()
            owner.start(
                policy: windowCloseFaultPolicy(
                    delayMilliseconds:
                        expectedGeneration % 5
                ),
                identity: windowCloseFaultIdentity,
                snapshotProvider: { snapshot },
                applyClose: {
                    snapshot =
                        self.closedWindowCloseSnapshot()
                    appliedGenerations.append(
                        expectedGeneration
                    )
                },
                onWatchdog: { _ in
                    XCTFail(
                        "Generation \(expectedGeneration) should resolve."
                    )
                }
            )
            XCTAssertTrue(
                scheduler.fire(
                    at: expectedGeneration - 1
                )
            )
        }

        XCTAssertEqual(
            appliedGenerations,
            Array(1...500)
        )
        XCTAssertEqual(
            evidence.values.filter { $0.phase == .scheduled }
                .map(\.requestGeneration),
            Array(1...500)
        )
        XCTAssertEqual(
            evidence.values.filter { $0.phase == .applied }
                .map(\.requestGeneration),
            Array(1...500)
        )
        XCTAssertTrue(
            (0..<500).allSatisfy {
                scheduler.token(at: $0).isCancelled
            }
        )
        XCTAssertFalse(owner.isPending)
    }

    @MainActor
    private func makeWindowCloseFaultOwner(
        scheduler: any SpaceFixtureScheduling,
        triggerObserverFactory:
            SpaceFixtureWindowCloseFaultOwner
                .TriggerObserverFactory? = nil,
        evidence:
            SpaceFixtureWindowCloseFaultEvidenceRecorder
    ) -> SpaceFixtureWindowCloseFaultOwner {
        SpaceFixtureWindowCloseFaultOwner(
            scheduler: scheduler,
            triggerObserverFactory:
                triggerObserverFactory,
            evidencePublisher: {
                evidence.values.append($0)
            }
        )
    }

    private var windowCloseFaultIdentity:
        SpaceFixtureWindowCloseFaultIdentity
    {
        SpaceFixtureWindowCloseFaultIdentity(
            bundleIdentifier: "fixture.bundle",
            processIdentifier: 4321
        )
    }

    private func windowCloseFaultPolicy(
        delayMilliseconds: Int = 600,
        retryMilliseconds: Int = 40,
        watchdogMilliseconds: Int = 1_200
    ) -> SpaceFixtureWindowCloseFaultPolicy {
        SpaceFixtureWindowCloseFaultPolicy(
            targetWindowPlanIndex: 2,
            delayMilliseconds: delayMilliseconds,
            readbackRetryIntervalMilliseconds:
                retryMilliseconds,
            watchdogMilliseconds: watchdogMilliseconds
        )!
    }

    private func openWindowCloseSnapshot()
        -> SpaceFixtureWindowCloseTopologySnapshot
    {
        SpaceFixtureWindowCloseTopologySnapshot(
            targetWindowPlanIndex: 2,
            targetWindowNumber: 902,
            targetWindowIsVisible: true,
            targetCGWindowIsOnScreen: true,
            remainingWindowPlanIndices: [1, 2]
        )
    }

    private func closedWindowCloseSnapshot()
        -> SpaceFixtureWindowCloseTopologySnapshot
    {
        SpaceFixtureWindowCloseTopologySnapshot(
            targetWindowPlanIndex: 2,
            targetWindowNumber: 902,
            targetWindowIsVisible: false,
            targetCGWindowIsOnScreen: false,
            remainingWindowPlanIndices: [1]
        )
    }
}

@MainActor
private final class ManualSpaceFixtureWindowCloseTriggerObserver {
    private struct Observation {
        let token: ManualSpaceFixtureCancellable
        let onTrigger:
            @MainActor (
                SpaceFixtureWindowCloseFaultTrigger
            ) -> Void
    }

    private var observations: [Observation] = []

    var tokens: [ManualSpaceFixtureCancellable] {
        observations.map(\.token)
    }

    func observe(
        route _: SpaceFixtureWindowCloseFaultTriggerRoute,
        onTrigger:
            @escaping @MainActor (
                SpaceFixtureWindowCloseFaultTrigger
            ) -> Void
    ) -> any SpaceFixtureCancellable {
        let token = ManualSpaceFixtureCancellable()
        observations.append(
            Observation(
                token: token,
                onTrigger: onTrigger
            )
        )
        return token
    }

    func send(
        _ trigger: SpaceFixtureWindowCloseFaultTrigger,
        at index: Int = 0,
        includingCancelled: Bool = false
    ) {
        guard observations.indices.contains(index) else {
            return
        }
        let observation = observations[index]
        guard includingCancelled
            || !observation.token.isCancelled
        else {
            return
        }
        observation.onTrigger(trigger)
    }
}

@MainActor
private final class SpaceFixtureWindowCloseFaultEvidenceRecorder {
    var values: [SpaceFixtureWindowCloseFaultEvidence] = []
}

@MainActor
private final class ImmediateSpaceFixtureWindowCloseScheduler:
    SpaceFixtureScheduling
{
    private(set) var tokens:
        [ImmediateSpaceFixtureWindowCloseCancellable] = []

    func schedule(
        afterMilliseconds _: Int,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any SpaceFixtureCancellable {
        let token =
            ImmediateSpaceFixtureWindowCloseCancellable()
        tokens.append(token)
        action()
        return token
    }
}

@MainActor
private final class ImmediateSpaceFixtureWindowCloseCancellable:
    SpaceFixtureCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}
