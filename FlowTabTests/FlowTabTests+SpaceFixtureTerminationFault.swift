import XCTest

extension FlowTabTests {
    func testTerminationFaultEvidenceTransportParsesExactAcknowledgement() {
        let notification = Notification(
            name: Notification.Name(
                "test.fixture.termination"
            ),
            userInfo: [
                "requestGeneration": NSNumber(value: 7),
                "phase": "applied",
                "source": "applicationShouldTerminate",
                "delayMilliseconds": NSNumber(value: 1_200),
                "bundleIdentifier": "com.example.fixture",
                "processIdentifier": NSNumber(value: 4_321)
            ]
        )

        XCTAssertEqual(
            SpaceFixtureTerminationFaultEvidenceTransport
                .evidence(from: notification),
            SpaceFixtureTerminationFaultEvidence(
                requestGeneration: 7,
                phase: .applied,
                source: .applicationShouldTerminate,
                delayMilliseconds: 1_200,
                identity:
                    SpaceFixtureTerminationFaultIdentity(
                        bundleIdentifier:
                            "com.example.fixture",
                        processIdentifier: 4_321
                    )
            )
        )
        XCTAssertNil(
            SpaceFixtureTerminationFaultEvidenceTransport
                .evidence(
                    from: Notification(
                        name: notification.name,
                        userInfo: [
                            "requestGeneration":
                                NSNumber(value: 8),
                            "phase": "elapsed",
                            "source":
                                "applicationShouldTerminate",
                            "delayMilliseconds":
                                NSNumber(value: 1_200),
                            "bundleIdentifier":
                                "com.example.fixture",
                            "processIdentifier":
                                NSNumber(value: 4_321)
                        ]
                    )
                )
        )
    }

    @MainActor
    func testTerminationFaultOwnerPublishesScheduledThenAppliedEvidence() {
        let scheduler = ManualSpaceFixtureScheduler()
        var evidence: [SpaceFixtureTerminationFaultEvidence] =
            []
        var applyCount = 0
        let owner = makeTerminationFaultOwner(
            scheduler: scheduler
        ) {
            evidence.append($0)
        }

        let disposition = owner.request(
            source: .applicationShouldTerminate
        ) {
            applyCount += 1
        }

        XCTAssertEqual(
            disposition,
            .scheduled(requestGeneration: 1)
        )
        XCTAssertTrue(owner.isPending)
        XCTAssertEqual(scheduler.scheduledDelays, [1_200])
        XCTAssertEqual(
            evidence,
            [
                makeTerminationFaultEvidence(
                    generation: 1,
                    phase: .scheduled,
                    source: .applicationShouldTerminate
                )
            ]
        )
        XCTAssertEqual(applyCount, 0)

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertFalse(owner.isPending)
        XCTAssertEqual(applyCount, 1)
        XCTAssertTrue(scheduler.token(at: 0).isCancelled)
        XCTAssertEqual(
            evidence,
            [
                makeTerminationFaultEvidence(
                    generation: 1,
                    phase: .scheduled,
                    source: .applicationShouldTerminate
                ),
                makeTerminationFaultEvidence(
                    generation: 1,
                    phase: .applied,
                    source: .applicationShouldTerminate
                )
            ]
        )
    }

    @MainActor
    func testTerminationFaultOwnerKeepsFirstRequestAcrossDuplicateSource() {
        let scheduler = ManualSpaceFixtureScheduler()
        var appliedSources:
            [SpaceFixtureTerminationFaultRequestSource] = []
        let owner = makeTerminationFaultOwner(
            scheduler: scheduler
        ) { _ in }

        XCTAssertEqual(
            owner.request(source: .terminationSignal) {
                appliedSources.append(.terminationSignal)
            },
            .scheduled(requestGeneration: 1)
        )
        XCTAssertEqual(
            owner.request(
                source: .applicationShouldTerminate
            ) {
                appliedSources.append(
                    .applicationShouldTerminate
                )
            },
            .alreadyPending(requestGeneration: 1)
        )
        XCTAssertEqual(scheduler.scheduledCount, 1)

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(
            appliedSources,
            [.terminationSignal]
        )
        XCTAssertEqual(
            owner.lastEvidence?.source,
            .terminationSignal
        )
        XCTAssertEqual(
            owner.lastEvidence?.phase,
            .applied
        )
    }

    @MainActor
    func testTerminationFaultOwnerCancellationRejectsLateScheduledWork() {
        let scheduler = ManualSpaceFixtureScheduler()
        var appliedGenerations: [Int] = []
        let owner = makeTerminationFaultOwner(
            scheduler: scheduler
        ) { _ in }

        owner.request(source: .applicationShouldTerminate) {
            appliedGenerations.append(1)
        }
        owner.cancel()

        XCTAssertFalse(owner.isPending)
        XCTAssertTrue(scheduler.token(at: 0).isCancelled)
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertTrue(appliedGenerations.isEmpty)

        XCTAssertEqual(
            owner.request(source: .terminationSignal) {
                appliedGenerations.append(2)
            },
            .scheduled(requestGeneration: 2)
        )
        XCTAssertTrue(scheduler.fire(at: 1))
        XCTAssertEqual(appliedGenerations, [2])
    }

    @MainActor
    func testTerminationFaultOwnerSupportsSynchronousScheduler() {
        let scheduler =
            ImmediateSpaceFixtureTerminationScheduler()
        var phases:
            [SpaceFixtureTerminationFaultEvidencePhase] =
            []
        var applyCount = 0
        let owner = SpaceFixtureTerminationFaultOwner(
            policy:
                SpaceFixtureTerminationFaultPolicy(
                    delayMilliseconds: 1_200
                )!,
            identity: terminationFaultIdentity,
            scheduler: scheduler,
            evidencePublisher: {
                phases.append($0.phase)
            }
        )

        XCTAssertEqual(
            owner.request(source: .terminationSignal) {
                applyCount += 1
            },
            .scheduled(requestGeneration: 1)
        )

        XCTAssertEqual(phases, [.scheduled, .applied])
        XCTAssertEqual(applyCount, 1)
        XCTAssertFalse(owner.isPending)
        XCTAssertTrue(scheduler.token.isCancelled)
    }

    @MainActor
    func testTerminationFaultOwnerLifecyclePressureAppliesEveryGenerationOnce() {
        let scheduler = ManualSpaceFixtureScheduler()
        var scheduledGenerations: [Int] = []
        var appliedGenerations: [Int] = []
        var actionGenerations: [Int] = []
        let owner = makeTerminationFaultOwner(
            scheduler: scheduler
        ) { evidence in
            switch evidence.phase {
            case .scheduled:
                scheduledGenerations.append(
                    evidence.requestGeneration
                )
            case .applied:
                appliedGenerations.append(
                    evidence.requestGeneration
                )
            }
        }

        for generation in 1...500 {
            owner.request(source: .terminationSignal) {
                actionGenerations.append(generation)
            }
            XCTAssertTrue(
                scheduler.fire(at: generation - 1)
            )
            XCTAssertFalse(
                scheduler.fire(at: generation - 1)
            )
        }

        let expectedGenerations = Array(1...500)
        XCTAssertEqual(
            scheduledGenerations,
            expectedGenerations
        )
        XCTAssertEqual(
            appliedGenerations,
            expectedGenerations
        )
        XCTAssertEqual(
            actionGenerations,
            expectedGenerations
        )
        XCTAssertFalse(owner.isPending)
        XCTAssertTrue(
            (0..<500).allSatisfy {
                scheduler.token(at: $0).isCancelled
            }
        )
    }

    @MainActor
    private func makeTerminationFaultOwner(
        scheduler: ManualSpaceFixtureScheduler,
        evidencePublisher:
            @escaping @MainActor (
                SpaceFixtureTerminationFaultEvidence
            ) -> Void
    ) -> SpaceFixtureTerminationFaultOwner {
        SpaceFixtureTerminationFaultOwner(
            policy:
                SpaceFixtureTerminationFaultPolicy(
                    delayMilliseconds: 1_200
                )!,
            identity: terminationFaultIdentity,
            scheduler: scheduler,
            evidencePublisher: evidencePublisher
        )
    }

    private var terminationFaultIdentity:
        SpaceFixtureTerminationFaultIdentity
    {
        SpaceFixtureTerminationFaultIdentity(
            bundleIdentifier: "com.example.fixture",
            processIdentifier: 4_321
        )
    }

    private func makeTerminationFaultEvidence(
        generation: Int,
        phase: SpaceFixtureTerminationFaultEvidencePhase,
        source: SpaceFixtureTerminationFaultRequestSource
    ) -> SpaceFixtureTerminationFaultEvidence {
        SpaceFixtureTerminationFaultEvidence(
            requestGeneration: generation,
            phase: phase,
            source: source,
            delayMilliseconds: 1_200,
            identity: terminationFaultIdentity
        )
    }
}

@MainActor
private final class ImmediateSpaceFixtureTerminationScheduler:
    SpaceFixtureScheduling
{
    let token =
        ImmediateSpaceFixtureTerminationCancellable()

    func schedule(
        afterMilliseconds delayMilliseconds: Int,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any SpaceFixtureCancellable {
        action()
        return token
    }
}

@MainActor
private final class ImmediateSpaceFixtureTerminationCancellable:
    SpaceFixtureCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}
