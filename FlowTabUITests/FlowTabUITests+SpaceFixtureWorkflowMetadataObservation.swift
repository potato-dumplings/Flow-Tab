import Foundation
import XCTest

enum SpaceFixtureWorkflowMetadataUITestPolicy {
    static let watchdog: TimeInterval = 8
}

private enum SpaceFixtureWorkflowMetadataAccessibilityIdentifier {
    static let ready = "flowtab.spacefixture.workflow.ready"
    static let summary = "flowtab.spacefixture.workflow.summary"

    static func fullscreenMarker(
        windowIndex: Int
    ) -> String {
        "flowtab.spacefixture.window.mode.\(windowIndex)"
    }
}

struct SpaceFixtureWorkflowMetadataElementSnapshot:
    Equatable
{
    let exists: Bool
    let value: String

    var diagnosticSummary: String {
        "exists=\(exists) value=\(value)"
    }
}

struct SpaceFixtureWorkflowMetadataSnapshot: Equatable {
    let summaryElements:
        [SpaceFixtureWorkflowMetadataElementSnapshot]
    let fullscreenMarker:
        SpaceFixtureWorkflowMetadataElementSnapshot?

    var diagnosticSummary: String {
        let summaries = summaryElements
            .map { "{\($0.diagnosticSummary)}" }
            .joined(separator: ",")
        return "summaries=[\(summaries)] "
            + "fullscreenMarker={"
            + (
                fullscreenMarker?.diagnosticSummary
                ?? "not-required"
            )
            + "}"
    }
}

final class SpaceFixtureWorkflowMetadataObservationOwner {
    private let expectedSummary: String
    private let expectedFullscreenMarker: String?
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureWorkflowMetadataSnapshot
        >

    init(
        expectedSummary: String,
        expectedFullscreenMarker: String?,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            SpaceFixtureWorkflowMetadataSnapshot
    ) {
        self.expectedSummary = expectedSummary
        self.expectedFullscreenMarker =
            expectedFullscreenMarker
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                snapshot.summaryElements.contains {
                    $0.exists
                        && $0.value == expectedSummary
                }
                    && (
                        expectedFullscreenMarker.map {
                            expectedMarker in
                            snapshot.fullscreenMarker?.exists
                                == true
                                && snapshot
                                    .fullscreenMarker?
                                    .value
                                    == expectedMarker
                        } ?? true
                    )
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        SpaceFixtureWorkflowMetadataSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        SpaceFixtureWorkflowMetadataSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "expectedSummary=\(expectedSummary) "
            + "expectedFullscreenMarker="
            + "\(expectedFullscreenMarker ?? "not-required") "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func validateResolvedSpaceFixtureWorkflowMetadata(
        after readinessSnapshot:
            SpaceFixtureWorkflowReadinessAggregateSnapshot,
        workflow: SpaceFixtureResolvedWorkflow,
        applications: [XCUIApplication],
        waitsForFullscreenMarkers: Bool,
        suppressesApplicationAccessibilityChildren: Bool
    ) {
        XCTAssertTrue(
            readinessSnapshot.isReady,
            "Visible fixture metadata requires terminal "
                + "aggregate readiness: "
                + readinessSnapshot.logFields
        )
        guard readinessSnapshot.isReady,
              !suppressesApplicationAccessibilityChildren
        else {
            return
        }
        XCTAssertEqual(applications.count, workflow.apps.count)
        guard applications.count == workflow.apps.count else {
            return
        }

        for (workflowApp, application) in zip(
            workflow.apps,
            applications
        ) {
            waitForSpaceFixtureWorkflowMetadata(
                in: application,
                expectedWindowTitles:
                    workflowApp.expectedWindowTitles,
                fullscreenWindowIndex:
                    waitsForFullscreenMarkers
                    ? workflowApp.fullscreenWindowIndex
                    : nil
            )
        }
    }

    func waitForSpaceFixtureWorkflowReadiness(
        in app: XCUIApplication,
        windowCount: Int,
        titlePrefix: String,
        fullscreenWindowIndex: Int?,
        readinessTimeout: TimeInterval
    ) {
        waitForSpaceFixtureWorkflowReadiness(
            in: app,
            expectedWindowTitles:
                expectedSpaceFixtureWorkflowWindowTitles(
                    titlePrefix: titlePrefix,
                    windowCount: windowCount
                ),
            fullscreenWindowIndex: fullscreenWindowIndex,
            readinessTimeout: readinessTimeout
        )
    }

    func waitForSpaceFixtureWorkflowReadiness(
        in app: XCUIApplication,
        expectedWindowTitles: [String],
        fullscreenWindowIndex: Int?,
        readinessTimeout: TimeInterval,
        readinessEvidence:
            SpaceFixtureWorkflowReadinessEvidence? = nil
    ) {
        let readyLabel = element(
            in: app,
            identifier:
                SpaceFixtureWorkflowMetadataAccessibilityIdentifier
                    .ready
        )
        let readyExpectation =
            XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format:
                        "exists == true AND label == %@",
                    "Ready"
                ),
                object: readyLabel
            )
        let waitResult = XCTWaiter.wait(
            for: [readyExpectation],
            timeout: readinessTimeout
        )
        XCTAssertEqual(
            waitResult,
            .completed,
            "Fixture visible-readiness watchdog expired; "
                + "lastLabel="
                + (
                    readyLabel.exists
                    ? readyLabel.label
                    : "<missing>"
                )
                + " evidence={"
                + (
                    readinessEvidence?.logFields
                    ?? "unavailable"
                )
                + "}"
        )

        waitForSpaceFixtureWorkflowMetadata(
            in: app,
            expectedWindowTitles: expectedWindowTitles,
            fullscreenWindowIndex: fullscreenWindowIndex
        )
    }

    func waitForSpaceFixtureWorkflowMetadata(
        in app: XCUIApplication,
        expectedWindowTitles: [String],
        fullscreenWindowIndex: Int?,
        timeout: TimeInterval =
            SpaceFixtureWorkflowMetadataUITestPolicy
                .watchdog
    ) {
        let expectedSummary =
            expectedSpaceFixtureWorkflowSummary(
                windowTitles: expectedWindowTitles
            )
        let summaryElements = app
            .descendants(matching: .any)
            .matching(
                identifier:
                    SpaceFixtureWorkflowMetadataAccessibilityIdentifier
                        .summary
            )
        let fullscreenMarker = fullscreenWindowIndex.map {
            element(
                in: app,
                identifier:
                    SpaceFixtureWorkflowMetadataAccessibilityIdentifier
                        .fullscreenMarker(windowIndex: $0)
            )
        }
        let owner = SpaceFixtureWorkflowMetadataObservationOwner(
            expectedSummary: expectedSummary,
            expectedFullscreenMarker:
                fullscreenWindowIndex.map {
                    _ in "Fullscreen Target"
                },
            readback: {
                SpaceFixtureWorkflowMetadataSnapshot(
                    summaryElements:
                        summaryElements
                            .allElementsBoundByIndex
                            .map {
                                self.metadataElementSnapshot(
                                    $0
                                )
                            },
                    fullscreenMarker:
                        fullscreenMarker.map {
                            self.metadataElementSnapshot($0)
                        }
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNotNil(
            owner.waitForResolution(timeout: timeout),
            "Fixture visible-metadata watchdog expired. "
                + owner.diagnosticSummary
        )
    }

    private func metadataElementSnapshot(
        _ element: XCUIElement
    ) -> SpaceFixtureWorkflowMetadataElementSnapshot {
        let exists = element.exists
        return SpaceFixtureWorkflowMetadataElementSnapshot(
            exists: exists,
            value: exists ? elementStringValue(element) : ""
        )
    }
}
