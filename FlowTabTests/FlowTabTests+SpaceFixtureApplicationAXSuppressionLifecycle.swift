import XCTest

extension FlowTabTests {
    func testProjectionAcknowledgementTransportParsesC1EvidenceExactly() {
        let notification = Notification(
            name:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .route
                    .projectionAcknowledgementNotificationName,
            userInfo: [
                "acknowledgementGeneration":
                    NSNumber(value: UInt64(7)),
                "bundleIdentifier": "com.example.fixture",
                "processIdentifier": NSNumber(value: 4_321),
                "windowCount": NSNumber(value: 2),
                "sourceGeneration":
                    "appLifecycle=1,cg=2,space=3"
            ]
        )

        XCTAssertEqual(
            SpaceFixtureProjectionAcknowledgementTransport
                .acknowledgement(from: notification),
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(
                    generation: 7,
                    sourceGeneration:
                        "appLifecycle=1,cg=2,space=3"
                )
        )
        XCTAssertNil(
            SpaceFixtureProjectionAcknowledgementTransport
                .acknowledgement(
                    from: Notification(
                        name: notification.name,
                        userInfo: [
                            "acknowledgementGeneration":
                                NSNumber(value: UInt64(8)),
                            "bundleIdentifier":
                                "com.example.fixture",
                            "processIdentifier":
                                NSNumber(value: 4_321),
                            "windowCount": NSNumber(value: 0),
                            "sourceGeneration":
                                "projection=8"
                        ]
                    )
                )
        )
    }

    @MainActor
    func testApplicationAXSuppressionWithoutRoutePreservesLocalReadbackCompatibility() {
        let scheduler = ManualSpaceFixtureScheduler()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 2,
                windowsAttributeCount: 2
            )
        var suppressCount = 0
        let owner =
            SpaceFixtureApplicationAXSuppressionOwner(
                scheduler: scheduler,
                exposureProvider: {
                    exposure.read()
                }
            )
        owner.start(
            route: nil,
            identity:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .identity,
            expectedProjectionWindowCount: 2,
            expectedPublishedAXWindowCount: 2,
            suppress: {
                suppressCount += 1
                exposure.set(windowCount: 0)
            }
        )

        owner.localTopologyStageDidResolve()

        XCTAssertEqual(suppressCount, 1)
        XCTAssertEqual(owner.suppressionGeneration, 1)
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(scheduler.token(at: 0).isCancelled)
        XCTAssertNil(owner.lastFailure)
    }

    @MainActor
    func testApplicationAXSuppressionWatchdogReportsMissingAcknowledgementAndLastReadback() {
        let scheduler = ManualSpaceFixtureScheduler()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 2,
                windowsAttributeCount: 2
            )
        var suppressCount = 0
        let owner =
            SpaceFixtureApplicationAXSuppressionOwner(
                scheduler: scheduler,
                exposureProvider: {
                    exposure.read()
                }
            )
        owner.start(
            route:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .route,
            identity:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .identity,
            expectedProjectionWindowCount: 2,
            expectedPublishedAXWindowCount: 2,
            suppress: {
                suppressCount += 1
            }
        )
        owner.localTopologyStageDidResolve()

        XCTAssertTrue(scheduler.fire(at: 0))

        let failure = owner.lastFailure
        XCTAssertEqual(suppressCount, 0)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(
            failure?.finalEvidence.unmetConditions,
            [
                "matchingProjectionAcknowledgement"
            ]
        )
        XCTAssertEqual(
            failure?.finalEvidence.source,
            .watchdogReadback
        )
        XCTAssertTrue(
            failure?.logFields.contains(
                "children=2 windows=2"
            ) == true
        )
    }

    @MainActor
    func testApplicationAXSuppressionLifecyclePressurePublishesEveryExactGeneration() {
        let scheduler = ManualSpaceFixtureScheduler()
        let observation =
            ManualSpaceFixtureProjectionAcknowledgementObservation()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 1,
                windowsAttributeCount: 1
            )
        var completionGenerations: [UInt64] = []
        let owner =
            SpaceFixtureApplicationAXSuppressionOwner(
                scheduler: scheduler,
                acknowledgementObservationInstaller: {
                    name,
                    handler in
                    observation.install(
                        notificationName: name,
                        handler: handler
                    )
                },
                exposureProvider: {
                    exposure.read()
                },
                completionPublisher: {
                    completion,
                    _ in
                    completionGenerations.append(
                        completion.suppressionGeneration
                    )
                }
            )

        for cycle in 1...500 {
            exposure.set(windowCount: 1)
            owner.start(
                route:
                    SpaceFixtureApplicationAXSuppressionTestSupport
                        .route,
                identity:
                    SpaceFixtureApplicationAXSuppressionTestSupport
                        .identity,
                expectedProjectionWindowCount: 1,
                expectedPublishedAXWindowCount: 1,
                suppress: {
                    exposure.set(windowCount: 0)
                }
            )
            observation.emit(
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .acknowledgement(
                        generation: UInt64(cycle),
                        windowCount: 1,
                        sourceGeneration:
                            "projection=\(cycle)"
                    ),
                at: cycle - 1
            )
            owner.localTopologyStageDidResolve()
        }

        XCTAssertEqual(
            completionGenerations,
            (1...500).map(UInt64.init)
        )
        XCTAssertEqual(
            observation.observations.filter {
                $0.token.isCancelled
            }.count,
            500
        )
        XCTAssertEqual(
            scheduler.scheduledDelays,
            Array(repeating: 15_000, count: 500)
        )
        XCTAssertNil(owner.lastFailure)
    }
}
