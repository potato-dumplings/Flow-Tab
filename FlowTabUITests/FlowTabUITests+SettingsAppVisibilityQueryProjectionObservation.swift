import Foundation
import XCTest

enum FlowTabUITestSettingsAppVisibilityQueryProjectionPolicy {
    static let watchdog: TimeInterval = 6
}

struct FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let managerExists: Bool
    let searchFieldExists: Bool
    let searchFieldValue: String
    let projectionIdentifier: String?
    let targetRowExists: Bool

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "managerExists=\(managerExists) "
            + "searchFieldExists=\(searchFieldExists) "
            + "searchFieldValue=\(String(reflecting: searchFieldValue)) "
            + "projectionIdentifier="
            + "\(String(reflecting: projectionIdentifier)) "
            + "targetRowExists=\(targetRowExists)"
    }
}

struct FlowTabUITestSettingsAppVisibilityQueryProjectionExpectation:
    Equatable
{
    let expectedQuery: String
    let projectionIdentifierPrefix: String
    let baselineProjectionIdentifier: String
    let targetRowIdentifier: String

    func isSatisfied(
        by snapshot: FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot
    ) -> Bool {
        guard let projectionIdentifier = snapshot.projectionIdentifier else {
            return false
        }
        return snapshot.applicationState == .runningForeground
            && snapshot.managerExists
            && snapshot.searchFieldExists
            && snapshot.searchFieldValue == expectedQuery
            && projectionIdentifier.hasPrefix(projectionIdentifierPrefix)
            && projectionIdentifier != baselineProjectionIdentifier
            && snapshot.targetRowExists
    }
}

final class FlowTabUITestSettingsAppVisibilityQueryProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSettingsAppVisibilityQueryProjectionExpectation,
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
            FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "expectedQuery=\(String(reflecting: expectation.expectedQuery)) "
                    + "projectionIdentifierPrefix="
                    + "\(String(reflecting: expectation.projectionIdentifierPrefix)) "
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
        FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot
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

private struct FlowTabUITestSettingsAppVisibilityQueryProjectionElements {
    let manager: XCUIElement
    let searchField: XCUIElement
    let projectionMarker: XCUIElement
    let targetRow: XCUIElement
}

extension FlowTabUITests {
    @discardableResult
    func assertSettingsAppVisibilityQueryProjection(
        _ query: String,
        targetRowIdentifier: String,
        in app: XCUIApplication,
        targetDescription: String
    ) -> Bool {
        let elements = settingsAppVisibilityQueryProjectionElements(
            in: app,
            targetRowIdentifier: targetRowIdentifier
        )
        let readback = settingsAppVisibilityQueryProjectionReadback(
            in: app,
            elements: elements
        )
        let baseline = readback()
        guard
            baseline.applicationState == .runningForeground,
            baseline.managerExists,
            baseline.searchFieldExists,
            let baselineProjectionIdentifier = baseline.projectionIdentifier
        else {
            XCTFail(
                "App Visibility query baseline was unavailable. "
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
        var queryTriggerDidComplete = false
        let owner =
            FlowTabUITestSettingsAppVisibilityQueryProjectionObservationOwner(
                expectation: .init(
                    expectedQuery: query,
                    projectionIdentifierPrefix:
                        Identifier
                            .settingsAppVisibilityQueryProjectionPrefix,
                    baselineProjectionIdentifier:
                        baselineProjectionIdentifier,
                    targetRowIdentifier: targetRowIdentifier
                ),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: { queryTriggerDidComplete },
                readback: readback
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "App Visibility query initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }

        tapElement(elements.searchField)
        pasteSettingsAppVisibilityQuery(query, in: app)
        queryTriggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence != nil {
            return true
        }

        deferredReadbacks.activate()
        guard owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityQueryProjectionPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "App Visibility query projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func settingsAppVisibilityQueryProjectionElements(
        in app: XCUIApplication,
        targetRowIdentifier: String
    ) -> FlowTabUITestSettingsAppVisibilityQueryProjectionElements {
        let projectionMarker = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    Identifier.settingsAppVisibilityQueryProjectionPrefix
                )
            )
            .firstMatch
        return .init(
            manager: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityManager
            ),
            searchField: element(
                in: app,
                identifier: Identifier.settingsAppVisibilitySearch
            ),
            projectionMarker: projectionMarker,
            targetRow: element(in: app, identifier: targetRowIdentifier)
        )
    }

    private func settingsAppVisibilityQueryProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSettingsAppVisibilityQueryProjectionElements
    ) -> () -> FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return .init(
                    applicationState: applicationState,
                    managerExists: false,
                    searchFieldExists: false,
                    searchFieldValue: "",
                    projectionIdentifier: nil,
                    targetRowExists: false
                )
            }
            let managerExists = elements.manager.exists
            let searchFieldExists = managerExists && elements.searchField.exists
            let projectionExists =
                managerExists && elements.projectionMarker.exists
            return .init(
                applicationState: applicationState,
                managerExists: managerExists,
                searchFieldExists: searchFieldExists,
                searchFieldValue: searchFieldExists
                    ? (elements.searchField.value as? String ?? "")
                    : "",
                projectionIdentifier: projectionExists
                    ? elements.projectionMarker.identifier
                    : nil,
                targetRowExists:
                    projectionExists && elements.targetRow.exists
            )
        }
    }
}
