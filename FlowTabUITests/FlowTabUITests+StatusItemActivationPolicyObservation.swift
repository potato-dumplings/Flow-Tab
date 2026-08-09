import Foundation
import XCTest

enum StatusItemActivationPolicyUITestPolicy {
    static let transitionWatchdog: TimeInterval = 8
    static let temporaryRegularMarker =
        "activationPolicy=regular "
        + "source=status_item_temporary_activation"
    static let stableAccessoryMarker =
        "activationPolicy=accessory "
        + "source=status_item_window_stable"

    static let orderedMarkers = [
        temporaryRegularMarker,
        stableAccessoryMarker
    ]
}

enum StatusItemActivationPolicyObservationRule {
    static func isSatisfied(
        by snapshot: FlowTabUITestRuntimeLogSnapshot
    ) -> Bool {
        firstUnmatchedMarker(in: snapshot.contents) == nil
    }

    static func diagnosticSummary(
        for snapshot: FlowTabUITestRuntimeLogSnapshot
    ) -> String {
        let firstUnmatched = firstUnmatchedMarker(
            in: snapshot.contents
        ) ?? "none"
        return "firstUnmatchedOrderedMarker=\(firstUnmatched) "
            + "expectedOrder="
            + "\(StatusItemActivationPolicyUITestPolicy.orderedMarkers) "
            + "observed{\(snapshot.diagnosticSummary)}"
    }

    static func firstUnmatchedMarker(
        in contents: String
    ) -> String? {
        var searchStart = contents.startIndex
        for marker in
            StatusItemActivationPolicyUITestPolicy.orderedMarkers
        {
            guard
                let range = contents.range(
                    of: marker,
                    range: searchStart..<contents.endIndex
                )
            else {
                return marker
            }
            searchStart = range.upperBound
        }
        return nil
    }
}

final class StatusItemActivationPolicyObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestRuntimeLogSnapshot
        >

    convenience init(
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied:
                StatusItemActivationPolicyObservationRule
                    .isSatisfied(by:),
            describe:
                StatusItemActivationPolicyObservationRule
                    .diagnosticSummary(for:)
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
        FlowTabUITestRuntimeLogSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestRuntimeLogSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestRuntimeLogSnapshot
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
    func assertStatusItemActivationPolicyTransition(
        since baseline:
            FlowTabUITestRuntimeLogObservationBaseline,
        trigger: () -> Void
    ) {
        let observation =
            StatusItemActivationPolicyObservationOwner(
                baseline: baseline
            )
        observation.start()
        defer { observation.cancel() }

        XCTAssertEqual(
            observation.latestEvidence?.source,
            .initialReadback
        )
        guard observation.resolvedEvidence == nil else {
            XCTFail(
                "Status-item activation-policy baseline already contained "
                    + "the complete transition. "
                    + observation.diagnosticSummary
            )
            return
        }

        trigger()
        observation.requestReadback(source: .triggerReadback)

        XCTAssertNotNil(
            observation.waitForResolution(
                timeout:
                    StatusItemActivationPolicyUITestPolicy
                        .transitionWatchdog
            ),
            "Status-item activation-policy transition watchdog expired. "
                + observation.diagnosticSummary
        )
    }
}
