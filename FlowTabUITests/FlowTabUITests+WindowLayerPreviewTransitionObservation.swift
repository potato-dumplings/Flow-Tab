import Foundation
import XCTest

private enum FlowTabUITestWindowLayerPreviewTransitionPolicy {
    static let watchdog: TimeInterval = 5
}

struct FlowTabUITestWindowLayerPreviewTransitionSnapshot: Equatable {
    let diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot
    let previewIdentifier: String
    let previewExists: Bool

    var modeValue: String? {
        diagnostics.values["mode"]
    }

    var previewValue: String? {
        diagnostics.values["preview"]
    }

    var previewImageCount: Int? {
        diagnostics.values["previewImages"].flatMap(Int.init)
    }

    var hasActivePreviewProjection: Bool {
        guard
            let previewValue,
            previewValue != "inactive",
            let separatorRange = previewValue.range(of: "::")
        else {
            return false
        }
        return !previewValue[separatorRange.upperBound...].isEmpty
    }

    var diagnosticSummary: String {
        "mode=\(modeValue ?? "nil") "
            + "preview=\(previewValue ?? "nil") "
            + "previewImageCount="
            + "\(previewImageCount.map { String($0) } ?? "nil") "
            + "activePreviewProjection="
            + "\(hasActivePreviewProjection) "
            + "previewIdentifier=\(previewIdentifier) "
            + "previewExists=\(previewExists) "
            + "diagnostics{\(diagnostics.diagnosticSummary)}"
    }
}

final class FlowTabUITestWindowLayerPreviewTransitionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestWindowLayerPreviewTransitionSnapshot
        >

    init(
        expectedPreviewIdentifier: String,
        acceptsEvidence: @escaping () -> Bool = {
            true
        },
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestWindowLayerPreviewTransitionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence()
                    && snapshot.diagnostics.exists
                    && snapshot.modeValue?.hasPrefix(
                        "windowCycle"
                    ) == true
                    && snapshot.hasActivePreviewProjection
                    && snapshot.previewIdentifier
                        == expectedPreviewIdentifier
                    && snapshot.previewExists
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + "expectedPreviewIdentifier="
                    + "\(expectedPreviewIdentifier) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestWindowLayerPreviewTransitionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestWindowLayerPreviewTransitionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func performAndWaitForWindowLayerPreviewTransition(
        diagnosticsSummary: XCUIElement,
        previewElement: XCUIElement,
        expectedPreviewIdentifier: String,
        trigger: () -> Void
    ) -> Bool {
        var triggerCompleted = false
        let owner =
            FlowTabUITestWindowLayerPreviewTransitionObservationOwner(
                expectedPreviewIdentifier:
                    expectedPreviewIdentifier,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    let previewExists =
                        previewElement.exists
                    return FlowTabUITestWindowLayerPreviewTransitionSnapshot(
                        diagnostics:
                            self.switcherDiagnosticsSnapshot(
                                diagnosticsSummary,
                                keys: [
                                    "mode",
                                    "preview",
                                    "previewImages",
                                ]
                            ),
                        previewIdentifier:
                            previewExists
                                ? previewElement.identifier
                                : "unavailable",
                        previewExists: previewExists
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard owner.waitForResolution(
            timeout:
                FlowTabUITestWindowLayerPreviewTransitionPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "Window-layer preview transition watchdog "
                    + "expired. \(owner.diagnosticSummary)"
            )
            return false
        }
        return true
    }
}
