import Foundation
import XCTest

enum FlowTabUITestSettingsAppVisibilityManagerProjectionPolicy {
    static let watchdog: TimeInterval = 6
}

struct FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot:
    Equatable
{
    let applicationState: XCUIApplication.State
    let settingsContentExists: Bool
    let manageActionExists: Bool
    let manageActionIsHittable: Bool
    let managerExists: Bool
    let backActionExists: Bool
    let backActionIsHittable: Bool
    let expectedManagerTitleExists: Bool

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "settingsContentExists=\(settingsContentExists) "
            + "manageActionExists=\(manageActionExists) "
            + "manageActionIsHittable=\(manageActionIsHittable) "
            + "managerExists=\(managerExists) "
            + "backActionExists=\(backActionExists) "
            + "backActionIsHittable=\(backActionIsHittable) "
            + "expectedManagerTitleExists="
            + "\(expectedManagerTitleExists)"
    }
}

struct FlowTabUITestSettingsAppVisibilityManagerProjectionExpectation:
    Equatable
{
    let expectedManagerTitle: String?

    init(expectedManagerTitle: String? = nil) {
        self.expectedManagerTitle = expectedManagerTitle
    }

    func isSatisfied(
        by snapshot:
            FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot
    ) -> Bool {
        snapshot.applicationState == .runningForeground
            && snapshot.settingsContentExists
            && !snapshot.manageActionExists
            && snapshot.managerExists
            && snapshot.backActionExists
            && snapshot.backActionIsHittable
            && (expectedManagerTitle == nil
                || snapshot.expectedManagerTitleExists)
    }
}

final class
    FlowTabUITestSettingsAppVisibilityManagerProjectionObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSettingsAppVisibilityManagerProjectionExpectation,
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
            FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "expectedManagerTitle="
                    + "\(String(reflecting: expectation.expectedManagerTitle)) "
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
        FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot
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

private struct
    FlowTabUITestSettingsAppVisibilityManagerProjectionElements
{
    let settingsContent: XCUIElement
    let manageAction: XCUIElement
    let manager: XCUIElement
    let backAction: XCUIElement
    let expectedManagerTitle: XCUIElement?
}

extension FlowTabUITests {
    @discardableResult
    func assertSettingsAppVisibilityManagerProjectionAfterNavigation(
        in app: XCUIApplication,
        expectedManagerTitle: String? = nil,
        targetDescription: String
    ) -> Bool {
        let elements =
            settingsAppVisibilityManagerProjectionElements(
                in: app,
                expectedManagerTitle: expectedManagerTitle
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
        var navigationAttemptDidComplete = false
        let owner =
            FlowTabUITestSettingsAppVisibilityManagerProjectionObservationOwner(
                expectation: .init(
                    expectedManagerTitle: expectedManagerTitle
                ),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: {
                    acceptsInitialTarget
                        || navigationAttemptDidComplete
                },
                readback:
                    settingsAppVisibilityManagerProjectionReadback(
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
                "App Visibility manager initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        if owner.resolvedEvidence != nil {
            return true
        }

        let manageActionQuery = app.buttons.matching(
            identifier: Identifier.settingsAppVisibilityManage
        )
        let triggerSucceeded = tapFirstHittable(
            in: manageActionQuery,
            timeout:
                FlowTabUITestSettingsAppVisibilityManagerProjectionPolicy
                    .watchdog
        )
        navigationAttemptDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence != nil {
            return true
        }
        guard triggerSucceeded else {
            XCTFail(
                "App Visibility manager trigger watchdog expired. "
                    + "target=\(targetDescription) "
                    + "finalCandidateCount=\(manageActionQuery.count) "
                    + owner.diagnosticSummary
            )
            return false
        }

        deferredReadbacks.activate()
        guard owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityManagerProjectionPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "App Visibility manager projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func settingsAppVisibilityManagerProjectionElements(
        in app: XCUIApplication,
        expectedManagerTitle: String?
    ) -> FlowTabUITestSettingsAppVisibilityManagerProjectionElements {
        FlowTabUITestSettingsAppVisibilityManagerProjectionElements(
            settingsContent: element(
                in: app,
                identifier: Identifier.settingsTabContent
            ),
            manageAction: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityManage
            ),
            manager: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityManager
            ),
            backAction: element(
                in: app,
                identifier: Identifier.settingsAppVisibilityBack
            ),
            expectedManagerTitle: expectedManagerTitle.map {
                app.staticTexts[$0]
            }
        )
    }

    private func settingsAppVisibilityManagerProjectionReadback(
        in app: XCUIApplication,
        elements:
            FlowTabUITestSettingsAppVisibilityManagerProjectionElements
    ) -> () ->
        FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot
    {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot(
                    applicationState: applicationState,
                    settingsContentExists: false,
                    manageActionExists: false,
                    manageActionIsHittable: false,
                    managerExists: false,
                    backActionExists: false,
                    backActionIsHittable: false,
                    expectedManagerTitleExists: false
                )
            }
            let manageActionExists = elements.manageAction.exists
            let backActionExists = elements.backAction.exists
            return FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot(
                applicationState: applicationState,
                settingsContentExists: elements.settingsContent.exists,
                manageActionExists: manageActionExists,
                manageActionIsHittable:
                    manageActionExists
                    && elements.manageAction.isHittable,
                managerExists: elements.manager.exists,
                backActionExists: backActionExists,
                backActionIsHittable:
                    backActionExists
                    && elements.backAction.isHittable,
                expectedManagerTitleExists:
                    elements.expectedManagerTitle?.exists ?? true
            )
        }
    }
}
