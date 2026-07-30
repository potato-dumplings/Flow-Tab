import AppKit
import Foundation
import XCTest

struct SpaceFixtureWorkflowReadinessAggregateUITestEntry {
    let expectation:
        SpaceFixtureWorkflowReadinessAggregateExpectation
    let route: SpaceFixtureWorkflowReadinessUITestRoute
}

final class SpaceFixtureWorkflowReadinessAggregateObservationOwner {
    private let entries:
        [SpaceFixtureWorkflowReadinessAggregateUITestEntry]
    private let center: DistributedNotificationCenter
    private let aggregateOwner =
        SpaceFixtureWorkflowReadinessAggregateOwner()
    private var observationTokens: [NSObjectProtocol] = []
    private var readyExpectation: XCTestExpectation?
    private var readySnapshot:
        SpaceFixtureWorkflowReadinessAggregateSnapshot?
    private var aggregateGeneration: Int?

    init(
        entries:
            [SpaceFixtureWorkflowReadinessAggregateUITestEntry],
        center: DistributedNotificationCenter = .default()
    ) {
        precondition(!entries.isEmpty)
        precondition(
            Set(entries.map(\.expectation.workflowAppID))
                .count == entries.count
        )
        self.entries = entries
        self.center = center
    }

    func start() {
        cancel()
        readySnapshot = nil
        let expectation = XCTestExpectation(
            description:
                "all fixture workflow processes ready"
        )
        expectation.assertForOverFulfill = true
        readyExpectation = expectation
        let aggregateGeneration = aggregateOwner.start(
            expectations: entries.map(\.expectation)
        ) { [weak self] snapshot in
            guard let self else { return }
            readySnapshot = snapshot
            readyExpectation?.fulfill()
        }
        self.aggregateGeneration = aggregateGeneration

        observationTokens = entries.map { entry in
            center.addObserver(
                forName: entry.route.notificationName,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let evidence =
                    SpaceFixtureWorkflowReadinessTransport
                        .evidence(from: notification)
                else {
                    return
                }
                self?.aggregateOwner.observe(
                    evidence,
                    for:
                        entry.expectation.workflowAppID,
                    observationGeneration:
                        aggregateGeneration
                )
            }
        }
    }

    func fixtureLaunchArguments(
        for workflowAppID: String
    ) -> [String] {
        guard let entry = entries.first(where: {
            $0.expectation.workflowAppID == workflowAppID
        }) else {
            preconditionFailure(
                "Missing workflow readiness route for "
                    + workflowAppID
            )
        }
        return entry.route.fixtureLaunchArguments
    }

    func waitForReady(
        timeout: TimeInterval
    ) -> SpaceFixtureWorkflowReadinessAggregateSnapshot? {
        observeReadbackEvidence()
        if let readySnapshot {
            return readySnapshot
        }
        guard let readyExpectation,
              XCTWaiter.wait(
                for: [readyExpectation],
                timeout: timeout
              ) == .completed
        else {
            return nil
        }
        return readySnapshot
    }

    func observeReadbackEvidence() {
        guard let aggregateGeneration else {
            return
        }
        for entry in entries {
            for evidence in
                SpaceFixtureWorkflowReadinessTransport
                    .readbackEvidence(
                        route: entry.route.evidenceRoute
                    )
            {
                aggregateOwner.observe(
                    evidence,
                    for:
                        entry.expectation.workflowAppID,
                    observationGeneration:
                        aggregateGeneration
                )
            }
        }
    }

    var diagnosticSummary: String {
        aggregateOwner.lastSnapshot?.logFields
            ?? "unobserved"
    }

    func cancel() {
        for token in observationTokens {
            center.removeObserver(token)
        }
        observationTokens.removeAll()
        aggregateOwner.cancel()
        aggregateGeneration = nil
        readyExpectation = nil
        removeReadbackEvidence()
    }

    deinit {
        for token in observationTokens {
            center.removeObserver(token)
        }
        removeReadbackEvidence()
    }

    private func removeReadbackEvidence() {
        for entry in entries {
            SpaceFixtureWorkflowReadinessTransport
                .removeReadbackEvidence(
                    route: entry.route.evidenceRoute
                )
        }
    }
}

extension FlowTabUITests {
    func makeSpaceFixtureWorkflowReadinessAggregateOwner(
        for workflow: SpaceFixtureResolvedWorkflow
    ) -> SpaceFixtureWorkflowReadinessAggregateObservationOwner {
        SpaceFixtureWorkflowReadinessAggregateObservationOwner(
            entries: workflow.apps.map {
                workflowApp in
                SpaceFixtureWorkflowReadinessAggregateUITestEntry(
                    expectation:
                        SpaceFixtureWorkflowReadinessAggregateExpectation(
                            workflowAppID: workflowApp.appID,
                            bundleIdentifier:
                                workflowApp.identity
                                    .bundleIdentifier,
                            windowPlanIndices:
                                Array(1...workflowApp.windowCount),
                            fullscreenWindowPlanIndices:
                                workflowApp.fullscreenWindowIndex
                                    .map { [$0] } ?? [],
                            windowTitles:
                                workflowApp.expectedWindowTitles
                        ),
                    route:
                        makeSpaceFixtureWorkflowReadinessRoute()
                )
            }
        )
    }

    func assertSpaceFixtureWorkflowReadinessAggregate(
        _ snapshot:
            SpaceFixtureWorkflowReadinessAggregateSnapshot,
        workflow: SpaceFixtureResolvedWorkflow,
        launchedApps: [XCUIApplication]
    ) {
        XCTAssertTrue(snapshot.isReady)
        XCTAssertEqual(
            snapshot.expectedWorkflowAppIDs,
            workflow.apps.map(\.appID)
        )
        XCTAssertEqual(launchedApps.count, workflow.apps.count)

        for (index, workflowApp) in workflow.apps.enumerated() {
            guard let configuredEvidence =
                    snapshot.configuredEvidenceByWorkflowAppID[
                        workflowApp.appID
                    ],
                  let readyEvidence =
                    snapshot.readyEvidenceByWorkflowAppID[
                        workflowApp.appID
                    ]
            else {
                XCTFail(
                    "Missing exact readiness evidence for "
                        + workflowApp.appID
                        + ": "
                        + snapshot.logFields
                )
                continue
            }
            XCTAssertEqual(
                readyEvidence.identity,
                configuredEvidence.identity
            )
            XCTAssertEqual(
                readyEvidence.identity.bundleIdentifier,
                workflowApp.identity.bundleIdentifier
            )
            XCTAssertEqual(
                readyEvidence.snapshot
                    .expectedWindowPlanIndices,
                Array(1...workflowApp.windowCount)
            )
            XCTAssertEqual(
                readyEvidence.snapshot
                    .observedWindowPlanIndices,
                Array(1...workflowApp.windowCount)
            )
            XCTAssertEqual(
                readyEvidence.snapshot
                    .expectedFullscreenWindowPlanIndices,
                workflowApp.fullscreenWindowIndex
                    .map { [$0] } ?? []
            )
            XCTAssertEqual(
                readyEvidence.snapshot
                    .completedFullscreenWindowPlanIndices,
                workflowApp.fullscreenWindowIndex
                    .map { [$0] } ?? []
            )
            XCTAssertEqual(
                readyEvidence.snapshot.windowTitles,
                workflowApp.expectedWindowTitles
            )
            XCTAssertTrue(readyEvidence.snapshot.isReady)
            XCTAssertNotEqual(
                launchedApps[index].state,
                .notRunning
            )
            XCTAssertTrue(
                NSRunningApplication.runningApplications(
                    withBundleIdentifier:
                        workflowApp.identity
                            .bundleIdentifier
                ).contains {
                    !$0.isTerminated
                        && $0.processIdentifier
                            == readyEvidence.identity
                                .processIdentifier
                }
            )
        }
    }
}

extension FlowTabUITests {
    func testSpaceFixtureWorkflowReadinessAggregateInitialReadbackRecoversPreForegroundEvidence() {
        let routeToken = UUID().uuidString
        let notificationName = Notification.Name(
            "io.github.potato-dumplings.flowtab."
                + "ui-test.fixture-workflow-readiness."
                + routeToken
        )
        let readbackURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "flowtab-workflow-readiness-"
                        + routeToken
                        + ".plist"
                )
        let route =
            SpaceFixtureWorkflowReadinessUITestRoute(
                notificationName: notificationName,
                readbackURL: readbackURL
            )
        let aggregateExpectation =
            SpaceFixtureWorkflowReadinessAggregateExpectation(
                workflowAppID: "readback",
                bundleIdentifier: "fixture.readback",
                windowPlanIndices: [1],
                fullscreenWindowPlanIndices: [],
                windowTitles: ["Readback"]
            )
        let owner =
            SpaceFixtureWorkflowReadinessAggregateObservationOwner(
                entries: [
                    SpaceFixtureWorkflowReadinessAggregateUITestEntry(
                        expectation: aggregateExpectation,
                        route: route
                    )
                ]
            )
        defer { owner.cancel() }

        owner.start()
        SpaceFixtureWorkflowReadinessTransport
            .recordReadbackEvidence(
                Self.readbackAggregateEvidence(
                    stage: .configured,
                    transitionGeneration: 1
                ),
                route: route.evidenceRoute
            )
        SpaceFixtureWorkflowReadinessTransport
            .recordReadbackEvidence(
                Self.readbackAggregateEvidence(
                    stage: .ready,
                    transitionGeneration: 2
                ),
                route: route.evidenceRoute
            )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "unmet=[readback.configured]"
            )
        )

        let snapshot = owner.waitForReady(timeout: 2)

        XCTAssertEqual(
            snapshot?
                .configuredEvidenceByWorkflowAppID[
                    "readback"
                ]?.stage,
            .configured
        )
        XCTAssertEqual(
            snapshot?
                .readyEvidenceByWorkflowAppID[
                    "readback"
                ]?.stage,
            .ready
        )
        XCTAssertTrue(snapshot?.isReady == true)
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
