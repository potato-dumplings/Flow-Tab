import Foundation
import XCTest

enum FlowTabUITestLogsClearProjectionObservationPolicy {
    static let projectionWatchdog: TimeInterval = 5
    static let relaunchProjectionWatchdog: TimeInterval = 8
}

struct FlowTabUITestLogsClearProjectionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let logsContentExists: Bool
    let clearButtonExists: Bool
    let clearButtonIsHittable: Bool
    let linesContainerExists: Bool
    let emptyHintExists: Bool
    let selectedLevel: String?
    let seededRowIdentifiers: [String]

    var identifierCounts: [String: Int] {
        seededRowIdentifiers.reduce(into: [:]) {
            counts,
            identifier in
            counts[identifier, default: 0] += 1
        }
    }

    var isNotRunningBaseline: Bool {
        applicationState == .notRunning
            && !logsContentExists
            && !clearButtonExists
            && !clearButtonIsHittable
            && !linesContainerExists
            && !emptyHintExists
            && selectedLevel == nil
            && seededRowIdentifiers.isEmpty
    }

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "logsContentExists=\(logsContentExists) "
            + "clearButtonExists=\(clearButtonExists) "
            + "clearButtonIsHittable=\(clearButtonIsHittable) "
            + "linesContainerExists=\(linesContainerExists) "
            + "emptyHintExists=\(emptyHintExists) "
            + "selectedLevel=\(selectedLevel ?? "nil") "
            + "identifierCounts="
            + logsClearIdentifierCountSummary(identifierCounts)
    }
}

enum FlowTabUITestLogsContentProjectionRequirement:
    String,
    Equatable
{
    case populated
    case empty
    case loaded

    func isSatisfied(
        linesContainerExists: Bool,
        emptyHintExists: Bool
    ) -> Bool {
        switch self {
        case .populated:
            return linesContainerExists && !emptyHintExists
        case .empty:
            return !linesContainerExists && emptyHintExists
        case .loaded:
            return linesContainerExists != emptyHintExists
        }
    }
}

struct FlowTabUITestLogsClearProjectionExpectation: Equatable {
    let contentRequirement:
        FlowTabUITestLogsContentProjectionRequirement
    let selectedLevel: String
    let identifierCounts: [String: Int]

    static func populated(
        selectedLevel: String,
        visibleIdentifiers: [String]
    ) -> Self {
        Self(
            contentRequirement: .populated,
            selectedLevel: selectedLevel,
            identifierCounts: visibleIdentifiers.reduce(into: [:]) {
                counts,
                identifier in
                counts[identifier, default: 0] += 1
            }
        )
    }

    static func cleared(selectedLevel: String) -> Self {
        Self(
            contentRequirement: .empty,
            selectedLevel: selectedLevel,
            identifierCounts: [:]
        )
    }

    static func reloadedWithoutSeededRows(
        selectedLevel: String
    ) -> Self {
        Self(
            contentRequirement: .loaded,
            selectedLevel: selectedLevel,
            identifierCounts: [:]
        )
    }

    func isSatisfied(
        by snapshot: FlowTabUITestLogsClearProjectionSnapshot
    ) -> Bool {
        snapshot.applicationState == .runningForeground
            && snapshot.logsContentExists
            && snapshot.clearButtonExists
            && snapshot.clearButtonIsHittable
            && contentRequirement.isSatisfied(
                linesContainerExists:
                    snapshot.linesContainerExists,
                emptyHintExists: snapshot.emptyHintExists
            )
            && snapshot.selectedLevel == selectedLevel
            && snapshot.identifierCounts == identifierCounts
    }

    var diagnosticSummary: String {
        "contentRequirement=\(contentRequirement.rawValue) "
            + "selectedLevel=\(selectedLevel) "
            + "identifierCounts="
            + logsClearIdentifierCountSummary(identifierCounts)
    }
}

private func logsClearIdentifierCountSummary(
    _ counts: [String: Int]
) -> String {
    counts.keys.sorted().map { identifier in
        "\(identifier)=\(counts[identifier, default: 0])"
    }
    .joined(separator: ",")
}

private struct FlowTabUITestLogsClearProjectionElements {
    let logsContent: XCUIElement
    let clearButton: XCUIElement
    let linesContainer: XCUIElement
    let emptyHint: XCUIElement
    let logsLevel: XCUIElement
    let seededRows: XCUIElementQuery
}

final class FlowTabUITestLogsClearProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestLogsClearProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestLogsClearProjectionExpectation,
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
            FlowTabUITestLogsClearProjectionSnapshot
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
        FlowTabUITestLogsClearProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsClearProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsClearProjectionSnapshot
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

extension FlowTabUITests {
    @discardableResult
    func assertLogsPopulatedProjectionAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String,
        selectedLevel: String,
        visibleIdentifiers: [String],
        trigger: () -> Bool
    ) -> Bool {
        let expectation =
            FlowTabUITestLogsClearProjectionExpectation.populated(
                selectedLevel: selectedLevel,
                visibleIdentifiers: visibleIdentifiers
            )
        let elements = logsClearProjectionElements(in: app)
        let readback = logsClearProjectionReadback(
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
            FlowTabUITestLogsClearProjectionObservationOwner(
                expectation: expectation,
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

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Logs navigation initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        XCTAssertNil(owner.resolvedEvidence)

        let triggerSucceeded = trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        guard triggerSucceeded else {
            XCTFail(
                "Logs navigation trigger watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        guard owner.waitForResolution(
            timeout:
                FlowTabUITestLogsProjectionPolicy
                    .exactProjectionWatchdog
        ) != nil else {
            XCTFail(
                "Logs populated projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    func assertLogsClearTransition(
        in app: XCUIApplication,
        targetDescription: String,
        selectedLevel: String,
        initialVisibleIdentifiers: [String]
    ) {
        let initialExpectation =
            FlowTabUITestLogsClearProjectionExpectation.populated(
                selectedLevel: selectedLevel,
                visibleIdentifiers: initialVisibleIdentifiers
            )
        let targetExpectation =
            FlowTabUITestLogsClearProjectionExpectation.cleared(
                selectedLevel: selectedLevel
            )
        let elements = logsClearProjectionElements(in: app)
        let readback = logsClearProjectionReadback(
            in: app,
            elements: elements
        )

        let baselineOwner =
            FlowTabUITestLogsClearProjectionObservationOwner(
                expectation: initialExpectation,
                readback: readback
            )
        baselineOwner.start()
        guard baselineOwner.waitForResolution(
            timeout:
                FlowTabUITestLogsClearProjectionObservationPolicy
                    .projectionWatchdog
        ) != nil else {
            XCTFail(
                "Logs clear baseline watchdog expired. "
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
            FlowTabUITestLogsClearProjectionObservationOwner(
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
              initialExpectation.isSatisfied(
                by: initialEvidence.value
              )
        else {
            XCTFail(
                "Logs clear initial baseline was incomplete. "
                    + "target=\(targetDescription) "
                    + "expected{\(initialExpectation.diagnosticSummary)} "
                    + owner.diagnosticSummary
            )
            return
        }
        XCTAssertNil(owner.resolvedEvidence)

        tapElement(elements.clearButton)
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        XCTAssertNotNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsClearProjectionObservationPolicy
                        .projectionWatchdog
            ),
            "Logs clear projection watchdog expired. "
                + "target=\(targetDescription) "
                + owner.diagnosticSummary
        )
    }

    func assertLogsClearPersistenceAfterRelaunch(
        in app: XCUIApplication,
        targetDescription: String,
        selectedLevel: String,
        trigger: () -> Void
    ) {
        let targetExpectation =
            FlowTabUITestLogsClearProjectionExpectation
                .reloadedWithoutSeededRows(
                    selectedLevel: selectedLevel
                )
        let elements = logsClearProjectionElements(in: app)
        let readback = logsClearProjectionReadback(
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
            FlowTabUITestLogsClearProjectionObservationOwner(
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
              initialEvidence.value.isNotRunningBaseline
        else {
            XCTFail(
                "Logs clear relaunch baseline was incomplete. "
                    + "target=\(targetDescription) "
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
                    FlowTabUITestLogsClearProjectionObservationPolicy
                        .relaunchProjectionWatchdog
            ),
            "Logs clear relaunch projection watchdog expired. "
                + "target=\(targetDescription) "
                + owner.diagnosticSummary
        )
    }

    private func logsClearProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestLogsClearProjectionElements {
        FlowTabUITestLogsClearProjectionElements(
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
            seededRows: app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        FlowTabUITestLogsProjectionPolicy
                            .seededRowIdentifierPrefix
                    )
                )
        )
    }

    private func logsClearProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestLogsClearProjectionElements
    ) -> () -> FlowTabUITestLogsClearProjectionSnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return FlowTabUITestLogsClearProjectionSnapshot(
                    applicationState: applicationState,
                    logsContentExists: false,
                    clearButtonExists: false,
                    clearButtonIsHittable: false,
                    linesContainerExists: false,
                    emptyHintExists: false,
                    selectedLevel: nil,
                    seededRowIdentifiers: []
                )
            }
            let clearButtonExists = elements.clearButton.exists
            let logsLevelExists = elements.logsLevel.exists
            return FlowTabUITestLogsClearProjectionSnapshot(
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
                seededRowIdentifiers: elements.seededRows
                    .allElementsBoundByIndex
                    .map(\.identifier)
            )
        }
    }
}
