import AppKit
import Foundation
import XCTest

enum FlowTabUITestSettingsAppVisibilityInventoryReadinessPolicy {
    static let watchdog: TimeInterval = 30
}

struct FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot:
    Equatable
{
    let applicationState: XCUIApplication.State
    let managerExists: Bool
    let readyMarkerExists: Bool

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "managerExists=\(managerExists) "
            + "readyMarkerExists=\(readyMarkerExists)"
    }
}

struct FlowTabUITestSettingsAppVisibilityInventoryReadinessExpectation:
    Equatable
{
    let readyMarkerIdentifier: String

    func isSatisfied(
        by snapshot:
            FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot
    ) -> Bool {
        snapshot.applicationState == .runningForeground
            && snapshot.managerExists
            && snapshot.readyMarkerExists
    }
}

final class
    FlowTabUITestSettingsAppVisibilityInventoryReadinessObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot
        >

    init(
        expectation:
            FlowTabUITestSettingsAppVisibilityInventoryReadinessExpectation,
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
            FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "readyMarkerIdentifier="
                    + "\(String(reflecting: expectation.readyMarkerIdentifier)) "
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
        FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot
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

private struct FlowTabUITestSettingsAppVisibilityInventoryReadinessElements {
    let manager: XCUIElement
    let readyMarker: XCUIElement
}

extension FlowTabUITests {
    func pasteSettingsAppVisibilityQuery(
        _ query: String,
        in app: XCUIApplication
    ) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(query, forType: .string) else {
            XCTFail("Failed to prepare App Visibility query pasteboard.")
            return
        }
        app.typeKey("v", modifierFlags: .command)
    }

    @discardableResult
    func assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String
    ) -> Bool {
        let elements =
            FlowTabUITestSettingsAppVisibilityInventoryReadinessElements(
                manager: element(
                    in: app,
                    identifier: Identifier.settingsAppVisibilityManager
                ),
                readyMarker: app.staticTexts[
                    Identifier.settingsAppVisibilityInventoryReadyMarker
                ]
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
        var acceptsInitialTarget = true
        var navigationDidComplete = false
        let owner =
            FlowTabUITestSettingsAppVisibilityInventoryReadinessObservationOwner(
                expectation: .init(
                    readyMarkerIdentifier:
                        Identifier
                            .settingsAppVisibilityInventoryReadyMarker
                ),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: {
                    acceptsInitialTarget || navigationDidComplete
                },
                readback:
                    settingsAppVisibilityInventoryReadinessReadback(
                        in: app,
                        elements: elements
                    )
            )
        owner.start()
        acceptsInitialTarget = false
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "App Visibility inventory initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        if owner.resolvedEvidence != nil {
            return true
        }

        let navigationSucceeded =
            assertSettingsAppVisibilityManagerProjectionAfterNavigation(
                in: app,
                targetDescription: "\(targetDescription) page"
            )
        navigationDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence != nil {
            return true
        }
        guard navigationSucceeded else {
            print(
                "App Visibility inventory navigation failed. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }

        deferredReadbacks.activate()
        guard owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityInventoryReadinessPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "App Visibility inventory watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func settingsAppVisibilityInventoryReadinessReadback(
        in app: XCUIApplication,
        elements:
            FlowTabUITestSettingsAppVisibilityInventoryReadinessElements
    ) -> () ->
        FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot
    {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return .init(
                    applicationState: applicationState,
                    managerExists: false,
                    readyMarkerExists: false
                )
            }
            let managerExists = elements.manager.exists
            return .init(
                applicationState: applicationState,
                managerExists: managerExists,
                readyMarkerExists:
                    managerExists && elements.readyMarker.exists
            )
        }
    }
}
