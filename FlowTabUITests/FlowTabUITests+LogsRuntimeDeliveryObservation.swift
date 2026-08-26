import Foundation
import XCTest

enum FlowTabUITestLogsRuntimeDeliveryObservationPolicy {
    static let projectionWatchdog: TimeInterval = 5
}

enum FlowTabUITestLogsRuntimeDeliveryRequirement:
    String,
    Equatable
{
    case emptyBaseline
    case delivered
}

struct FlowTabUITestLogsRuntimeDeliverySnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let logsContentExists: Bool
    let clearButtonExists: Bool
    let clearButtonIsHittable: Bool
    let linesContainerExists: Bool
    let emptyHintExists: Bool
    let selectedLevel: String?
    let matchingRowContents: [String]

    var diagnosticSummary: String {
        let contentLengths = matchingRowContents.map(\.count)
        return "applicationState="
            + "\(String(describing: applicationState)) "
            + "logsContentExists=\(logsContentExists) "
            + "clearButtonExists=\(clearButtonExists) "
            + "clearButtonIsHittable=\(clearButtonIsHittable) "
            + "linesContainerExists=\(linesContainerExists) "
            + "emptyHintExists=\(emptyHintExists) "
            + "selectedLevel=\(selectedLevel ?? "nil") "
            + "matchingRowCount=\(matchingRowContents.count) "
            + "matchingRowContentLengths=\(contentLengths)"
    }
}

struct FlowTabUITestLogsRuntimeDeliveryExpectation: Equatable {
    let requirement: FlowTabUITestLogsRuntimeDeliveryRequirement
    let selectedLevel: String
    let marker: String

    static func emptyBaseline(
        selectedLevel: String,
        marker: String
    ) -> Self {
        Self(
            requirement: .emptyBaseline,
            selectedLevel: selectedLevel,
            marker: marker
        )
    }

    static func delivered(
        selectedLevel: String,
        marker: String
    ) -> Self {
        Self(
            requirement: .delivered,
            selectedLevel: selectedLevel,
            marker: marker
        )
    }

    func isSatisfied(
        by snapshot: FlowTabUITestLogsRuntimeDeliverySnapshot
    ) -> Bool {
        guard
            snapshot.applicationState == .runningForeground,
            snapshot.logsContentExists,
            snapshot.clearButtonExists,
            snapshot.clearButtonIsHittable,
            snapshot.selectedLevel == selectedLevel
        else {
            return false
        }

        switch requirement {
        case .emptyBaseline:
            return !snapshot.linesContainerExists
                && snapshot.emptyHintExists
                && snapshot.matchingRowContents.isEmpty
        case .delivered:
            return snapshot.linesContainerExists
                && !snapshot.emptyHintExists
                && snapshot.matchingRowContents.count == 1
                && snapshot.matchingRowContents[0].contains(marker)
        }
    }

    var diagnosticSummary: String {
        "requirement=\(requirement.rawValue) "
            + "selectedLevel=\(selectedLevel) "
            + "marker=\(marker)"
    }
}

final class FlowTabUITestLogsRuntimeDeliveryObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestLogsRuntimeDeliverySnapshot
        >

    init(
        expectation:
            FlowTabUITestLogsRuntimeDeliveryExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        acceptsResolution: @escaping () -> Bool = { true },
        readback: @escaping () ->
            FlowTabUITestLogsRuntimeDeliverySnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "acceptsResolution=\(acceptsResolution()) "
                    + "expected{\(expectation.diagnosticSummary)} "
                    + "observed{\(snapshot.diagnosticSummary)}"
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestLogsRuntimeDeliverySnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsRuntimeDeliverySnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsRuntimeDeliverySnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
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

private struct FlowTabUITestLogsRuntimeDeliveryElements {
    let logsContent: XCUIElement
    let clearButton: XCUIElement
    let linesContainer: XCUIElement
    let emptyHint: XCUIElement
    let logsLevel: XCUIElement
    let matchingRows: XCUIElementQuery
}

extension FlowTabUITests {
    func assertLogsRuntimeSnapshotAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String,
        selectedLevel: String,
        marker: String,
        trigger: () -> Bool
    ) {
        let targetExpectation =
            FlowTabUITestLogsRuntimeDeliveryExpectation
                .delivered(
                    selectedLevel: selectedLevel,
                    marker: marker
                )
        let elements = logsRuntimeDeliveryElements(
            in: app,
            marker: marker
        )
        let readback = logsRuntimeDeliveryReadback(
            in: app,
            elements: elements
        )
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestLogsRuntimeDeliveryObservationOwner(
                expectation: targetExpectation,
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: { triggerDidComplete },
                readback: readback
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard let initialEvidence = owner.latestEvidence,
              initialEvidence.source == .initialReadback
        else {
            XCTFail(
                "Runtime Logs current-snapshot initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return
        }
        XCTAssertTrue(initialEvidence.value.matchingRowContents.isEmpty)
        XCTAssertNil(owner.resolvedEvidence)

        let triggerSucceeded = trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
        guard triggerSucceeded else {
            XCTFail(
                "Runtime Logs current-snapshot navigation failed. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return
        }

        XCTAssertNotNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsRuntimeDeliveryObservationPolicy
                        .projectionWatchdog
            ),
            "Runtime Logs current-snapshot projection watchdog expired. "
                + "target=\(targetDescription) "
                + owner.diagnosticSummary
        )
    }

    func assertLogsRuntimeDelivery(
        in app: XCUIApplication,
        targetDescription: String,
        selectedLevel: String,
        marker: String,
        trigger: () -> Void
    ) {
        let baselineExpectation =
            FlowTabUITestLogsRuntimeDeliveryExpectation
                .emptyBaseline(
                    selectedLevel: selectedLevel,
                    marker: marker
                )
        let targetExpectation =
            FlowTabUITestLogsRuntimeDeliveryExpectation
                .delivered(
                    selectedLevel: selectedLevel,
                    marker: marker
                )
        let elements = logsRuntimeDeliveryElements(
            in: app,
            marker: marker
        )
        let readback = logsRuntimeDeliveryReadback(
            in: app,
            elements: elements
        )

        let baselineOwner =
            FlowTabUITestLogsRuntimeDeliveryObservationOwner(
                expectation: baselineExpectation,
                readback: readback
            )
        baselineOwner.start()
        guard baselineOwner.waitForResolution(
            timeout:
                FlowTabUITestLogsRuntimeDeliveryObservationPolicy
                    .projectionWatchdog
        ) != nil else {
            XCTFail(
                "Runtime Logs delivery baseline watchdog expired. "
                    + "target=\(targetDescription) "
                    + baselineOwner.diagnosticSummary
            )
            baselineOwner.cancel()
            return
        }
        baselineOwner.cancel()

        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestLogsRuntimeDeliveryObservationOwner(
                expectation: targetExpectation,
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: { triggerDidComplete },
                readback: readback
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard let initialEvidence = owner.latestEvidence,
              initialEvidence.source == .initialReadback,
              baselineExpectation.isSatisfied(
                by: initialEvidence.value
              )
        else {
            XCTFail(
                "Runtime Logs delivery initial baseline was incomplete. "
                    + "target=\(targetDescription) "
                    + "expected{\(baselineExpectation.diagnosticSummary)} "
                    + owner.diagnosticSummary
            )
            return
        }
        XCTAssertNil(owner.resolvedEvidence)

        trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        XCTAssertNotNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsRuntimeDeliveryObservationPolicy
                        .projectionWatchdog
            ),
            "Runtime Logs delivery projection watchdog expired. "
                + "target=\(targetDescription) "
                + owner.diagnosticSummary
        )
    }

    private func logsRuntimeDeliveryElements(
        in app: XCUIApplication,
        marker: String
    ) -> FlowTabUITestLogsRuntimeDeliveryElements {
        FlowTabUITestLogsRuntimeDeliveryElements(
            logsContent: element(
                in: app,
                identifier: Identifier.logsTabContent
            ),
            clearButton: app.buttons
                .matching(identifier: Identifier.logsClearButton)
                .firstMatch,
            linesContainer: element(
                in: app,
                identifier: Identifier.logsLines
            ),
            emptyHint: element(
                in: app,
                identifier: Identifier.logsEmptyHint
            ),
            logsLevel: element(
                in: app,
                identifier: Identifier.logsLevel
            ),
            matchingRows: app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    marker
                )
            )
        )
    }

    private func logsRuntimeDeliveryReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestLogsRuntimeDeliveryElements
    ) -> () -> FlowTabUITestLogsRuntimeDeliverySnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return FlowTabUITestLogsRuntimeDeliverySnapshot(
                    applicationState: applicationState,
                    logsContentExists: false,
                    clearButtonExists: false,
                    clearButtonIsHittable: false,
                    linesContainerExists: false,
                    emptyHintExists: false,
                    selectedLevel: nil,
                    matchingRowContents: []
                )
            }
            let clearButtonExists = elements.clearButton.exists
            let logsLevelExists = elements.logsLevel.exists
            return FlowTabUITestLogsRuntimeDeliverySnapshot(
                applicationState: applicationState,
                logsContentExists: elements.logsContent.exists,
                clearButtonExists: clearButtonExists,
                clearButtonIsHittable: clearButtonExists
                    && elements.clearButton.isHittable,
                linesContainerExists:
                    elements.linesContainer.exists,
                emptyHintExists: elements.emptyHint.exists,
                selectedLevel: logsLevelExists
                    ? self.elementStringValue(elements.logsLevel)
                    : nil,
                matchingRowContents: elements.matchingRows
                    .allElementsBoundByIndex
                    .map { row in
                        (row.value as? String) ?? row.label
                    }
            )
        }
    }
}
