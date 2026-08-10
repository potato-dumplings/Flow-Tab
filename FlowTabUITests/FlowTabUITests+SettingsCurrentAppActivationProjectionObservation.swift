import Foundation
import XCTest

enum FlowTabUITestSettingsCurrentAppActivationProjectionPolicy {
    static let projectionWatchdog: TimeInterval = 12
    static let expectedHiddenCountText = "已隐藏 1 个应用"
}

struct FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot:
    Equatable
{
    let appState: XCUIApplication.State
    let settingsContentExists: Bool
    let showInCommandTabToggleExists: Bool
    let showInCommandTabToggleHittable: Bool
    let showInCommandTabToggleIsOn: Bool?
    let showInCommandTabToggleValue: String?
    let hiddenCountExists: Bool
    let hiddenCountValue: String?

    var isExactProjection: Bool {
        appState == .runningForeground
            && settingsContentExists
            && showInCommandTabToggleExists
            && showInCommandTabToggleIsOn == false
            && hiddenCountExists
    }

    var diagnosticSummary: String {
        "isExactProjection=\(isExactProjection) "
            + "appState=\(String(describing: appState)) "
            + "settingsContentExists=\(settingsContentExists) "
            + "showInCommandTabToggleExists="
            + "\(showInCommandTabToggleExists) "
            + "showInCommandTabToggleHittable="
            + "\(showInCommandTabToggleHittable) "
            + "showInCommandTabToggleIsOn="
            + "\(String(describing: showInCommandTabToggleIsOn)) "
            + "showInCommandTabToggleValue="
            + "\(String(reflecting: showInCommandTabToggleValue)) "
            + "hiddenCountExists=\(hiddenCountExists) "
            + "hiddenCountValue="
            + "\(String(reflecting: hiddenCountValue))"
    }
}

final class
    FlowTabUITestSettingsCurrentAppActivationProjectionObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot
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
            FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot
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
        FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot
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

extension FlowTabUITests {
    @discardableResult
    func assertSettingsCurrentAppActivationProjectionAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String,
        trigger: () -> Void
    ) -> Bool {
        let settingsContent = element(
            in: app,
            identifier: Identifier.settingsTabContent
        )
        let showInCommandTabToggle = element(
            in: app,
            identifier: Identifier.settingsAppearanceShowInCommandTab
        )
        let hiddenCount = app.staticTexts[
            FlowTabUITestSettingsCurrentAppActivationProjectionPolicy
                .expectedHiddenCountText
        ]
        var acceptsEvidence = false
        let owner =
            FlowTabUITestSettingsCurrentAppActivationProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                readback: {
                    let toggleExists =
                        showInCommandTabToggle.exists
                    let hiddenCountExists = hiddenCount.exists
                    return FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot(
                        appState: app.state,
                        settingsContentExists:
                            settingsContent.exists,
                        showInCommandTabToggleExists:
                            toggleExists,
                        showInCommandTabToggleHittable:
                            toggleExists
                                && showInCommandTabToggle
                                    .isHittable,
                        showInCommandTabToggleIsOn:
                            toggleExists
                                ? self.toggleIsOn(
                                    showInCommandTabToggle
                                )
                                : nil,
                        showInCommandTabToggleValue:
                            toggleExists
                                ? String(
                                    describing:
                                        showInCommandTabToggle
                                            .value
                                )
                                : nil,
                        hiddenCountExists:
                            hiddenCountExists,
                        hiddenCountValue:
                            hiddenCountExists
                                ? self.elementStringValue(
                                    hiddenCount
                                )
                                : nil
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Settings current-App activation projection did not "
                    + "establish its initial readback. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }

        trigger()
        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        guard
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsCurrentAppActivationProjectionPolicy
                        .projectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Settings current-App activation projection watchdog "
                    + "expired. target=\(targetDescription) "
                    + "expectedToggleIdentifier="
                    + "\(Identifier.settingsAppearanceShowInCommandTab) "
                    + "expectedHiddenCount="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsCurrentAppActivationProjectionPolicy
                                .expectedHiddenCountText
                    )
                    + " "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
