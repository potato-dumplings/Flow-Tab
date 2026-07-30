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

    @discardableResult
    func start() -> Int {
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
                self?.observeNotificationEvent(
                    SpaceFixtureWorkflowReadinessTransport
                        .evidence(from: notification),
                    for: entry,
                    observationGeneration:
                        aggregateGeneration
                )
            }
        }
        observeReadbackEvidence(
            observationGeneration: aggregateGeneration
        )
        return aggregateGeneration
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
        observeReadbackEvidence(
            observationGeneration: aggregateGeneration
        )
    }

    func observeNotificationEvent(
        _ evidence: SpaceFixtureWorkflowReadinessEvidence?,
        for entry:
            SpaceFixtureWorkflowReadinessAggregateUITestEntry,
        observationGeneration: Int
    ) {
        observeReadbackEvidence(
            for: entry,
            observationGeneration: observationGeneration
        )
        guard let evidence else { return }
        aggregateOwner.observe(
            evidence,
            for: entry.expectation.workflowAppID,
            observationGeneration: observationGeneration
        )
    }

    private func observeReadbackEvidence(
        observationGeneration: Int
    ) {
        for entry in entries {
            observeReadbackEvidence(
                for: entry,
                observationGeneration: observationGeneration
            )
        }
    }

    private func observeReadbackEvidence(
        for entry:
            SpaceFixtureWorkflowReadinessAggregateUITestEntry,
        observationGeneration: Int
    ) {
        for evidence in
            SpaceFixtureWorkflowReadinessTransport
                .readbackEvidence(
                    route: entry.route.evidenceRoute
                )
        {
            aggregateOwner.observe(
                evidence,
                for: entry.expectation.workflowAppID,
                observationGeneration:
                    observationGeneration
            )
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
    func spaceFixtureWorkflowReadinessAggregateExpectation(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> SpaceFixtureWorkflowReadinessAggregateExpectation {
        SpaceFixtureWorkflowReadinessAggregateExpectation(
            workflowAppID: workflowApp.appID,
            bundleIdentifier:
                workflowApp.identity.bundleIdentifier,
            windowPlanIndices:
                Array(1...workflowApp.windowCount),
            fullscreenWindowPlanIndices:
                workflowApp.fullscreenWindowIndices,
            windowTitles: workflowApp.expectedWindowTitles
        )
    }

    func makeSpaceFixtureWorkflowReadinessAggregateOwner(
        for workflow: SpaceFixtureResolvedWorkflow
    ) -> SpaceFixtureWorkflowReadinessAggregateObservationOwner {
        SpaceFixtureWorkflowReadinessAggregateObservationOwner(
            entries: workflow.apps.map {
                workflowApp in
                SpaceFixtureWorkflowReadinessAggregateUITestEntry(
                    expectation:
                        spaceFixtureWorkflowReadinessAggregateExpectation(
                            for: workflowApp
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
                workflowApp.fullscreenWindowIndices
            )
            XCTAssertEqual(
                readyEvidence.snapshot
                    .completedFullscreenWindowPlanIndices,
                workflowApp.fullscreenWindowIndices
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
