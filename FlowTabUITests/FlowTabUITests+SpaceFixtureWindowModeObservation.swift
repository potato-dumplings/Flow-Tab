import Foundation
import XCTest

enum SpaceFixtureWindowModeUITestPolicy {
    static let publicationWatchdog: TimeInterval = 5
}

struct SpaceFixtureWindowModeSnapshot: Equatable {
    let identifier: String?
    let exists: Bool
    let label: String?

    var diagnosticSummary: String {
        "identifier=\(identifier ?? "nil") "
            + "exists=\(exists) "
            + "label=\(label ?? "nil")"
    }
}

final class SpaceFixtureWindowModeObservationOwner {
    private let expectedIdentifier: String
    private let expectedLabel: String
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureWindowModeSnapshot
        >

    init(
        expectedIdentifier: String,
        expectedLabel: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () -> SpaceFixtureWindowModeSnapshot
    ) {
        self.expectedIdentifier = expectedIdentifier
        self.expectedLabel = expectedLabel
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                snapshot.exists
                    && snapshot.identifier == expectedIdentifier
                    && snapshot.label == expectedLabel
            },
            describe: \.diagnosticSummary
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
        SpaceFixtureWindowModeSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        SpaceFixtureWindowModeSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        SpaceFixtureWindowModeSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "expectedIdentifier=\(expectedIdentifier) "
            + "expectedLabel=\(expectedLabel) "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func assertSpaceFixtureWindowModePublication(
        in app: XCUIApplication,
        windowIndex: Int,
        expectedLabel: String,
        trigger: () -> Void
    ) {
        let identifier =
            "flowtab.spacefixture.window.mode.\(windowIndex)"
        let marker = element(
            in: app,
            identifier: identifier
        )
        let owner = SpaceFixtureWindowModeObservationOwner(
            expectedIdentifier: identifier,
            expectedLabel: expectedLabel,
            readback: {
                let exists = marker.exists
                return SpaceFixtureWindowModeSnapshot(
                    identifier: exists ? marker.identifier : nil,
                    exists: exists,
                    label: exists ? marker.label : nil
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.latestEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            owner.latestEvidence?.value.exists,
            false,
            "Fixture marker baseline must be absent. "
                + owner.diagnosticSummary
        )
        XCTAssertNil(owner.resolvedEvidence)

        trigger()
        owner.requestReadback(source: .triggerReadback)

        XCTAssertNotNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureWindowModeUITestPolicy
                        .publicationWatchdog
            ),
            "Fixture window-mode publication watchdog expired. "
                + owner.diagnosticSummary
        )
    }
}
