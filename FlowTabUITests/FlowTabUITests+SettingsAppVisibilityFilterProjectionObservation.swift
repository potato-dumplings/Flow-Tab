import Foundation
import XCTest

enum FlowTabUITestSettingsAppVisibilityFilterProjectionPolicy {
    static let watchdog: TimeInterval = 6
}

struct FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let managerExists: Bool
    let hiddenActionExists: Bool
    let hiddenActionHittable: Bool
    let projectionIdentifier: String?
    let targetRowExists: Bool

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "managerExists=\(managerExists) "
            + "hiddenActionExists=\(hiddenActionExists) "
            + "hiddenActionHittable=\(hiddenActionHittable) "
            + "projectionIdentifier="
            + "\(String(reflecting: projectionIdentifier)) "
            + "targetRowExists=\(targetRowExists)"
    }
}

struct FlowTabUITestSettingsAppVisibilityFilterProjectionExpectation:
    Equatable
{
    let expectedProjectionIdentifierPrefix: String
    let baselineProjectionIdentifier: String
    let targetRowIdentifier: String

    func isSatisfied(
        by snapshot: FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot
    ) -> Bool {
        guard let projectionIdentifier = snapshot.projectionIdentifier else {
            return false
        }
        return snapshot.applicationState == .runningForeground
            && snapshot.managerExists
            && snapshot.hiddenActionExists
            && snapshot.hiddenActionHittable
            && projectionIdentifier.hasPrefix(
                expectedProjectionIdentifierPrefix
            )
            && projectionIdentifier != baselineProjectionIdentifier
            && snapshot.targetRowExists
    }
}

final class FlowTabUITestSettingsAppVisibilityFilterProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSettingsAppVisibilityFilterProjectionExpectation,
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
            FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "expectedProjectionIdentifierPrefix="
                    + "\(String(reflecting: expectation.expectedProjectionIdentifierPrefix)) "
                    + "baselineProjectionIdentifier="
                    + "\(String(reflecting: expectation.baselineProjectionIdentifier)) "
                    + "targetRowIdentifier="
                    + "\(String(reflecting: expectation.targetRowIdentifier)) "
                    + "acceptsResolution=\(acceptsResolution()) "
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
        FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func requestReadback(source: FlowTabUITestConditionObservationSource) {
        conditionOwner.requestReadback(source: source)
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

private struct FlowTabUITestSettingsAppVisibilityFilterProjectionElements {
    let manager: XCUIElement
    let hiddenAction: XCUIElement
    let projectionMarker: XCUIElement
    let targetRow: XCUIElement
}

extension FlowTabUITests {
    @discardableResult
    func assertSettingsAppVisibilityHiddenFilterProjection(
        targetRowIdentifier: String,
        in app: XCUIApplication,
        targetDescription: String
    ) -> Bool {
        let elements = settingsAppVisibilityFilterProjectionElements(
            in: app,
            targetRowIdentifier: targetRowIdentifier
        )
        let readback = settingsAppVisibilityFilterProjectionReadback(
            in: app,
            elements: elements
        )
        let baseline = readback()
        guard
            baseline.applicationState == .runningForeground,
            baseline.managerExists,
            baseline.hiddenActionExists,
            baseline.hiddenActionHittable,
            let baselineProjectionIdentifier = baseline.projectionIdentifier
        else {
            XCTFail(
                "App Visibility filter baseline was unavailable. "
                    + "target=\(targetDescription) "
                    + baseline.diagnosticSummary
            )
            return false
        }

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
        var filterTriggerDidComplete = false
        let owner =
            FlowTabUITestSettingsAppVisibilityFilterProjectionObservationOwner(
                expectation: .init(
                    expectedProjectionIdentifierPrefix:
                        Identifier
                            .settingsAppVisibilityHiddenFilterProjectionPrefix,
                    baselineProjectionIdentifier:
                        baselineProjectionIdentifier,
                    targetRowIdentifier: targetRowIdentifier
                ),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: { filterTriggerDidComplete },
                readback: readback
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "App Visibility filter initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }

        tapElement(elements.hiddenAction)
        filterTriggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence != nil {
            return true
        }

        deferredReadbacks.activate()
        guard owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityFilterProjectionPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "App Visibility filter projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func settingsAppVisibilityFilterProjectionElements(
        in app: XCUIApplication,
        targetRowIdentifier: String
    ) -> FlowTabUITestSettingsAppVisibilityFilterProjectionElements {
        let projectionMarker = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    Identifier.settingsAppVisibilityFilterProjectionPrefix
                )
            )
            .firstMatch
        return .init(
            manager: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityManager
            ),
            hiddenAction: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityFilterHidden
            ),
            projectionMarker: projectionMarker,
            targetRow: element(in: app, identifier: targetRowIdentifier)
        )
    }

    private func settingsAppVisibilityFilterProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSettingsAppVisibilityFilterProjectionElements
    ) -> () -> FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return .init(
                    applicationState: applicationState,
                    managerExists: false,
                    hiddenActionExists: false,
                    hiddenActionHittable: false,
                    projectionIdentifier: nil,
                    targetRowExists: false
                )
            }
            let managerExists = elements.manager.exists
            let hiddenActionExists =
                managerExists && elements.hiddenAction.exists
            let projectionExists =
                managerExists && elements.projectionMarker.exists
            return .init(
                applicationState: applicationState,
                managerExists: managerExists,
                hiddenActionExists: hiddenActionExists,
                hiddenActionHittable:
                    hiddenActionExists && elements.hiddenAction.isHittable,
                projectionIdentifier: projectionExists
                    ? elements.projectionMarker.identifier
                    : nil,
                targetRowExists:
                    projectionExists && elements.targetRow.exists
            )
        }
    }
}
