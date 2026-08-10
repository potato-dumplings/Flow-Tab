import Foundation
import XCTest

enum FlowTabUITestSettingsInitialAppearanceProjectionPolicy {
    static let projectionWatchdog: TimeInterval = 5
    static let appearanceTitle = "外观"
}

struct FlowTabUITestSettingsInitialAppearanceProjectionSnapshot:
    Equatable
{
    let appState: XCUIApplication.State
    let settingsContentExists: Bool
    let appearanceTitleExists: Bool
    let appearanceTitleValue: String?

    var isExactProjection: Bool {
        appState == .runningForeground
            && settingsContentExists
            && appearanceTitleExists
    }

    var diagnosticSummary: String {
        "isExactProjection=\(isExactProjection) "
            + "appState=\(String(describing: appState)) "
            + "settingsContentExists=\(settingsContentExists) "
            + "appearanceTitleExists=\(appearanceTitleExists) "
            + "appearanceTitleValue="
            + "\(String(reflecting: appearanceTitleValue))"
    }
}

final class FlowTabUITestSettingsInitialAppearanceProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsInitialAppearanceProjectionSnapshot
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
            FlowTabUITestSettingsInitialAppearanceProjectionSnapshot
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
        FlowTabUITestSettingsInitialAppearanceProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsInitialAppearanceProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsInitialAppearanceProjectionSnapshot
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

private struct FlowTabUITestSettingsInitialAppearanceProjectionElements {
    let settingsContent: XCUIElement
    let appearanceTitle: XCUIElement
}

extension FlowTabUITests {
    func assertSettingsInitialAppearanceProjectionAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String,
        trigger: () -> Void
    ) -> Bool {
        let elements = settingsInitialAppearanceProjectionElements(in: app)
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
            FlowTabUITestSettingsInitialAppearanceProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                readback: settingsInitialAppearanceProjectionReadback(
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
                "Initial Settings Appearance projection did not establish "
                    + "its initial readback. target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
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
                    FlowTabUITestSettingsInitialAppearanceProjectionPolicy
                        .projectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Initial Settings Appearance projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + "settingsContentIdentifier="
                    + "\(Identifier.settingsTabContent) "
                    + "expectedAppearanceTitle="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsInitialAppearanceProjectionPolicy
                                .appearanceTitle
                    )
                    + " "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func settingsInitialAppearanceProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestSettingsInitialAppearanceProjectionElements {
        FlowTabUITestSettingsInitialAppearanceProjectionElements(
            settingsContent: element(
                in: app,
                identifier: Identifier.settingsTabContent
            ),
            appearanceTitle: app.staticTexts[
                FlowTabUITestSettingsInitialAppearanceProjectionPolicy
                    .appearanceTitle
            ]
        )
    }

    private func settingsInitialAppearanceProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSettingsInitialAppearanceProjectionElements
    ) -> () -> FlowTabUITestSettingsInitialAppearanceProjectionSnapshot {
        {
            let appearanceTitleExists = elements.appearanceTitle.exists
            return FlowTabUITestSettingsInitialAppearanceProjectionSnapshot(
                appState: app.state,
                settingsContentExists: elements.settingsContent.exists,
                appearanceTitleExists: appearanceTitleExists,
                appearanceTitleValue:
                    appearanceTitleExists
                        ? self.elementStringValue(elements.appearanceTitle)
                        : nil
            )
        }
    }
}
