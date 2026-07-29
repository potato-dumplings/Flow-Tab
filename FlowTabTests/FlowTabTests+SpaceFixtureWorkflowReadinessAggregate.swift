import Darwin
import Foundation
import XCTest

extension FlowTabTests {
    func testSpaceFixtureWorkflowReadinessAggregateWaitsForEveryExactProcess() {
        let expectations =
            workflowReadinessAggregateExpectations()
        var completed:
            [SpaceFixtureWorkflowReadinessAggregateSnapshot] = []
        let owner =
            SpaceFixtureWorkflowReadinessAggregateOwner()
        let generation = owner.start(
            expectations: expectations,
            onReady: { completed.append($0) }
        )

        owner.observe(
            aggregateEvidence(
                expectation: expectations[1],
                processIdentifier: 2002,
                transitionGeneration: 4,
                stage: .ready
            ),
            for: expectations[1].workflowAppID,
            observationGeneration: generation
        )
        XCTAssertEqual(
            owner.lastSnapshot?.unmetConditions,
            [
                "browser.configured",
                "mail.configured"
            ]
        )

        owner.observe(
            aggregateEvidence(
                expectation: expectations[1],
                processIdentifier: 2002,
                transitionGeneration: 1,
                stage: .configured
            ),
            for: expectations[1].workflowAppID,
            observationGeneration: generation
        )
        XCTAssertEqual(
            owner.lastSnapshot?.unmetConditions,
            ["browser.configured"]
        )

        let expectedBrowser = expectations[0]
        let wrongExpectation =
            SpaceFixtureWorkflowReadinessAggregateExpectation(
                workflowAppID:
                    expectedBrowser.workflowAppID,
                bundleIdentifier: "wrong.bundle",
                windowPlanIndices:
                    expectedBrowser.windowPlanIndices,
                fullscreenWindowPlanIndices:
                    expectedBrowser
                        .fullscreenWindowPlanIndices,
                windowTitles:
                    expectedBrowser.windowTitles
            )
        owner.observe(
            aggregateEvidence(
                expectation: wrongExpectation,
                processIdentifier: 1001,
                transitionGeneration: 3,
                stage: .ready
            ),
            for: expectations[0].workflowAppID,
            observationGeneration: generation
        )
        owner.observe(
            aggregateEvidence(
                expectation: expectations[0],
                processIdentifier: 1001,
                transitionGeneration: 1,
                stage: .configured
            ),
            for: expectations[0].workflowAppID,
            observationGeneration: generation
        )
        XCTAssertEqual(
            owner.lastSnapshot?.unmetConditions,
            ["browser.ready"]
        )
        XCTAssertTrue(
            owner.lastSnapshot?.logFields.contains(
                "unmet=[browser.ready]"
            ) == true
        )

        owner.observe(
            aggregateEvidence(
                expectation: expectations[0],
                processIdentifier: 1001,
                transitionGeneration: 5,
                stage: .ready
            ),
            for: expectations[0].workflowAppID,
            observationGeneration: generation
        )

        XCTAssertEqual(completed.count, 1)
        XCTAssertTrue(completed[0].isReady)
        XCTAssertTrue(completed[0].unmetConditions.isEmpty)
        XCTAssertEqual(
            completed[0]
                .readyEvidenceByWorkflowAppID["mail"]?
                .transitionGeneration,
            4
        )
        XCTAssertFalse(owner.isObserving)
    }

    func testSpaceFixtureWorkflowReadinessAggregateRejectsCancelledAndStaleGenerations() {
        let expectations =
            workflowReadinessAggregateExpectations(
                appCount: 1
            )
        var completedGenerations: [Int] = []
        let owner =
            SpaceFixtureWorkflowReadinessAggregateOwner()
        let firstGeneration = owner.start(
            expectations: expectations,
            onReady: {
                completedGenerations.append(
                    $0.observationGeneration
                )
            }
        )
        owner.cancel()
        let secondGeneration = owner.start(
            expectations: expectations,
            onReady: {
                completedGenerations.append(
                    $0.observationGeneration
                )
            }
        )

        for stage in [
            SpaceFixtureWorkflowReadinessStage.configured,
            .ready
        ] {
            owner.observe(
                aggregateEvidence(
                    expectation: expectations[0],
                    processIdentifier: 1001,
                    transitionGeneration:
                        stage == .configured ? 1 : 2,
                    stage: stage
                ),
                for: expectations[0].workflowAppID,
                observationGeneration: firstGeneration
            )
        }
        XCTAssertTrue(completedGenerations.isEmpty)

        for stage in [
            SpaceFixtureWorkflowReadinessStage.configured,
            .ready
        ] {
            owner.observe(
                aggregateEvidence(
                    expectation: expectations[0],
                    processIdentifier: 1001,
                    transitionGeneration:
                        stage == .configured ? 1 : 2,
                    stage: stage
                ),
                for: expectations[0].workflowAppID,
                observationGeneration: secondGeneration
            )
        }
        XCTAssertEqual(
            completedGenerations,
            [secondGeneration]
        )
    }

    func testSpaceFixtureWorkflowReadinessAggregateSupportsSynchronousReplacement() {
        let expectations =
            workflowReadinessAggregateExpectations(
                appCount: 1
            )
        var owner:
            SpaceFixtureWorkflowReadinessAggregateOwner!
        var replacementGeneration: Int?
        owner = SpaceFixtureWorkflowReadinessAggregateOwner()
        let firstGeneration = owner.start(
            expectations: expectations
        ) { _ in
            replacementGeneration = owner.start(
                expectations: expectations,
                onReady: { _ in }
            )
        }

        completeAggregate(
            owner,
            expectations: expectations,
            aggregateGeneration: firstGeneration
        )

        XCTAssertNotNil(replacementGeneration)
        XCTAssertTrue(owner.isObserving)
        completeAggregate(
            owner,
            expectations: expectations,
            aggregateGeneration:
                replacementGeneration!
        )
        XCTAssertFalse(owner.isObserving)
    }

    func testSpaceFixtureWorkflowReadinessAggregateLifecyclePressure() {
        let expectations =
            workflowReadinessAggregateExpectations()
        let owner =
            SpaceFixtureWorkflowReadinessAggregateOwner()
        var completedGenerations: [Int] = []
        var generations: [Int] = []

        for _ in 0..<500 {
            generations.append(
                owner.start(
                    expectations: expectations
                ) {
                    completedGenerations.append(
                        $0.observationGeneration
                    )
                }
            )
        }
        for generation in generations.dropLast() {
            completeAggregate(
                owner,
                expectations: expectations,
                aggregateGeneration: generation
            )
        }
        let finalGeneration = generations.last!
        completeAggregate(
            owner,
            expectations: expectations,
            aggregateGeneration: finalGeneration
        )

        XCTAssertEqual(
            completedGenerations,
            [finalGeneration]
        )
        XCTAssertFalse(owner.isObserving)
    }

    private func completeAggregate(
        _ owner:
            SpaceFixtureWorkflowReadinessAggregateOwner,
        expectations:
            [SpaceFixtureWorkflowReadinessAggregateExpectation],
        aggregateGeneration: Int
    ) {
        for (index, expectation) in
            expectations.enumerated()
        {
            let processIdentifier =
                pid_t(1_001 + index)
            owner.observe(
                aggregateEvidence(
                    expectation: expectation,
                    processIdentifier: processIdentifier,
                    transitionGeneration: 1,
                    stage: .configured
                ),
                for: expectation.workflowAppID,
                observationGeneration: aggregateGeneration
            )
            owner.observe(
                aggregateEvidence(
                    expectation: expectation,
                    processIdentifier: processIdentifier,
                    transitionGeneration: 2,
                    stage: .ready
                ),
                for: expectation.workflowAppID,
                observationGeneration: aggregateGeneration
            )
        }
    }

    private func workflowReadinessAggregateExpectations(
        appCount: Int = 2
    ) -> [SpaceFixtureWorkflowReadinessAggregateExpectation] {
        let expectations = [
            SpaceFixtureWorkflowReadinessAggregateExpectation(
                workflowAppID: "browser",
                bundleIdentifier: "fixture.browser",
                windowPlanIndices: [1, 2],
                fullscreenWindowPlanIndices: [2],
                windowTitles: ["Browser 1", "Browser 2"]
            ),
            SpaceFixtureWorkflowReadinessAggregateExpectation(
                workflowAppID: "mail",
                bundleIdentifier: "fixture.mail",
                windowPlanIndices: [1],
                fullscreenWindowPlanIndices: [],
                windowTitles: ["Mail 1"]
            )
        ]
        return Array(expectations.prefix(appCount))
    }

    private func aggregateEvidence(
        expectation:
            SpaceFixtureWorkflowReadinessAggregateExpectation,
        processIdentifier: pid_t,
        transitionGeneration: UInt64,
        stage: SpaceFixtureWorkflowReadinessStage
    ) -> SpaceFixtureWorkflowReadinessEvidence {
        let isReady = stage == .ready
        let desktopAnchorWindowPlanIndex =
            expectation.fullscreenWindowPlanIndices.isEmpty
            ? nil
            : expectation.windowPlanIndices.first {
                !expectation.fullscreenWindowPlanIndices
                    .contains($0)
            }
        return SpaceFixtureWorkflowReadinessEvidence(
            observationGeneration: 1,
            transitionGeneration: transitionGeneration,
            stage: stage,
            identity:
                SpaceFixtureWorkflowReadinessIdentity(
                    bundleIdentifier:
                        expectation.bundleIdentifier,
                    processIdentifier: processIdentifier
                ),
            snapshot:
                SpaceFixtureWorkflowReadinessSnapshot(
                    expectedWindowPlanIndices:
                        expectation.windowPlanIndices,
                    observedWindowPlanIndices:
                        isReady
                        ? expectation.windowPlanIndices
                        : [],
                    expectedFullscreenWindowPlanIndices:
                        expectation
                            .fullscreenWindowPlanIndices,
                    completedFullscreenWindowPlanIndices:
                        isReady
                        ? expectation
                            .fullscreenWindowPlanIndices
                        : [],
                    desktopAnchorWindowPlanIndex:
                        desktopAnchorWindowPlanIndex,
                    desktopPresentationResolved:
                        isReady
                            || desktopAnchorWindowPlanIndex
                                == nil,
                    applicationAXSuppressionRequired:
                        false,
                    applicationAXExposureResolved: true,
                    windowTitles: expectation.windowTitles
                )
        )
    }
}
