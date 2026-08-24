import Foundation

enum FlowTabUITestHomePermissionBoundaryProjectionPolicy {
    static let watchdog: TimeInterval = 6
}

struct FlowTabUITestHomePermissionBoundaryProjectionExpectation:
    Equatable
{
    private enum HiddenAppsExpectation: Equatable {
        case exact(String)
        case minimum(Int)

        func accepts(_ value: String?) -> Bool {
            switch self {
            case let .exact(expectedValue):
                return value == expectedValue
            case let .minimum(minimumCount):
                guard let value, let count = Int(value) else { return false }
                return count >= minimumCount
            }
        }

        var diagnosticSummary: String {
            switch self {
            case let .exact(value):
                return "hiddenAppsValue=\(value)"
            case let .minimum(count):
                return "minimumHiddenApps=\(count)"
            }
        }
    }

    let applicationRowIdentifier: String
    let applicationRowValue: String
    let hiddenAppsIdentifier: String
    private let hiddenAppsExpectation: HiddenAppsExpectation

    init(
        applicationRowIdentifier: String,
        applicationRowValue: String,
        hiddenAppsIdentifier: String,
        hiddenAppsValue: String
    ) {
        self.applicationRowIdentifier = applicationRowIdentifier
        self.applicationRowValue = applicationRowValue
        self.hiddenAppsIdentifier = hiddenAppsIdentifier
        hiddenAppsExpectation = .exact(hiddenAppsValue)
    }

    init(
        applicationRowIdentifier: String,
        applicationRowValue: String,
        hiddenAppsIdentifier: String,
        minimumHiddenApps: Int
    ) {
        self.applicationRowIdentifier = applicationRowIdentifier
        self.applicationRowValue = applicationRowValue
        self.hiddenAppsIdentifier = hiddenAppsIdentifier
        hiddenAppsExpectation = .minimum(minimumHiddenApps)
    }

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
            && hiddenAppsExpectation.accepts(snapshot.hiddenAppsValue)
    }

    var diagnosticSummary: String {
        "applicationRowIdentifier=\(applicationRowIdentifier) "
            + "applicationRowValue=\(applicationRowValue) "
            + "hiddenAppsIdentifier=\(hiddenAppsIdentifier) "
            + hiddenAppsExpectation.diagnosticSummary
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
