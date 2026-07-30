import Darwin
import XCTest

extension FlowTabUITests {
    func testConfiguredNoisyWorkflowPreservesEveryFullscreenPlanIndex() throws {
        let installedWorkflow =
            try SpaceFixtureResolvedWorkflow.configured()
        let workflow = try resolveSpaceFixtureWorkflowScenario(
            sourceWorkflowURL:
                SpaceFixtureMultiAppWorkflowDefaults
                    .optionTabWindowStateNoisyRuntimeTruthWorkflowSourceURL,
            using: installedWorkflow
        )
        let workflowApp = try XCTUnwrap(
            workflow.apps.first
        )

        XCTAssertEqual(
            workflowApp.fullscreenWindowIndices,
            [2, 3]
        )
        XCTAssertEqual(workflowApp.fullscreenWindowIndex, 2)
        XCTAssertEqual(
            workflowApp.fullscreenWindowTitles,
            [
                "Chrome Fullscreen Tab",
                "Chrome Second Fullscreen Tab",
            ]
        )
        XCTAssertEqual(
            spaceFixtureWorkflowReadinessAggregateExpectation(
                for: workflowApp
            ).fullscreenWindowPlanIndices,
            [2, 3]
        )
    }

    func testResolvedWorkflowAppKeepsLegacySingleFullscreenIndexCompatible() {
        let workflowApp = Self.fullscreenPlanWorkflowApp(
            fullscreenWindowIndex: 3
        )

        XCTAssertEqual(
            workflowApp.fullscreenWindowIndices,
            [3]
        )
        XCTAssertEqual(workflowApp.fullscreenWindowIndex, 3)
        XCTAssertEqual(
            workflowApp.fullscreenWindowTitles,
            ["Window 3"]
        )
    }

    func testWorkflowReadinessAggregateAcceptsCompleteMultipleFullscreenPlan() {
        let workflowApp = Self.fullscreenPlanWorkflowApp(
            fullscreenWindowIndex: 2,
            fullscreenWindowIndices: [2, 3]
        )
        let expectation =
            spaceFixtureWorkflowReadinessAggregateExpectation(
                for: workflowApp
            )
        var completed:
            [SpaceFixtureWorkflowReadinessAggregateSnapshot] = []
        let owner =
            SpaceFixtureWorkflowReadinessAggregateOwner()
        let generation = owner.start(
            expectations: [expectation],
            onReady: { completed.append($0) }
        )

        for (stage, transitionGeneration) in [
            (SpaceFixtureWorkflowReadinessStage.configured, UInt64(1)),
            (.ready, UInt64(5)),
        ] {
            owner.observe(
                Self.fullscreenPlanEvidence(
                    workflowApp: workflowApp,
                    stage: stage,
                    transitionGeneration:
                        transitionGeneration
                ),
                for: workflowApp.appID,
                observationGeneration: generation
            )
        }

        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(
            completed.first?
                .readyEvidenceByWorkflowAppID[
                    workflowApp.appID
                ]?.snapshot
                .completedFullscreenWindowPlanIndices,
            [2, 3]
        )
    }

    private static func fullscreenPlanWorkflowApp(
        fullscreenWindowIndex: Int?,
        fullscreenWindowIndices: [Int]? = nil
    ) -> SpaceFixtureResolvedWorkflow.App {
        SpaceFixtureResolvedWorkflow.App(
            appID: "chrome",
            appName: "Chrome Fixture",
            identity:
                SpaceFixtureAppIdentity(
                    bundleIdentifier:
                        "com.example.fixture.chrome",
                    appURL: nil
                ),
            launchOrder: 1,
            windowCount: 4,
            expectedWindowTitles: [
                "Window 1",
                "Window 2",
                "Window 3",
                "Window 4",
            ],
            fullscreenWindowIndex: fullscreenWindowIndex,
            fullscreenWindowIndices:
                fullscreenWindowIndices
        )
    }

    private static func fullscreenPlanEvidence(
        workflowApp: SpaceFixtureResolvedWorkflow.App,
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
                    bundleIdentifier:
                        workflowApp.identity.bundleIdentifier,
                    processIdentifier: pid_t(4_567)
                ),
            snapshot:
                SpaceFixtureWorkflowReadinessSnapshot(
                    expectedWindowPlanIndices:
                        Array(1...workflowApp.windowCount),
                    observedWindowPlanIndices:
                        isReady
                        ? Array(1...workflowApp.windowCount)
                        : [],
                    expectedFullscreenWindowPlanIndices:
                        workflowApp.fullscreenWindowIndices,
                    completedFullscreenWindowPlanIndices:
                        isReady
                        ? workflowApp.fullscreenWindowIndices
                        : [],
                    desktopAnchorWindowPlanIndex: 1,
                    desktopPresentationResolved: true,
                    applicationAXSuppressionRequired: true,
                    applicationAXExposureResolved: isReady,
                    windowTitles:
                        workflowApp.expectedWindowTitles
                )
        )
    }
}
