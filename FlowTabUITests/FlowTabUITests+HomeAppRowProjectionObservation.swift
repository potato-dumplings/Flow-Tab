import Foundation
import XCTest

enum FlowTabUITestHomeInitialRowProjectionPolicy {
    static let watchdog: TimeInterval = 16
}

enum FlowTabUITestHomeAppliedRowProjectionPolicy {
    static let watchdog: TimeInterval = 4
    static let positionAccuracy: Double = 1
}

enum FlowTabUITestHomeRuntimeOrderProjectionPolicy {
    static let watchdog: TimeInterval = 36
}

struct FlowTabUITestHomeAppRowProjectionExpectation: Equatable {
    enum FrameOrder: String, Equatable {
        case expectationOrder
        case unconstrained
    }

    struct Row: Equatable {
        let identifier: String
        let value: String?
    }

    let rows: [Row]
    let frameOrder: FrameOrder
    let requiredApplicationState: XCUIApplication.State?

    init(
        rows: [Row],
        frameOrder: FrameOrder = .expectationOrder,
        requiredApplicationState: XCUIApplication.State? = nil
    ) {
        self.rows = rows
        self.frameOrder = frameOrder
        self.requiredApplicationState = requiredApplicationState
    }

    func isSatisfied(
        by snapshot: FlowTabUITestHomeAppRowProjectionSnapshot
    ) -> Bool {
        if let requiredApplicationState,
           snapshot.applicationState != requiredApplicationState
        {
            return false
        }
        guard snapshot.rows.count == rows.count else {
            return false
        }

        var previousFrameMinY: Double?
        for (expected, actual) in zip(rows, snapshot.rows) {
            guard actual.identifier == expected.identifier,
                  actual.exists,
                  let frameMinY = actual.frameMinY,
                  frameMinY.isFinite
            else {
                return false
            }
            if let expectedValue = expected.value,
               actual.value != expectedValue
            {
                return false
            }
            if frameOrder == .expectationOrder,
               let previousFrameMinY,
               previousFrameMinY >= frameMinY
            {
                return false
            }
            previousFrameMinY = frameMinY
        }
        return true
    }

    var diagnosticSummary: String {
        "frameOrder=\(frameOrder.rawValue) "
            + "requiredApplicationState="
            + "\(String(describing: requiredApplicationState)) "
            + rows.map {
                "identifier=\($0.identifier) "
                    + "expectedValue=\($0.value ?? "any")"
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

    let applicationState: XCUIApplication.State?
    let rows: [Row]

    init(
        applicationState: XCUIApplication.State? = nil,
        rows: [Row]
    ) {
        self.applicationState = applicationState
        self.rows = rows
    }

    func row(
        identifier: String
    ) -> Row? {
        rows.first { $0.identifier == identifier }
    }

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + rows.map {
                "identifier=\($0.identifier) "
                    + "exists=\($0.exists) "
                    + "value=\($0.value ?? "nil") "
                    + "frameMinY=\($0.frameMinY.map { String($0) } ?? "nil")"
            }
            .joined(separator: ";")
    }

    var identifiersByAscendingFrame: [String]? {
        let positionedRows = rows.compactMap { row -> (String, Double)? in
            guard row.exists,
                  let frameMinY = row.frameMinY,
                  frameMinY.isFinite
            else {
                return nil
            }
            return (row.identifier, frameMinY)
        }
        guard positionedRows.count == rows.count else { return nil }
        return positionedRows
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}

struct FlowTabUITestHomeAppRowPositionExpectation: Equatable {
    struct Row: Equatable {
        let identifier: String
        let frameMinY: Double
        let accuracy: Double
    }

    let rows: [Row]

    func isSatisfied(
        by snapshot: FlowTabUITestHomeAppRowProjectionSnapshot
    ) -> Bool {
        guard snapshot.rows.count == rows.count else {
            return false
        }

        for (expected, actual) in zip(rows, snapshot.rows) {
            guard expected.frameMinY.isFinite,
                  expected.accuracy.isFinite,
                  expected.accuracy >= 0,
                  actual.identifier == expected.identifier,
                  actual.exists,
                  let frameMinY = actual.frameMinY,
                  frameMinY.isFinite,
                  abs(frameMinY - expected.frameMinY)
                    <= expected.accuracy
            else {
                return false
            }
        }
        return true
    }

    var diagnosticSummary: String {
        rows.map {
            "identifier=\($0.identifier) "
                + "frameMinY=\($0.frameMinY) "
                + "accuracy=\($0.accuracy)"
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
    private let snapshotExpectationDescription: () -> String
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
        acceptsSnapshot: @escaping (
            FlowTabUITestHomeAppRowProjectionSnapshot
        ) -> Bool = { _ in
            true
        },
        snapshotExpectationDescription: @escaping () -> String = {
            "none"
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
        self.snapshotExpectationDescription =
            snapshotExpectationDescription
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsEvidence()
                    && expectation.isSatisfied(by: $0)
                    && acceptsSnapshot($0)
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
            + "snapshotExpected{"
            + "\(snapshotExpectationDescription())} "
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
        frameOrder:
            FlowTabUITestHomeAppRowProjectionExpectation.FrameOrder =
                .expectationOrder,
        requiredApplicationState: XCUIApplication.State? = nil,
        acceptsEvidence: @escaping () -> Bool = {
            true
        },
        acceptsSnapshot: @escaping (
            FlowTabUITestHomeAppRowProjectionSnapshot
        ) -> Bool = { _ in
            true
        },
        snapshotExpectationDescription: @escaping () -> String = {
            "none"
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
                    rows: rows,
                    frameOrder: frameOrder,
                    requiredApplicationState:
                        requiredApplicationState
                ),
            acceptsEvidence: acceptsEvidence,
            acceptsSnapshot: acceptsSnapshot,
            snapshotExpectationDescription:
                snapshotExpectationDescription,
            readback: {
                self.homeAppRowProjectionSnapshot(
                    for: elements,
                    applicationState:
                        requiredApplicationState == nil
                            ? nil
                            : app.state
                )
            }
        )
    }

    func homeAppRowProjectionSnapshot(
        for elements: [FlowTabUITestHomeAppRowProjectionElement],
        applicationState: XCUIApplication.State? = nil
    ) -> FlowTabUITestHomeAppRowProjectionSnapshot {
        FlowTabUITestHomeAppRowProjectionSnapshot(
            applicationState: applicationState,
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
