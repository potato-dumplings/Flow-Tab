import Foundation
import XCTest

enum FlowTabUITestSettingsWindowBehaviorControlsProjectionPolicy {
    static let projectionWatchdog: TimeInterval = 15
}

struct FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot:
    Equatable
{
    let appState: XCUIApplication.State
    let settingsContentExists: Bool
    let delayInputExists: Bool
    let delayInputHittable: Bool
    let delayInputValue: String?
    let autoRestoreToggleExists: Bool
    let autoRestoreToggleHittable: Bool
    let autoRestoreToggleIsOn: Bool?
    let autoRestoreToggleValue: String?
    let hideMinimizedToggleExists: Bool
    let hideMinimizedToggleHittable: Bool
    let hideMinimizedToggleIsOn: Bool?
    let hideMinimizedToggleValue: String?

    var isExactProjection: Bool {
        appState == .runningForeground
            && settingsContentExists
            && delayInputExists
            && delayInputValue?.isEmpty == false
            && autoRestoreToggleExists
            && autoRestoreToggleIsOn != nil
            && hideMinimizedToggleExists
            && hideMinimizedToggleIsOn != nil
    }

    var diagnosticSummary: String {
        "isExactProjection=\(isExactProjection) "
            + "appState=\(String(describing: appState)) "
            + "settingsContentExists=\(settingsContentExists) "
            + "delayInputExists=\(delayInputExists) "
            + "delayInputHittable=\(delayInputHittable) "
            + "delayInputValue=\(String(reflecting: delayInputValue)) "
            + "autoRestoreToggleExists=\(autoRestoreToggleExists) "
            + "autoRestoreToggleHittable=\(autoRestoreToggleHittable) "
            + "autoRestoreToggleIsOn="
            + "\(String(describing: autoRestoreToggleIsOn)) "
            + "autoRestoreToggleValue="
            + "\(String(reflecting: autoRestoreToggleValue)) "
            + "hideMinimizedToggleExists=\(hideMinimizedToggleExists) "
            + "hideMinimizedToggleHittable=\(hideMinimizedToggleHittable) "
            + "hideMinimizedToggleIsOn="
            + "\(String(describing: hideMinimizedToggleIsOn)) "
            + "hideMinimizedToggleValue="
            + "\(String(reflecting: hideMinimizedToggleValue))"
    }
}

struct FlowTabUITestSettingsWindowBehaviorControls {
    let delayInput: XCUIElement
    let autoRestoreToggle: XCUIElement
    let hideMinimizedToggle: XCUIElement
}

final class
    FlowTabUITestSettingsWindowBehaviorControlsProjectionObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot
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
            FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot
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
        FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot
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

private struct FlowTabUITestSettingsWindowBehaviorProjectionElements {
    let settingsContent: XCUIElement
    let controls: FlowTabUITestSettingsWindowBehaviorControls
}

extension FlowTabUITests {
    func assertSettingsWindowBehaviorControlsProjectionAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String,
        trigger: () -> Void
    ) -> FlowTabUITestSettingsWindowBehaviorControls? {
        let elements = settingsWindowBehaviorProjectionElements(in: app)
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
            FlowTabUITestSettingsWindowBehaviorControlsProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                readback: settingsWindowBehaviorProjectionReadback(
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
                "Settings Window Behavior controls did not establish their "
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
                    FlowTabUITestSettingsWindowBehaviorControlsProjectionPolicy
                        .projectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Settings Window Behavior controls projection watchdog "
                    + "expired. target=\(targetDescription) "
                    + "delayIdentifier="
                    + "\(Identifier.settingsWindowAutoEnterDelayInput) "
                    + "autoRestoreIdentifier="
                    + "\(Identifier.settingsWindowAutoRestoreMinimized) "
                    + "hideMinimizedIdentifier="
                    + "\(Identifier.settingsWindowHideMinimizedApps) "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return elements.controls
    }

    @discardableResult
    func assertSettingsWindowBehaviorHideMinimizedAppsCanBeSet(
        in app: XCUIApplication,
        to isEnabled: Bool,
        targetDescription: String
    ) -> Bool {
        guard
            let controls =
                assertSettingsWindowBehaviorControlsProjectionAfterNavigation(
                    in: app,
                    targetDescription: targetDescription,
                    trigger: {
                        openSettingsTab(in: app)
                    }
                )
        else {
            return false
        }

        setToggle(controls.hideMinimizedToggle, to: isEnabled)
        let observedState = toggleIsOn(controls.hideMinimizedToggle)
        XCTAssertEqual(
            observedState,
            isEnabled,
            "Settings hide-minimized state mismatch. "
                + "target=\(targetDescription) "
                + "identifier="
                + "\(Identifier.settingsWindowHideMinimizedApps) "
                + "observed=\(observedState) expected=\(isEnabled)"
        )
        return observedState == isEnabled
    }

    private func settingsWindowBehaviorProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestSettingsWindowBehaviorProjectionElements {
        FlowTabUITestSettingsWindowBehaviorProjectionElements(
            settingsContent: element(
                in: app,
                identifier: Identifier.settingsTabContent
            ),
            controls: FlowTabUITestSettingsWindowBehaviorControls(
                delayInput: element(
                    in: app,
                    identifier: Identifier.settingsWindowAutoEnterDelayInput
                ),
                autoRestoreToggle: element(
                    in: app,
                    identifier:
                        Identifier.settingsWindowAutoRestoreMinimized
                ),
                hideMinimizedToggle: element(
                    in: app,
                    identifier:
                        Identifier.settingsWindowHideMinimizedApps
                )
            )
        )
    }

    private func settingsWindowBehaviorProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSettingsWindowBehaviorProjectionElements
    ) -> () ->
        FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot
    {
        {
            let delayInputExists = elements.controls.delayInput.exists
            let autoRestoreExists =
                elements.controls.autoRestoreToggle.exists
            let hideMinimizedExists =
                elements.controls.hideMinimizedToggle.exists
            return
                FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot(
                    appState: app.state,
                    settingsContentExists: elements.settingsContent.exists,
                    delayInputExists: delayInputExists,
                    delayInputHittable:
                        delayInputExists
                            && elements.controls.delayInput.isHittable,
                    delayInputValue:
                        delayInputExists
                            ? self.elementStringValue(
                                elements.controls.delayInput
                            )
                            : nil,
                    autoRestoreToggleExists: autoRestoreExists,
                    autoRestoreToggleHittable:
                        autoRestoreExists
                            && elements.controls.autoRestoreToggle.isHittable,
                    autoRestoreToggleIsOn:
                        autoRestoreExists
                            ? self.toggleIsOn(
                                elements.controls.autoRestoreToggle
                            )
                            : nil,
                    autoRestoreToggleValue:
                        autoRestoreExists
                            ? self.elementStringValue(
                                elements.controls.autoRestoreToggle
                            )
                            : nil,
                    hideMinimizedToggleExists: hideMinimizedExists,
                    hideMinimizedToggleHittable:
                        hideMinimizedExists
                            && elements.controls.hideMinimizedToggle.isHittable,
                    hideMinimizedToggleIsOn:
                        hideMinimizedExists
                            ? self.toggleIsOn(
                                elements.controls.hideMinimizedToggle
                            )
                            : nil,
                    hideMinimizedToggleValue:
                        hideMinimizedExists
                            ? self.elementStringValue(
                                elements.controls.hideMinimizedToggle
                            )
                            : nil
                )
        }
    }
}
