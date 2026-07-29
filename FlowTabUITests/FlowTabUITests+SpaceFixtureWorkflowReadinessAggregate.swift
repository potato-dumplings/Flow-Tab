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
        readyExpectation = nil
    }

    deinit {
        for token in observationTokens {
            center.removeObserver(token)
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
