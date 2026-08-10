import Foundation
import XCTest

enum FlowTabUITestLogsDiagnosticSessionObservationPolicy {
    static let projectionWatchdog: TimeInterval = 5
}

struct FlowTabUITestLogsDiagnosticSessionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let logsContentExists: Bool
    let toggleExists: Bool
    let toggleIsOn: Bool?
    let statusExists: Bool
    let statusLabel: String

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "logsContentExists=\(logsContentExists) "
            + "toggleExists=\(toggleExists) "
            + "toggleIsOn=\(toggleIsOn.map { String($0) } ?? "nil") "
            + "statusExists=\(statusExists) "
            + "statusLabel=\(statusLabel)"
    }
}

struct FlowTabUITestLogsDiagnosticSessionExpectation: Equatable {
    let isActive: Bool

    func isSatisfied(
        by snapshot: FlowTabUITestLogsDiagnosticSessionSnapshot
    ) -> Bool {
        snapshot.applicationState == .runningForeground
            && snapshot.logsContentExists
            && snapshot.toggleExists
            && snapshot.toggleIsOn == isActive
            && snapshot.statusExists == isActive
            && (!isActive
                || !snapshot.statusLabel
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty)
    }

    var diagnosticSummary: String {
        "isActive=\(isActive)"
    }
}

final class FlowTabUITestLogsDiagnosticSessionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestLogsDiagnosticSessionSnapshot
        >

    init(
        expectation:
            FlowTabUITestLogsDiagnosticSessionExpectation,
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
            FlowTabUITestLogsDiagnosticSessionSnapshot
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
        FlowTabUITestLogsDiagnosticSessionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsDiagnosticSessionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsDiagnosticSessionSnapshot
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
    func assertLogsDiagnosticSessionTransition(
        in app: XCUIApplication,
        toggle: XCUIElement,
        targetDescription: String,
        from initialIsActive: Bool,
        to isActive: Bool,
        trigger: () -> Void
    ) {
        let initialExpectation =
            FlowTabUITestLogsDiagnosticSessionExpectation(
                isActive: initialIsActive
            )
        let targetExpectation =
            FlowTabUITestLogsDiagnosticSessionExpectation(
                isActive: isActive
            )
        let logsContent = element(
            in: app,
            identifier: Identifier.logsTabContent
        )
        let status = element(
            in: app,
            identifier: Identifier.logsDiagnosticSessionStatus
        )
        let readback: () ->
            FlowTabUITestLogsDiagnosticSessionSnapshot = {
                let applicationState = app.state
                guard applicationState == .runningForeground else {
                    return FlowTabUITestLogsDiagnosticSessionSnapshot(
                        applicationState: applicationState,
                        logsContentExists: false,
                        toggleExists: false,
                        toggleIsOn: nil,
                        statusExists: false,
                        statusLabel: ""
                    )
                }
                let toggleExists = toggle.exists
                let statusExists = status.exists
                return FlowTabUITestLogsDiagnosticSessionSnapshot(
                    applicationState: applicationState,
                    logsContentExists: logsContent.exists,
                    toggleExists: toggleExists,
                    toggleIsOn: toggleExists
                        ? self.toggleIsOn(toggle)
                        : nil,
                    statusExists: statusExists,
                    statusLabel: statusExists
                        ? self.elementStringValue(status)
                        : ""
                )
            }

        let baselineOwner =
            FlowTabUITestLogsDiagnosticSessionObservationOwner(
                expectation: initialExpectation,
                readback: readback
            )
        baselineOwner.start()
        guard baselineOwner.waitForResolution(
            timeout:
                FlowTabUITestLogsDiagnosticSessionObservationPolicy
                    .projectionWatchdog
        ) != nil else {
            XCTFail(
                "Diagnostic-session baseline watchdog expired. "
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
            FlowTabUITestLogsDiagnosticSessionObservationOwner(
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
                "Diagnostic-session initial baseline was incomplete. "
                    + "target=\(targetDescription) "
                    + "expected{\(initialExpectation.diagnosticSummary)} "
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
                    FlowTabUITestLogsDiagnosticSessionObservationPolicy
                        .projectionWatchdog
            ),
            "Diagnostic-session transition watchdog expired. "
                + "target=\(targetDescription) "
                + owner.diagnosticSummary
        )
    }
}
