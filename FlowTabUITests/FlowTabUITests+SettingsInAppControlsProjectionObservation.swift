import Foundation
import XCTest

enum FlowTabUITestSettingsInAppControlsProjectionPolicy {
    static let projectionWatchdog: TimeInterval = 10
}

struct FlowTabUITestSettingsInAppControlsProjectionSnapshot: Equatable {
    let appState: XCUIApplication.State
    let settingsContentExists: Bool
    let modifierExists: Bool
    let modifierEnabled: Bool?
    let keyExists: Bool
    let keyEnabled: Bool?

    var isDisabledProjection: Bool {
        appState == .runningForeground
            && settingsContentExists
            && modifierExists
            && modifierEnabled == false
            && keyExists
            && keyEnabled == false
    }

    var diagnosticSummary: String {
        "isDisabledProjection=\(isDisabledProjection) "
            + "appState=\(String(describing: appState)) "
            + "settingsContentExists=\(settingsContentExists) "
            + "modifierExists=\(modifierExists) "
            + "modifierEnabled=\(String(describing: modifierEnabled)) "
            + "keyExists=\(keyExists) "
            + "keyEnabled=\(String(describing: keyEnabled))"
    }
}

struct FlowTabUITestSettingsInAppControls {
    let modifier: XCUIElement
    let key: XCUIElement
}

final class FlowTabUITestSettingsInAppControlsProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsInAppControlsProjectionSnapshot
        >

    init(
        acceptsEvidence: @escaping () -> Bool = { true },
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSettingsInAppControlsProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence() && snapshot.isDisabledProjection
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsInAppControlsProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsInAppControlsProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsInAppControlsProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

private struct FlowTabUITestSettingsInAppProjectionElements {
    let settingsContent: XCUIElement
    let controls: FlowTabUITestSettingsInAppControls
}

extension FlowTabUITests {
    func waitForDisabledSettingsInAppControls(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line,
        trigger: () -> Void
    ) -> FlowTabUITestSettingsInAppControls? {
        let elements = settingsInAppProjectionElements(in: app)
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
        var acceptsEvidence = false
        let owner =
            FlowTabUITestSettingsInAppControlsProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                readback: settingsInAppProjectionReadback(
                    in: app,
                    elements: elements
                )
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Settings in-app controls did not establish their initial "
                    + "readback. " + owner.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }

        trigger()
        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        guard
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsInAppControlsProjectionPolicy
                        .projectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Settings in-app controls projection watchdog expired. "
                    + "modifierIdentifier="
                    + "\(Identifier.settingsHotkeyInAppModifier) "
                    + "keyIdentifier="
                    + "\(Identifier.settingsHotkeyInAppKey) "
                    + owner.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }
        return elements.controls
    }

    private func settingsInAppProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestSettingsInAppProjectionElements {
        FlowTabUITestSettingsInAppProjectionElements(
            settingsContent: element(
                in: app,
                identifier: Identifier.settingsTabContent
            ),
            controls: FlowTabUITestSettingsInAppControls(
                modifier: element(
                    in: app,
                    identifier: Identifier.settingsHotkeyInAppModifier
                ),
                key: element(
                    in: app,
                    identifier: Identifier.settingsHotkeyInAppKey
                )
            )
        )
    }

    private func settingsInAppProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSettingsInAppProjectionElements
    ) -> () -> FlowTabUITestSettingsInAppControlsProjectionSnapshot {
        {
            let modifierExists = elements.controls.modifier.exists
            let keyExists = elements.controls.key.exists
            return FlowTabUITestSettingsInAppControlsProjectionSnapshot(
                appState: app.state,
                settingsContentExists: elements.settingsContent.exists,
                modifierExists: modifierExists,
                modifierEnabled:
                    modifierExists
                        ? elements.controls.modifier.isEnabled
                        : nil,
                keyExists: keyExists,
                keyEnabled:
                    keyExists
                        ? elements.controls.key.isEnabled
                        : nil
            )
        }
    }
}
