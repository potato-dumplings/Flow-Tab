import Foundation
import XCTest

enum FlowTabUITestSettingsAppVisibilityDetailProjectionPolicy {
    static let watchdog: TimeInterval = 6
}

struct FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let managerExists: Bool
    let targetRowExists: Bool
    let targetRowHittable: Bool
    let projectionIdentifier: String?
    let showToggleExists: Bool
    let showToggleHittable: Bool

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "managerExists=\(managerExists) "
            + "targetRowExists=\(targetRowExists) "
            + "targetRowHittable=\(targetRowHittable) "
            + "projectionIdentifier="
            + "\(String(reflecting: projectionIdentifier)) "
            + "showToggleExists=\(showToggleExists) "
            + "showToggleHittable=\(showToggleHittable)"
    }
}

struct FlowTabUITestSettingsAppVisibilityDetailProjectionExpectation:
    Equatable
{
    let expectedProjectionIdentifierPrefix: String
    let baselineProjectionIdentifier: String?
    let targetRowIdentifier: String

    func isSatisfied(
        by snapshot: FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot
    ) -> Bool {
        guard let projectionIdentifier = snapshot.projectionIdentifier else {
            return false
        }
        return snapshot.applicationState == .runningForeground
            && snapshot.managerExists
            && snapshot.targetRowExists
            && snapshot.targetRowHittable
            && projectionIdentifier.hasPrefix(
                expectedProjectionIdentifierPrefix
            )
            && snapshot.showToggleExists
            && snapshot.showToggleHittable
    }
}

final class FlowTabUITestSettingsAppVisibilityDetailProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSettingsAppVisibilityDetailProjectionExpectation,
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
            FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot
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
        FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot
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

private struct FlowTabUITestSettingsAppVisibilityDetailProjectionElements {
    let manager: XCUIElement
    let targetRow: XCUIElement
    let projectionMarker: XCUIElement
    let showToggle: XCUIElement
}

extension FlowTabUITests {
    func settingsAppVisibilityShowToggleAfterSelecting(
        rowIdentifier: String,
        in app: XCUIApplication,
        targetDescription: String
    ) -> XCUIElement? {
        guard let projectionIdentifierPrefix =
            settingsAppVisibilityDetailProjectionIdentifierPrefix(
                forRowIdentifier: rowIdentifier
            )
        else {
            XCTFail(
                "App Visibility detail target identity was invalid. "
                    + "target=\(targetDescription) "
                    + "rowIdentifier=\(String(reflecting: rowIdentifier))"
            )
            return nil
        }
        let elements = settingsAppVisibilityDetailProjectionElements(
            in: app,
            rowIdentifier: rowIdentifier,
            projectionIdentifierPrefix: projectionIdentifierPrefix
        )
        let readback = settingsAppVisibilityDetailProjectionReadback(
            in: app,
            elements: elements
        )
        let baseline = readback()
        guard
            baseline.applicationState == .runningForeground,
            baseline.managerExists,
            baseline.targetRowExists,
            baseline.targetRowHittable
        else {
            XCTFail(
                "App Visibility detail baseline was unavailable. "
                    + "target=\(targetDescription) "
                    + baseline.diagnosticSummary
            )
            return nil
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
        var initialReadbackMayResolve = true
        var selectionTriggerDidComplete = false
        let owner =
            FlowTabUITestSettingsAppVisibilityDetailProjectionObservationOwner(
                expectation: .init(
                    expectedProjectionIdentifierPrefix:
                        projectionIdentifierPrefix,
                    baselineProjectionIdentifier:
                        baseline.projectionIdentifier,
                    targetRowIdentifier: rowIdentifier
                ),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: {
                    initialReadbackMayResolve
                        || selectionTriggerDidComplete
                },
                readback: readback
            )
        owner.start()
        initialReadbackMayResolve = false
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "App Visibility detail initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return nil
        }
        if owner.resolvedEvidence != nil {
            return elements.showToggle
        }

        tapElement(elements.targetRow)
        selectionTriggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence != nil {
            return elements.showToggle
        }

        deferredReadbacks.activate()
        guard owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityDetailProjectionPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "App Visibility detail projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return elements.showToggle
    }

    func settingsAppVisibilityDetailProjectionIdentifierPrefix(
        forRowIdentifier rowIdentifier: String
    ) -> String? {
        let rowPrefix = Identifier.settingsAppVisibilityAppRowPrefix
        guard rowIdentifier.hasPrefix(rowPrefix) else { return nil }
        let appIdentity = rowIdentifier.dropFirst(rowPrefix.count)
        guard !appIdentity.isEmpty else { return nil }
        return Identifier.settingsAppVisibilityDetailProjectionPrefix
            + String(appIdentity)
            + ".generation."
    }

    private func settingsAppVisibilityDetailProjectionElements(
        in app: XCUIApplication,
        rowIdentifier: String,
        projectionIdentifierPrefix: String
    ) -> FlowTabUITestSettingsAppVisibilityDetailProjectionElements {
        .init(
            manager: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityManager
            ),
            targetRow: element(in: app, identifier: rowIdentifier),
            projectionMarker: app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        projectionIdentifierPrefix
                    )
                )
                .firstMatch,
            showToggle: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityShowToggle
            )
        )
    }

    private func settingsAppVisibilityDetailProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSettingsAppVisibilityDetailProjectionElements
    ) -> () -> FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return .init(
                    applicationState: applicationState,
                    managerExists: false,
                    targetRowExists: false,
                    targetRowHittable: false,
                    projectionIdentifier: nil,
                    showToggleExists: false,
                    showToggleHittable: false
                )
            }
            let managerExists = elements.manager.exists
            let targetRowExists = managerExists && elements.targetRow.exists
            let projectionExists =
                managerExists && elements.projectionMarker.exists
            let showToggleExists =
                projectionExists && elements.showToggle.exists
            return .init(
                applicationState: applicationState,
                managerExists: managerExists,
                targetRowExists: targetRowExists,
                targetRowHittable:
                    targetRowExists && elements.targetRow.isHittable,
                projectionIdentifier: projectionExists
                    ? elements.projectionMarker.identifier
                    : nil,
                showToggleExists: showToggleExists,
                showToggleHittable:
                    showToggleExists && elements.showToggle.isHittable
            )
        }
    }
}
