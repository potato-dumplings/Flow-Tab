import Foundation

enum FlowTabUITestHomePermissionBoundaryProjectionPolicy {
    static let watchdog: TimeInterval = 6
}

struct FlowTabUITestHomePermissionBoundaryProjectionExpectation:
    Equatable
{
    let applicationRowIdentifier: String
    let applicationRowValue: String
    let hiddenAppsIdentifier: String
    let hiddenAppsValue: String

    func isSatisfied(
        by snapshot:
            FlowTabUITestHomePermissionBoundaryProjectionSnapshot
    ) -> Bool {
        snapshot.applicationRowIdentifier
            == applicationRowIdentifier
            && snapshot.applicationRowExists
            && snapshot.applicationRowValue
                == applicationRowValue
            && snapshot.hiddenAppsIdentifier
                == hiddenAppsIdentifier
            && snapshot.hiddenAppsExists
            && snapshot.hiddenAppsValue == hiddenAppsValue
    }

    var diagnosticSummary: String {
        "applicationRowIdentifier=\(applicationRowIdentifier) "
            + "applicationRowValue=\(applicationRowValue) "
            + "hiddenAppsIdentifier=\(hiddenAppsIdentifier) "
            + "hiddenAppsValue=\(hiddenAppsValue)"
    }
}

struct FlowTabUITestHomePermissionBoundaryProjectionSnapshot:
    Equatable
{
    let applicationRowIdentifier: String
    let applicationRowExists: Bool
    let applicationRowValue: String?
    let hiddenAppsIdentifier: String
    let hiddenAppsExists: Bool
    let hiddenAppsValue: String?

    var diagnosticSummary: String {
        "applicationRow{identifier=\(applicationRowIdentifier) "
            + "exists=\(applicationRowExists) "
            + "value=\(applicationRowValue ?? "nil")} "
            + "hiddenApps{identifier=\(hiddenAppsIdentifier) "
            + "exists=\(hiddenAppsExists) "
            + "value=\(hiddenAppsValue ?? "nil")}"
    }
}

final class FlowTabUITestHomePermissionBoundaryProjectionObservationOwner {
    private let expectation:
        FlowTabUITestHomePermissionBoundaryProjectionExpectation
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestHomePermissionBoundaryProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestHomePermissionBoundaryProjectionExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestHomePermissionBoundaryProjectionSnapshot
    ) {
        self.expectation = expectation
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                expectation.isSatisfied(by: $0)
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestHomePermissionBoundaryProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomePermissionBoundaryProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "expected{\(expectation.diagnosticSummary)} "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}
