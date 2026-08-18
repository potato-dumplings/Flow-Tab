import Foundation
import XCTest

private enum
    SpaceFixtureWorkflowMetadataObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testWorkflowMetadataUsesTerminalReadinessForAXSuppressedRealFixture() throws {
        let workflow =
            try configuredSwitcherRuntimeTruthWorkflow(
                sourceWorkflowURL:
                    SpaceFixtureMultiAppWorkflowDefaults
                    .controlTabNoisyRuntimeTruthWorkflowSourceURL
            )

        try runRealSpaceFixtureWorkflow(
            workflow,
            waitsForFullscreenMarkers: false,
            suppressesAppAccessibilityChildren: true,
            validatesPermissionsBeforeFixtureLaunch: true,
            preservesDesktopAfterFullscreen: false,
            prelaunchesFlowTabBeforeFixture: true,
            flowTabLaunchTraceLabel:
                "workflow-metadata.ax-suppressed"
        ) { _, flowTabApp in
            XCTAssertTrue(
                flowTabApp.state == .runningForeground
                    || flowTabApp.state == .runningBackground
            )
        }
    }

    func testWorkflowMetadataObservationRegistersBeforeInitialReadback() {
        var order: [String] = []
        let owner =
            SpaceFixtureWorkflowMetadataObservationOwner(
                expectedSummary: "One | Two",
                expectedFullscreenMarker: nil,
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self.workflowMetadataTestSnapshot(
                        summary: "Launching"
                    )
                }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        owner.cancel()
        XCTAssertEqual(
            order,
            ["register", "readback", "cancel"]
        )
    }

    func testWorkflowMetadataObservationAcceptsInitialCompleteReadback() {
        let owner =
            SpaceFixtureWorkflowMetadataObservationOwner(
                expectedSummary: "One | Two",
                expectedFullscreenMarker:
                    "Fullscreen Target",
                observationRegistration: nil,
                readback: {
                    self.workflowMetadataTestSnapshot(
                        summary: "One | Two",
                        marker: "Fullscreen Target"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testWorkflowMetadataObservationWaitsForCompleteDelayedReadback() {
        var snapshot = workflowMetadataTestSnapshot(
            summary: "Launching",
            marker: "Standard Window"
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            SpaceFixtureWorkflowMetadataObservationOwner(
                expectedSummary: "One | Two",
                expectedFullscreenMarker:
                    "Fullscreen Target",
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    snapshot
                }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<20 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = workflowMetadataTestSnapshot(
            summary: "One | Two",
            marker: "Standard Window"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = workflowMetadataTestSnapshot(
            summary: "One | Two",
            marker: "Fullscreen Target"
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            snapshot
        )
    }

    func testWorkflowMetadataObservationRejectsStaleCallbacksUnderPressure() {
        for _ in
            0..<SpaceFixtureWorkflowMetadataObservationTestPolicy
                .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = workflowMetadataTestSnapshot(
                summary: "Launching"
            )
            let owner =
                SpaceFixtureWorkflowMetadataObservationOwner(
                    expectedSummary: "One | Two",
                    expectedFullscreenMarker: nil,
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        snapshot
                    }
                )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()
            snapshot = workflowMetadataTestSnapshot(
                summary: "One | Two"
            )

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testWorkflowMetadataObservationWatchdogReportsFinalReadback() {
        let owner =
            SpaceFixtureWorkflowMetadataObservationOwner(
                expectedSummary: "One | Two",
                expectedFullscreenMarker:
                    "Fullscreen Target",
                observationRegistration: nil,
                readback: {
                    self.workflowMetadataTestSnapshot(
                        summary: "Launching",
                        marker: "Standard Window"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureWorkflowMetadataObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedSummary=One | Two"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "value=Launching"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "value=Standard Window"
            )
        )
    }

    private func workflowMetadataTestSnapshot(
        summary: String,
        marker: String? = nil
    ) -> SpaceFixtureWorkflowMetadataSnapshot {
        SpaceFixtureWorkflowMetadataSnapshot(
            summaryElements: [
                SpaceFixtureWorkflowMetadataElementSnapshot(
                    exists: true,
                    value: summary
                ),
            ],
            fullscreenMarker: marker.map {
                SpaceFixtureWorkflowMetadataElementSnapshot(
                    exists: true,
                    value: $0
                )
            }
        )
    }
}
