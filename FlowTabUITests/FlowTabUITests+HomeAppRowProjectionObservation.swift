import Foundation
import XCTest

enum FlowTabUITestHomeInitialRowProjectionPolicy {
    static let watchdog: TimeInterval = 16
}

struct FlowTabUITestHomeAppRowProjectionExpectation: Equatable {
    struct Row: Equatable {
        let identifier: String
        let value: String
    }

    let rows: [Row]

    func isSatisfied(
        by snapshot: FlowTabUITestHomeAppRowProjectionSnapshot
    ) -> Bool {
        guard snapshot.rows.count == rows.count else {
            return false
        }

        var previousFrameMinY: Double?
        for (expected, actual) in zip(rows, snapshot.rows) {
            guard actual.identifier == expected.identifier,
                  actual.exists,
                  actual.value == expected.value,
                  let frameMinY = actual.frameMinY,
                  frameMinY.isFinite
            else {
                return false
            }
            if let previousFrameMinY,
               previousFrameMinY >= frameMinY
            {
                return false
            }
            previousFrameMinY = frameMinY
        }
        return true
    }

    var diagnosticSummary: String {
        rows.map {
            "identifier=\($0.identifier) value=\($0.value)"
        }
        .joined(separator: ";")
    }
}

struct FlowTabUITestHomeAppRowProjectionSnapshot: Equatable {
    struct Row: Equatable {
        let identifier: String
        let exists: Bool
        let value: String?
        let frameMinY: Double?
    }

    let rows: [Row]

    func row(
        identifier: String
    ) -> Row? {
        rows.first { $0.identifier == identifier }
    }

    var diagnosticSummary: String {
        rows.map {
            "identifier=\($0.identifier) "
                + "exists=\($0.exists) "
                + "value=\($0.value ?? "nil") "
                + "frameMinY=\($0.frameMinY.map { String($0) } ?? "nil")"
        }
        .joined(separator: ";")
    }
}

struct FlowTabUITestHomeAppRowProjectionElement {
    let identifier: String
    let element: XCUIElement
}

final class FlowTabUITestHomeAppRowProjectionObservationOwner {
    private let expectation:
        FlowTabUITestHomeAppRowProjectionExpectation
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestHomeAppRowProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestHomeAppRowProjectionExpectation,
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
            FlowTabUITestHomeAppRowProjectionSnapshot
    ) {
        self.expectation = expectation
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsEvidence()
                    && expectation.isSatisfied(by: $0)
            },
            describe: {
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + $0.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestHomeAppRowProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomeAppRowProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "expected{\(expectation.diagnosticSummary)} "
            + conditionOwner.diagnosticSummary
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func makeHomeAppRowProjectionObservation(
        in app: XCUIApplication,
        rows:
            [FlowTabUITestHomeAppRowProjectionExpectation.Row],
        acceptsEvidence: @escaping () -> Bool = {
            true
        }
    ) -> FlowTabUITestHomeAppRowProjectionObservationOwner {
        let elements = rows.map {
            FlowTabUITestHomeAppRowProjectionElement(
                identifier: $0.identifier,
                element: element(
                    in: app,
                    identifier: $0.identifier
                )
            )
        }
        return FlowTabUITestHomeAppRowProjectionObservationOwner(
            expectation:
                FlowTabUITestHomeAppRowProjectionExpectation(
                    rows: rows
                ),
            acceptsEvidence: acceptsEvidence,
            readback: {
                self.homeAppRowProjectionSnapshot(
                    for: elements
                )
            }
        )
    }

    func homeAppRowProjectionSnapshot(
        for elements: [FlowTabUITestHomeAppRowProjectionElement]
    ) -> FlowTabUITestHomeAppRowProjectionSnapshot {
        FlowTabUITestHomeAppRowProjectionSnapshot(
            rows: elements.map { item in
                let exists = item.element.exists
                return .init(
                    identifier: item.identifier,
                    exists: exists,
                    value: exists
                        ? elementStringValue(item.element)
                        : nil,
                    frameMinY: exists
                        ? Double(item.element.frame.minY)
                        : nil
                )
            }
        )
    }
}
