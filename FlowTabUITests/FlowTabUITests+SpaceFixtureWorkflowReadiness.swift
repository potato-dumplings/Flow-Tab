import AppKit
import Foundation
import XCTest

enum SpaceFixtureWorkflowReadinessUITestPolicy {
    static let defaultWatchdog: TimeInterval = 20

    static func watchdog(
        enterFullscreenDelayMilliseconds: Int
    ) -> TimeInterval {
        max(
            defaultWatchdog,
            Double(
                max(
                    0,
                    enterFullscreenDelayMilliseconds
                )
            ) / 1_000 + 15
        )
    }
}

struct SpaceFixtureWorkflowReadinessUITestRoute {
    let notificationName: Notification.Name

    var fixtureLaunchArguments: [String] {
        [
            SpaceFixtureWorkflowReadinessRoute
                .notificationArgument,
            notificationName.rawValue
        ]
    }
}

final class SpaceFixtureWorkflowReadinessObservationOwner {
    private let route:
        SpaceFixtureWorkflowReadinessUITestRoute
    private let center: DistributedNotificationCenter
    private let configuredExpectation =
        XCTestExpectation(
            description:
                "fixture workflow configured evidence"
        )
    private let readyExpectation =
        XCTestExpectation(
            description:
                "fixture workflow ready evidence"
        )
    private var observationToken: NSObjectProtocol?
    private var observedEvidence:
        [SpaceFixtureWorkflowReadinessEvidence] = []

    init(
        route:
            SpaceFixtureWorkflowReadinessUITestRoute,
        center: DistributedNotificationCenter = .default()
    ) {
        self.route = route
        self.center = center
        configuredExpectation.assertForOverFulfill = true
        readyExpectation.assertForOverFulfill = true
    }

    func start() {
        cancel()
        observedEvidence.removeAll()
        observationToken = center.addObserver(
            forName: route.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.observe(notification)
        }
    }

    func cancel() {
        guard let observationToken else { return }
        center.removeObserver(observationToken)
        self.observationToken = nil
    }

    func waitForConfigured(
        timeout: TimeInterval
    ) -> SpaceFixtureWorkflowReadinessEvidence? {
        wait(
            for: configuredExpectation,
            stage: .configured,
            observationGeneration: nil,
            timeout: timeout
        )
    }

    func waitForReady(
        observationGeneration: Int,
        timeout: TimeInterval
    ) -> SpaceFixtureWorkflowReadinessEvidence? {
        wait(
            for: readyExpectation,
            stage: .ready,
            observationGeneration:
                observationGeneration,
            timeout: timeout
        )
    }

    var diagnosticSummary: String {
        guard !observedEvidence.isEmpty else {
            return "unobserved"
        }
        return observedEvidence
            .map(\.logFields)
            .joined(separator: " | ")
    }

    deinit {
        if let observationToken {
            center.removeObserver(observationToken)
        }
    }

    private func observe(_ notification: Notification) {
        guard let evidence =
                SpaceFixtureWorkflowReadinessTransport
                    .evidence(from: notification)
        else {
            return
        }
        observedEvidence.append(evidence)
        switch evidence.stage {
        case .configured:
            configuredExpectation.fulfill()
        case .ready:
            readyExpectation.fulfill()
        case .windowTopology,
             .fullscreenTopology,
             .desktopPresentation,
             .applicationAXExposure:
            break
        }
    }

    private func wait(
        for expectation: XCTestExpectation,
        stage: SpaceFixtureWorkflowReadinessStage,
        observationGeneration: Int?,
        timeout: TimeInterval
    ) -> SpaceFixtureWorkflowReadinessEvidence? {
        if let evidence = matchingEvidence(
            stage: stage,
            observationGeneration:
                observationGeneration
        ) {
            return evidence
        }
        guard XCTWaiter.wait(
            for: [expectation],
            timeout: timeout
        ) == .completed
        else {
            return nil
        }
        return matchingEvidence(
            stage: stage,
            observationGeneration:
                observationGeneration
        )
    }

    private func matchingEvidence(
        stage: SpaceFixtureWorkflowReadinessStage,
        observationGeneration: Int?
    ) -> SpaceFixtureWorkflowReadinessEvidence? {
        observedEvidence.last {
            $0.stage == stage
                && (
                    observationGeneration == nil
                        || $0.observationGeneration
                            == observationGeneration
                )
        }
    }
}

extension FlowTabUITests {
    func makeSpaceFixtureWorkflowReadinessRoute()
        -> SpaceFixtureWorkflowReadinessUITestRoute
    {
        SpaceFixtureWorkflowReadinessUITestRoute(
            notificationName: Notification.Name(
                "io.github.potato-dumplings.flowtab."
                    + "ui-test.fixture-workflow-readiness."
                    + UUID().uuidString
            )
        )
    }

    func waitForSpaceFixtureWorkflowReadinessEvidence(
        observation:
            SpaceFixtureWorkflowReadinessObservationOwner,
        identity: SpaceFixtureAppIdentity,
        windowCount: Int,
        fullscreenWindowIndex: Int?,
        timeout: TimeInterval
    ) -> SpaceFixtureWorkflowReadinessEvidence? {
        guard let configuredEvidence =
                observation.waitForConfigured(
                    timeout: timeout
                )
        else {
            XCTFail(
                "Missing configured fixture readiness evidence: "
                    + observation.diagnosticSummary
            )
            return nil
        }
        guard let readyEvidence =
                observation.waitForReady(
                    observationGeneration:
                        configuredEvidence
                            .observationGeneration,
                    timeout: timeout
                )
        else {
            XCTFail(
                "Missing ready fixture evidence: "
                    + observation.diagnosticSummary
            )
            return nil
        }
        XCTAssertEqual(
            readyEvidence.identity,
            configuredEvidence.identity
        )
        XCTAssertEqual(
            readyEvidence.identity.bundleIdentifier,
            identity.bundleIdentifier
        )
        XCTAssertTrue(
            NSRunningApplication.runningApplications(
                withBundleIdentifier:
                    identity.bundleIdentifier
            ).contains {
                !$0.isTerminated
                    && $0.processIdentifier
                        == readyEvidence.identity
                            .processIdentifier
            }
        )
        XCTAssertEqual(
            readyEvidence.snapshot
                .expectedWindowPlanIndices,
            Array(1...windowCount)
        )
        XCTAssertEqual(
            readyEvidence.snapshot
                .expectedFullscreenWindowPlanIndices,
            fullscreenWindowIndex.map { [$0] } ?? []
        )
        XCTAssertTrue(readyEvidence.snapshot.isReady)
        return readyEvidence
    }
}
