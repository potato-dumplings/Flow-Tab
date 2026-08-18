import XCTest

extension FlowTabTests {
    @MainActor
    func testApplicationAXSuppressionObservesBeforeInitialReadbackAndLatchesSynchronousAcknowledgement() {
        let scheduler = ManualSpaceFixtureScheduler()
        let observation =
            ManualSpaceFixtureProjectionAcknowledgementObservation()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 2,
                windowsAttributeCount: 2
            )
        var events: [String] = []
        var completions:
            [SpaceFixtureApplicationAXSuppressionCompletion] = []
        var resolvedExposures:
            [SpaceFixtureApplicationAXExposure] = []
        observation.onInstall = { handler in
            events.append("observer")
            handler(
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .acknowledgement()
            )
        }
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
                    events.append("readback")
                    return exposure.read()
                },
                completionPublisher: {
                    completion,
                    _ in
                    events.append("completion")
                    completions.append(completion)
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
                events.append("suppress")
                exposure.set(windowCount: 0)
            },
            onResolved: {
                resolvedExposures.append($0)
            }
        )

        XCTAssertEqual(
            Array(events.prefix(2)),
            ["observer", "readback"]
        )
        XCTAssertTrue(completions.isEmpty)

        owner.localTopologyStageDidResolve()

        XCTAssertEqual(
            events,
            [
                "observer",
                "readback",
                "readback",
                "readback",
                "suppress",
                "readback",
                "completion"
            ]
        )
        XCTAssertEqual(
            completions.map(\.suppressionGeneration),
            [1]
        )
        XCTAssertEqual(
            resolvedExposures,
            [
                SpaceFixtureApplicationAXExposure(
                    childWindowCount: 0,
                    windowsAttributeCount: 0
                )
            ]
        )
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(
            observation.observations[0].token.isCancelled
        )
        XCTAssertTrue(scheduler.token(at: 0).isCancelled)
    }

    @MainActor
    func testApplicationAXSuppressionRejectsWrongAndOutOfOrderAcknowledgements() {
        let scheduler = ManualSpaceFixtureScheduler()
        let observation =
            ManualSpaceFixtureProjectionAcknowledgementObservation()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 2,
                windowsAttributeCount: 2
            )
        var suppressCount = 0
        let completionProbe =
            SpaceFixtureApplicationAXSuppressionCompletionProbe()
        let owner =
            SpaceFixtureApplicationAXSuppressionTestSupport
                .makeOwner(
            scheduler: scheduler,
            observation: observation,
            exposure: exposure,
            completionProbe: completionProbe
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
                exposure.set(windowCount: 0)
            }
        )

        observation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(
                    generation: 4,
                    bundleIdentifier: "com.example.other"
                )
        )
        observation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(generation: 3)
        )
        observation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(generation: 3)
        )
        observation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(generation: 2)
        )

        XCTAssertEqual(suppressCount, 0)
        owner.localTopologyStageDidResolve()

        XCTAssertEqual(suppressCount, 1)
        XCTAssertEqual(
            completionProbe.completions.first?
                .acknowledgement
                .acknowledgementGeneration,
            3
        )
        XCTAssertEqual(owner.suppressionGeneration, 1)
    }

    @MainActor
    func testApplicationAXSuppressionPollsOnlyUnmetReadbackAndSlowSchedulingDoesNotChangeResult() {
        let scheduler = ManualSpaceFixtureScheduler()
        let observation =
            ManualSpaceFixtureProjectionAcknowledgementObservation()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 1,
                windowsAttributeCount: 1
            )
        var suppressCount = 0
        let completionProbe =
            SpaceFixtureApplicationAXSuppressionCompletionProbe()
        let owner =
            SpaceFixtureApplicationAXSuppressionTestSupport
                .makeOwner(
            scheduler: scheduler,
            observation: observation,
            exposure: exposure,
            completionProbe: completionProbe
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
        observation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement()
        )
        owner.localTopologyStageDidResolve()

        XCTAssertEqual(
            scheduler.scheduledDelays,
            [15_000, 100]
        )
        XCTAssertTrue(completionProbe.completions.isEmpty)
        XCTAssertTrue(scheduler.fire(at: 1))
        XCTAssertEqual(
            scheduler.scheduledDelays,
            [15_000, 100, 100]
        )

        exposure.set(windowCount: 2)
        XCTAssertTrue(scheduler.fire(at: 2))
        XCTAssertEqual(suppressCount, 1)
        XCTAssertTrue(completionProbe.completions.isEmpty)
        XCTAssertEqual(
            scheduler.scheduledDelays,
            [15_000, 100, 100, 100]
        )

        exposure.set(windowCount: 0)
        XCTAssertTrue(scheduler.fire(at: 3))

        XCTAssertEqual(
            completionProbe.completions.map(
                \.suppressionGeneration
            ),
            [1]
        )
        XCTAssertNil(owner.lastFailure)
    }

    @MainActor
    func testApplicationAXSuppressionReplacementRejectsStaleObservationAndCancellationCleansUp() {
        let scheduler = ManualSpaceFixtureScheduler()
        let observation =
            ManualSpaceFixtureProjectionAcknowledgementObservation()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 2,
                windowsAttributeCount: 2
            )
        let completionProbe =
            SpaceFixtureApplicationAXSuppressionCompletionProbe()
        let owner =
            SpaceFixtureApplicationAXSuppressionTestSupport
                .makeOwner(
            scheduler: scheduler,
            observation: observation,
            exposure: exposure,
            completionProbe: completionProbe
                )
        let firstGeneration = owner.start(
            route:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .route,
            identity:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .identity,
            expectedProjectionWindowCount: 2,
            expectedPublishedAXWindowCount: 2,
            suppress: {
                exposure.set(windowCount: 0)
            }
        )
        let secondGeneration = owner.start(
            route:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .route,
            identity:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .identity,
            expectedProjectionWindowCount: 2,
            expectedPublishedAXWindowCount: 2,
            suppress: {
                exposure.set(windowCount: 0)
            }
        )
        XCTAssertGreaterThan(
            secondGeneration,
            firstGeneration
        )
        XCTAssertTrue(
            observation.observations[0].token.isCancelled
        )

        observation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(generation: 9),
            at: 0,
            includingCancelled: true
        )
        owner.localTopologyStageDidResolve()
        XCTAssertTrue(completionProbe.completions.isEmpty)

        observation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(generation: 10),
            at: 1
        )
        XCTAssertEqual(completionProbe.completions.count, 1)

        owner.cancel()
        observation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(generation: 11),
            at: 1,
            includingCancelled: true
        )
        XCTAssertTrue(
            scheduler.fire(
                at: 1,
                includingCancelled: true
            )
        )
        XCTAssertEqual(completionProbe.completions.count, 1)
    }

}
