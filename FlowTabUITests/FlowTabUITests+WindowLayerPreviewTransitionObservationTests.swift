import Foundation
import XCTest

private enum FlowTabUITestWindowLayerPreviewTransitionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testWindowLayerPreviewTransitionAcceptsInitialCompleteEvidence() {
        var order: [String] = []
        let owner =
            FlowTabUITestWindowLayerPreviewTransitionObservationOwner(
                expectedPreviewIdentifier:
                    windowLayerPreviewTestIdentifier,
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self
                        .windowLayerPreviewTransitionTestSnapshot(
                            mode: "windowCycle:forward",
                            preview:
                                "com.example.browser::Browser",
                            previewImages: "0",
                            previewExists: true
                        )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            order,
            ["register", "readback", "cancel"]
        )
    }

    func testWindowLayerPreviewTransitionGatesPretriggerEvidence() {
        var triggerCompleted = false
        var readbackCount = 0
        let owner =
            FlowTabUITestWindowLayerPreviewTransitionObservationOwner(
                expectedPreviewIdentifier:
                    windowLayerPreviewTestIdentifier,
                acceptsEvidence: {
                    triggerCompleted
                },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    readbackCount += 1
                    return self
                        .windowLayerPreviewTransitionTestSnapshot(
                            mode: "windowCycle:forward",
                            preview:
                                "com.example.browser::Browser",
                            previewImages: "1",
                            previewExists: true
                        )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(readbackCount, 1)

        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(readbackCount, 2)
    }

    func testWindowLayerPreviewTransitionWaitsForCompleteDelayedEvidence() {
        var snapshot =
            windowLayerPreviewTransitionTestSnapshot()
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestWindowLayerPreviewTransitionObservationOwner(
                expectedPreviewIdentifier:
                    windowLayerPreviewTestIdentifier,
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

        snapshot = windowLayerPreviewTransitionTestSnapshot(
            mode: "windowCycle:forward",
            preview: "com.example.browser::Browser",
            previewImages: "1"
        )
        for _ in 0..<20 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = windowLayerPreviewTransitionTestSnapshot(
            mode: "windowCycle:forward",
            preview: "com.example.browser::Browser",
            previewImages: "1",
            previewExists: true
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testWindowLayerPreviewTransitionRejectsStaleReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestWindowLayerPreviewTransitionTestPolicy
            .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot =
                windowLayerPreviewTransitionTestSnapshot()
            let owner =
                FlowTabUITestWindowLayerPreviewTransitionObservationOwner(
                    expectedPreviewIdentifier:
                        windowLayerPreviewTestIdentifier,
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
            snapshot =
                windowLayerPreviewTransitionTestSnapshot(
                    mode: "windowCycle:forward",
                    preview:
                        "com.example.browser::Browser",
                    previewImages: "1",
                    previewExists: true
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

    func testWindowLayerPreviewTransitionWatchdogReportsFinalEvidence() {
        let owner =
            FlowTabUITestWindowLayerPreviewTransitionObservationOwner(
                expectedPreviewIdentifier:
                    windowLayerPreviewTestIdentifier,
                observationRegistration: nil,
                readback: {
                    self
                        .windowLayerPreviewTransitionTestSnapshot(
                            mode: "windowCycle:forward",
                            preview:
                                "com.example.browser::Browser",
                            previewImages: "0"
                        )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWindowLayerPreviewTransitionTestPolicy
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
                "expectedPreviewIdentifier="
                    + windowLayerPreviewTestIdentifier
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "previewImageCount=0"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "previewExists=false"
            )
        )
    }

    private var windowLayerPreviewTestIdentifier: String {
        "flowtab.switcher.window-preview-image.mock-browser"
    }

    private func windowLayerPreviewTransitionTestSnapshot(
        mode: String = "appCycle",
        preview: String = "inactive",
        previewImages: String = "0",
        previewExists: Bool = false
    ) -> FlowTabUITestWindowLayerPreviewTransitionSnapshot {
        let rawValue =
            "mode=\(mode);preview=\(preview);"
            + "previewImages=\(previewImages)"
        return FlowTabUITestWindowLayerPreviewTransitionSnapshot(
            diagnostics:
                FlowTabUITestSwitcherDiagnosticsSnapshot(
                    identifier: "switcher-summary",
                    exists: true,
                    rawValue: rawValue,
                    values: [
                        "mode": mode,
                        "preview": preview,
                        "previewImages": previewImages,
                    ]
                ),
            previewIdentifier: windowLayerPreviewTestIdentifier,
            previewExists: previewExists
        )
    }
}
