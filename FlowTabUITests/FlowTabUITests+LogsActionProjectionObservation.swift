import Foundation
import XCTest

struct FlowTabUITestLogsActionProjectionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let logsContentExists: Bool
    let openDirectoryButtonExists: Bool
    let openDirectoryButtonIsHittable: Bool
    let clearButtonExists: Bool
    let clearButtonIsHittable: Bool

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "logsContentExists=\(logsContentExists) "
            + "openDirectoryButtonExists="
            + "\(openDirectoryButtonExists) "
            + "openDirectoryButtonIsHittable="
            + "\(openDirectoryButtonIsHittable) "
            + "clearButtonExists=\(clearButtonExists) "
            + "clearButtonIsHittable=\(clearButtonIsHittable)"
    }
}

struct FlowTabUITestLogsActionProjectionExpectation: Equatable {
    func isSatisfied(
        by snapshot: FlowTabUITestLogsActionProjectionSnapshot
    ) -> Bool {
        snapshot.applicationState == .runningForeground
            && snapshot.logsContentExists
            && snapshot.openDirectoryButtonExists
            && snapshot.openDirectoryButtonIsHittable
            && snapshot.clearButtonExists
            && snapshot.clearButtonIsHittable
    }
}

final class FlowTabUITestLogsActionProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestLogsActionProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestLogsActionProjectionExpectation = .init(),
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
            FlowTabUITestLogsActionProjectionSnapshot
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
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestLogsActionProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsActionProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsActionProjectionSnapshot
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

private struct FlowTabUITestLogsActionProjectionElements {
    let logsContent: XCUIElement
    let openDirectoryButton: XCUIElement
    let clearButton: XCUIElement
}

extension FlowTabUITests {
    @discardableResult
    func assertLogsActionProjectionAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String
    ) -> Bool {
        let elements = logsActionProjectionElements(in: app)
        let readback = logsActionProjectionReadback(
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
            FlowTabUITestLogsActionProjectionObservationOwner(
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
                "Logs actions initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        XCTAssertNil(owner.resolvedEvidence)

        let triggerSucceeded = tapFirstHittable(
            in: app.buttons.matching(
                identifier: Identifier.logsTabButton
            ),
            timeout:
                FlowTabUITestLogsProjectionPolicy
                    .tabNavigationWatchdog
        )
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        guard triggerSucceeded else {
            XCTFail(
                "Logs actions navigation trigger watchdog expired. "
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
                "Logs actions projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func logsActionProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestLogsActionProjectionElements {
        FlowTabUITestLogsActionProjectionElements(
            logsContent: element(
                in: app,
                identifier: Identifier.logsTabContent
            ),
            openDirectoryButton: app.buttons
                .matching(
                    identifier: Identifier.logsOpenDirectoryButton
                )
                .firstMatch,
            clearButton: app.buttons
                .matching(identifier: Identifier.logsClearButton)
                .firstMatch
        )
    }

    private func logsActionProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestLogsActionProjectionElements
    ) -> () -> FlowTabUITestLogsActionProjectionSnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return FlowTabUITestLogsActionProjectionSnapshot(
                    applicationState: applicationState,
                    logsContentExists: false,
                    openDirectoryButtonExists: false,
                    openDirectoryButtonIsHittable: false,
                    clearButtonExists: false,
                    clearButtonIsHittable: false
                )
            }
            let openDirectoryButtonExists =
                elements.openDirectoryButton.exists
            let clearButtonExists = elements.clearButton.exists
            return FlowTabUITestLogsActionProjectionSnapshot(
                applicationState: applicationState,
                logsContentExists: elements.logsContent.exists,
                openDirectoryButtonExists:
                    openDirectoryButtonExists,
                openDirectoryButtonIsHittable:
                    openDirectoryButtonExists
                    && elements.openDirectoryButton.isHittable,
                clearButtonExists: clearButtonExists,
                clearButtonIsHittable: clearButtonExists
                    && elements.clearButton.isHittable
            )
        }
    }
}
