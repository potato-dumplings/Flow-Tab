import Foundation
import XCTest

extension FlowTabUITests {
    func testSpaceFixtureWorkflowReadinessAggregateInitialReadbackRecoversPreForegroundEvidence() {
        let fixture = Self.readbackAggregateFixture()
        let owner =
            SpaceFixtureWorkflowReadinessAggregateObservationOwner(
                entries: [fixture.entry]
            )
        defer { owner.cancel() }

        let generation = owner.start()
        XCTAssertNil(owner.currentReadySnapshot)
        Self.recordReadbackAggregate(
            route: fixture.route,
            stages: [.configured, .ready]
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "unmet=[readback.configured]"
            )
        )
        owner.observeReadbackEvidence()

        Self.assertReadyReadback(
            owner.currentReadySnapshot,
            observationGeneration: generation
        )
    }

    func testSpaceFixtureWorkflowReadinessAggregateNotificationRefreshesMissedConfiguredReadback() {
        let fixture = Self.readbackAggregateFixture()
        let owner =
            SpaceFixtureWorkflowReadinessAggregateObservationOwner(
                entries: [fixture.entry]
            )
        defer { owner.cancel() }

        let generation = owner.start()
        XCTAssertNil(owner.currentReadySnapshot)
        owner.observeReadbackEvidence()
        Self.recordReadbackAggregate(
            route: fixture.route,
            stages: [.configured, .ready]
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "unmet=[readback.configured]"
            )
        )

        owner.observeNotificationEvent(
            Self.readbackAggregateEvidence(
                stage: .ready,
                transitionGeneration: 2
            ),
            for: fixture.entry,
            observationGeneration: generation
        )

        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "configuredApps=[readback]"
            )
        )
        Self.assertReadyReadback(
            owner.currentReadySnapshot,
            observationGeneration: generation
        )
    }

    func testSpaceFixtureWorkflowReadinessAggregateNotificationReadbackRejectsStaleGenerationUnderDuplicatePressure() {
        let fixture = Self.readbackAggregateFixture()
        let owner =
            SpaceFixtureWorkflowReadinessAggregateObservationOwner(
                entries: [fixture.entry]
            )
        defer { owner.cancel() }

        let staleGeneration = owner.start()
        let currentGeneration = owner.start()
        XCTAssertNil(owner.currentReadySnapshot)
        Self.recordReadbackAggregate(
            route: fixture.route,
            stages: [.configured, .ready]
        )
        let readyEvidence = Self.readbackAggregateEvidence(
            stage: .ready,
            transitionGeneration: 2
        )

        for _ in 0..<100 {
            owner.observeNotificationEvent(
                readyEvidence,
                for: fixture.entry,
                observationGeneration: staleGeneration
            )
        }
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "unmet=[readback.configured]"
            )
        )
        XCTAssertNil(owner.currentReadySnapshot)

        for _ in 0..<100 {
            owner.observeNotificationEvent(
                readyEvidence,
                for: fixture.entry,
                observationGeneration: currentGeneration
            )
        }
        Self.assertReadyReadback(
            owner.currentReadySnapshot,
            observationGeneration: currentGeneration
        )
    }

    private static func readbackAggregateFixture() -> (
        entry: SpaceFixtureWorkflowReadinessAggregateUITestEntry,
        route: SpaceFixtureWorkflowReadinessUITestRoute
    ) {
        let routeToken = UUID().uuidString
        let route =
            SpaceFixtureWorkflowReadinessUITestRoute(
                notificationName:
                    Notification.Name(
                        "io.github.potato-dumplings.flowtab."
                            + "ui-test.fixture-workflow-readiness."
                            + routeToken
                    ),
                readbackURL:
                    FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "flowtab-workflow-readiness-"
                                + routeToken
                                + ".plist"
                        )
            )
        return (
            SpaceFixtureWorkflowReadinessAggregateUITestEntry(
                expectation:
                    SpaceFixtureWorkflowReadinessAggregateExpectation(
                        workflowAppID: "readback",
                        bundleIdentifier: "fixture.readback",
                        windowPlanIndices: [1],
                        fullscreenWindowPlanIndices: [],
                        windowTitles: ["Readback"]
                    ),
                route: route
            ),
            route
        )
    }

    private static func recordReadbackAggregate(
        route: SpaceFixtureWorkflowReadinessUITestRoute,
        stages: [SpaceFixtureWorkflowReadinessStage]
    ) {
        for (index, stage) in stages.enumerated() {
            SpaceFixtureWorkflowReadinessTransport
                .recordReadbackEvidence(
                    readbackAggregateEvidence(
                        stage: stage,
                        transitionGeneration:
                            UInt64(index + 1)
                    ),
                    route: route.evidenceRoute
                )
        }
    }

    private static func assertReadyReadback(
        _ snapshot:
            SpaceFixtureWorkflowReadinessAggregateSnapshot?,
        observationGeneration: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            snapshot?.observationGeneration,
            observationGeneration,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot?
                .configuredEvidenceByWorkflowAppID[
                    "readback"
                ]?.stage,
            .configured,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot?
                .readyEvidenceByWorkflowAppID[
                    "readback"
                ]?.stage,
            .ready,
            file: file,
            line: line
        )
        XCTAssertTrue(
            snapshot?.isReady == true,
            file: file,
            line: line
        )
    }

    private static func readbackAggregateEvidence(
        stage: SpaceFixtureWorkflowReadinessStage,
        transitionGeneration: UInt64
    ) -> SpaceFixtureWorkflowReadinessEvidence {
        let isReady = stage == .ready
        return SpaceFixtureWorkflowReadinessEvidence(
            observationGeneration: 1,
            transitionGeneration: transitionGeneration,
            stage: stage,
            identity:
                SpaceFixtureWorkflowReadinessIdentity(
                    bundleIdentifier: "fixture.readback",
                    processIdentifier: 4_321
                ),
            snapshot:
                SpaceFixtureWorkflowReadinessSnapshot(
                    expectedWindowPlanIndices: [1],
                    observedWindowPlanIndices:
                        isReady ? [1] : [],
                    expectedFullscreenWindowPlanIndices:
                        [],
                    completedFullscreenWindowPlanIndices:
                        [],
                    desktopAnchorWindowPlanIndex: nil,
                    desktopPresentationResolved: true,
                    applicationAXSuppressionRequired:
                        false,
                    applicationAXExposureResolved: true,
                    windowTitles: ["Readback"]
                )
        )
    }
}
