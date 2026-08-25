import Foundation
import XCTest

enum FlowTabUITestSettingsAppearanceControlsProjectionPolicy {
    static let projectionWatchdog: TimeInterval = 20
    static let currentAppTitle = "像普通应用一样显示"
    static let currentAppDescription =
        "关闭后，当前应用将仅作为菜单栏辅助应用运行。"
}

struct FlowTabUITestSettingsAppearanceControlsProjectionSnapshot:
    Equatable
{
    let appState: XCUIApplication.State
    let settingsContentExists: Bool
    let currentAppToggleExists: Bool
    let currentAppToggleHittable: Bool
    let currentAppToggleIsOn: Bool?
    let currentAppToggleValue: String?
    let currentAppTitleExists: Bool
    let currentAppTitleValue: String?
    let currentAppDescriptionExists: Bool
    let currentAppDescriptionValue: String?

    var isExactProjection: Bool {
        appState == .runningForeground
            && settingsContentExists
            && currentAppToggleExists
            && currentAppToggleIsOn == false
            && currentAppTitleExists
            && currentAppDescriptionExists
    }

    var diagnosticSummary: String {
        "isExactProjection=\(isExactProjection) "
            + "appState=\(String(describing: appState)) "
            + "settingsContentExists=\(settingsContentExists) "
            + "currentAppToggleExists=\(currentAppToggleExists) "
            + "currentAppToggleHittable=\(currentAppToggleHittable) "
            + "currentAppToggleIsOn="
            + "\(String(describing: currentAppToggleIsOn)) "
            + "currentAppToggleValue="
            + "\(String(reflecting: currentAppToggleValue)) "
            + "currentAppTitleExists=\(currentAppTitleExists) "
            + "currentAppTitleValue="
            + "\(String(reflecting: currentAppTitleValue)) "
            + "currentAppDescriptionExists="
            + "\(currentAppDescriptionExists) "
            + "currentAppDescriptionValue="
            + "\(String(reflecting: currentAppDescriptionValue))"
    }
}

struct FlowTabUITestSettingsAppearanceControls {
    let currentAppToggle: XCUIElement
}

final class FlowTabUITestSettingsAppearanceControlsProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsAppearanceControlsProjectionSnapshot
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
            FlowTabUITestSettingsAppearanceControlsProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence() && snapshot.isExactProjection
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
        FlowTabUITestSettingsAppearanceControlsProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppearanceControlsProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppearanceControlsProjectionSnapshot
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

private struct FlowTabUITestSettingsAppearanceProjectionElements {
    let settingsContent: XCUIElement
    let controls: FlowTabUITestSettingsAppearanceControls
    let currentAppTitle: XCUIElement
    let currentAppDescription: XCUIElement
}

extension FlowTabUITests {
    func assertSettingsAppearanceControlsProjectionAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String,
        trigger: () -> Void
    ) -> FlowTabUITestSettingsAppearanceControls? {
        let elements = settingsAppearanceProjectionElements(in: app)
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
            FlowTabUITestSettingsAppearanceControlsProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                readback: settingsAppearanceProjectionReadback(
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
                "Settings Appearance controls did not establish their "
                    + "initial readback. target=\(targetDescription) "
                    + owner.diagnosticSummary
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
                    FlowTabUITestSettingsAppearanceControlsProjectionPolicy
                        .projectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Settings Appearance controls projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + "currentAppIdentifier="
                    + "\(Identifier.settingsAppearanceShowInCommandTab) "
                    + "expectedTitle="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsAppearanceControlsProjectionPolicy
                                .currentAppTitle
                    )
                    + " expectedDescription="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsAppearanceControlsProjectionPolicy
                                .currentAppDescription
                    )
                    + " "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return elements.controls
    }

    private func settingsAppearanceProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestSettingsAppearanceProjectionElements {
        FlowTabUITestSettingsAppearanceProjectionElements(
            settingsContent: element(
                in: app,
                identifier: Identifier.settingsTabContent
            ),
            controls: FlowTabUITestSettingsAppearanceControls(
                currentAppToggle: element(
                    in: app,
                    identifier:
                        Identifier.settingsAppearanceShowInCommandTab
                )
            ),
            currentAppTitle: app.staticTexts[
                FlowTabUITestSettingsAppearanceControlsProjectionPolicy
                    .currentAppTitle
            ],
            currentAppDescription: app.staticTexts[
                FlowTabUITestSettingsAppearanceControlsProjectionPolicy
                    .currentAppDescription
            ]
        )
    }

    private func settingsAppearanceProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSettingsAppearanceProjectionElements
    ) -> () -> FlowTabUITestSettingsAppearanceControlsProjectionSnapshot {
        {
            let currentAppExists = elements.controls.currentAppToggle.exists
            let titleExists = elements.currentAppTitle.exists
            let descriptionExists = elements.currentAppDescription.exists
            return FlowTabUITestSettingsAppearanceControlsProjectionSnapshot(
                appState: app.state,
                settingsContentExists: elements.settingsContent.exists,
                currentAppToggleExists: currentAppExists,
                currentAppToggleHittable:
                    currentAppExists
                        && elements.controls.currentAppToggle.isHittable,
                currentAppToggleIsOn:
                    currentAppExists
                        ? self.toggleIsOn(
                            elements.controls.currentAppToggle
                        )
                        : nil,
                currentAppToggleValue:
                    currentAppExists
                        ? String(
                            describing:
                                elements.controls.currentAppToggle.value
                        )
                        : nil,
                currentAppTitleExists: titleExists,
                currentAppTitleValue:
                    titleExists
                        ? self.elementStringValue(elements.currentAppTitle)
                        : nil,
                currentAppDescriptionExists: descriptionExists,
                currentAppDescriptionValue:
                    descriptionExists
                        ? self.elementStringValue(
                            elements.currentAppDescription
                        )
                        : nil
            )
        }
    }
}
