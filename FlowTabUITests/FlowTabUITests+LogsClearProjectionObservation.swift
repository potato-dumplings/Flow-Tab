import Foundation
import XCTest

enum FlowTabUITestLogsClearProjectionObservationPolicy {
    static let projectionWatchdog: TimeInterval = 5
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

struct FlowTabUITestLogsClearProjectionExpectation: Equatable {
    let linesContainerExists: Bool
    let emptyHintExists: Bool
    let selectedLevel: String
    let identifierCounts: [String: Int]

    static func populated(
        selectedLevel: String,
        visibleIdentifiers: [String]
    ) -> Self {
        Self(
            linesContainerExists: true,
            emptyHintExists: false,
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
            linesContainerExists: false,
            emptyHintExists: true,
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
            && snapshot.linesContainerExists == linesContainerExists
            && snapshot.emptyHintExists == emptyHintExists
            && snapshot.selectedLevel == selectedLevel
            && snapshot.identifierCounts == identifierCounts
    }

    var diagnosticSummary: String {
        "linesContainerExists=\(linesContainerExists) "
            + "emptyHintExists=\(emptyHintExists) "
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
        let logsContent = element(
            in: app,
            identifier: Identifier.logsTabContent
        )
        let clearButton = app.buttons
            .matching(identifier: Identifier.logsClearButton)
            .firstMatch
        let linesContainer = element(
            in: app,
            identifier: Identifier.logsLines
        )
        let emptyHint = element(
            in: app,
            identifier: Identifier.logsEmptyHint
        )
        let logsLevel = element(
            in: app,
            identifier: Identifier.logsLevel
        )
        let seededRows = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    FlowTabUITestLogsProjectionPolicy
                        .seededRowIdentifierPrefix
                )
            )
        let readback: () ->
            FlowTabUITestLogsClearProjectionSnapshot = {
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
                let clearButtonExists = clearButton.exists
                let logsLevelExists = logsLevel.exists
                return FlowTabUITestLogsClearProjectionSnapshot(
                    applicationState: applicationState,
                    logsContentExists: logsContent.exists,
                    clearButtonExists: clearButtonExists,
                    clearButtonIsHittable: clearButtonExists
                        && clearButton.isHittable,
                    linesContainerExists: linesContainer.exists,
                    emptyHintExists: emptyHint.exists,
                    selectedLevel: logsLevelExists
                        ? self.elementStringValue(logsLevel)
                        : nil,
                    seededRowIdentifiers: seededRows
                        .allElementsBoundByIndex
                        .map(\.identifier)
                )
            }

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

        tapElement(clearButton)
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
}
