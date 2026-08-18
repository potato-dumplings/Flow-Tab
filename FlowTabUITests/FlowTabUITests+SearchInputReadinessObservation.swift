import Foundation
import XCTest

enum FlowTabUITestSearchInputReadinessPolicy {
    static let applicationEvidenceLaunchArguments = [
        "--flowtab-ui-runtime-log-level",
        "INFO",
        "--flowtab-ui-enable-verbose-logs"
    ]
    static let watchdogFailureObservationTimeout:
        TimeInterval = 35
    static let accessibilityPublicationWatchdog:
        TimeInterval = 5
}

enum FlowTabUITestSearchInputReadinessEvidence {
    static let keyboardReadyMarker =
        "keyboardReadiness ready=1 "
        + "identifier=flowtab.switcher.search.input "
        + "responder=SearchSystemTextView "
        + "windowKey=1"
}

final class FlowTabUITestSearchInputReadinessObservationOwner {
    private let runtimeLogOwner:
        FlowTabUITestRuntimeLogObservationOwner
    private let baseline:
        FlowTabUITestRuntimeLogObservationBaseline?

    convenience init(
        baseline:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            baseline: baseline,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        baseline:
            FlowTabUITestRuntimeLogObservationBaseline? = nil,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        self.baseline = baseline
        runtimeLogOwner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation: .allMarkers([
                    FlowTabUITestSearchInputReadinessEvidence
                        .keyboardReadyMarker
                ]),
                observationRegistration:
                    observationRegistration,
                readback: readback
            )
    }

    func start() {
        runtimeLogOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestRuntimeLogSnapshot
    >? {
        runtimeLogOwner.waitForResolution(
            timeout: timeout
        )
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestRuntimeLogSnapshot
    >? {
        runtimeLogOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        runtimeLogOwner.diagnosticSummary
    }

    func cancel() {
        runtimeLogOwner.cancel()
        baseline?.cancel()
    }
}

extension FlowTabUITests {
    func prepareInitialFlowTabSearchInputReadiness()
        -> FlowTabUITestSearchInputReadinessObservationOwner
    {
        let owner =
            FlowTabUITestSearchInputReadinessObservationOwner(
                baseline: makeRuntimeLogFileSnapshot()
            )
        owner.start()
        addTeardownBlock {
            owner.cancel()
        }
        return owner
    }

    func requireInitialFlowTabSearchInput(
        in app: XCUIApplication,
        observedBy owner:
            FlowTabUITestSearchInputReadinessObservationOwner
    ) -> XCUIElement {
        defer { owner.cancel() }
        guard
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSearchInputReadinessPolicy
                        .watchdogFailureObservationTimeout
            ) != nil
        else {
            XCTFail(
                "Search input keyboard-readiness watchdog "
                    + "expired. \(owner.diagnosticSummary)"
            )
            return element(
                in: app,
                identifier:
                    Identifier.switcherSearchInput
            )
        }

        let searchInput = element(
            in: app,
            identifier: Identifier.switcherSearchInput
        )
        XCTAssertTrue(
            searchInput.waitForExistence(
                timeout:
                    FlowTabUITestSearchInputReadinessPolicy
                        .accessibilityPublicationWatchdog
            ),
            "The ready Search responder did not publish "
                + "its exact accessibility identity. "
                + owner.diagnosticSummary
        )
        return searchInput
    }
}
