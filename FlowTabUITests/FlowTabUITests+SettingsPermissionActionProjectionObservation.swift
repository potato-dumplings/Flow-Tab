import Foundation
import XCTest

enum FlowTabUITestSettingsPermissionActionProjectionPolicy {
    static let watchdog: TimeInterval = 5
    static let maximumCompactActionHeight: CGFloat = 36
}

struct FlowTabUITestSettingsPermissionActionProjectionSnapshot:
    Equatable
{
    let applicationState: XCUIApplication.State
    let settingsContentExists: Bool
    let accessibilityActionExists: Bool
    let accessibilityActionIsHittable: Bool
    let accessibilityActionLabel: String
    let accessibilityActionHeight: CGFloat
    let screenCaptureActionExists: Bool
    let screenCaptureActionIsHittable: Bool
    let screenCaptureActionLabel: String
    let screenCaptureActionHeight: CGFloat

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "settingsContentExists=\(settingsContentExists) "
            + "accessibilityActionExists="
            + "\(accessibilityActionExists) "
            + "accessibilityActionIsHittable="
            + "\(accessibilityActionIsHittable) "
            + "accessibilityActionLabel="
            + "\(String(reflecting: accessibilityActionLabel)) "
            + "accessibilityActionHeight="
            + "\(accessibilityActionHeight) "
            + "screenCaptureActionExists="
            + "\(screenCaptureActionExists) "
            + "screenCaptureActionIsHittable="
            + "\(screenCaptureActionIsHittable) "
            + "screenCaptureActionLabel="
            + "\(String(reflecting: screenCaptureActionLabel)) "
            + "screenCaptureActionHeight="
            + "\(screenCaptureActionHeight)"
    }
}

struct FlowTabUITestSettingsPermissionActionProjectionExpectation:
    Equatable
{
    let expectedAccessibilityLabel: String?
    let expectedScreenCaptureLabel: String?
    let maximumActionHeight: CGFloat

    init(
        expectedAccessibilityLabel: String? = nil,
        expectedScreenCaptureLabel: String? = nil,
        maximumActionHeight: CGFloat =
            FlowTabUITestSettingsPermissionActionProjectionPolicy
                .maximumCompactActionHeight
    ) {
        self.expectedAccessibilityLabel = expectedAccessibilityLabel
        self.expectedScreenCaptureLabel = expectedScreenCaptureLabel
        self.maximumActionHeight = maximumActionHeight
    }

    func isSatisfied(
        by snapshot:
            FlowTabUITestSettingsPermissionActionProjectionSnapshot
    ) -> Bool {
        snapshot.applicationState == .runningForeground
            && snapshot.settingsContentExists
            && snapshot.accessibilityActionExists
            && snapshot.accessibilityActionIsHittable
            && snapshot.accessibilityActionHeight <= maximumActionHeight
            && label(
                snapshot.accessibilityActionLabel,
                matches: expectedAccessibilityLabel
            )
            && snapshot.screenCaptureActionExists
            && snapshot.screenCaptureActionIsHittable
            && snapshot.screenCaptureActionHeight <= maximumActionHeight
            && label(
                snapshot.screenCaptureActionLabel,
                matches: expectedScreenCaptureLabel
            )
    }

    private func label(
        _ actual: String,
        matches expected: String?
    ) -> Bool {
        expected.map { actual == $0 } ?? true
    }
}

final class
    FlowTabUITestSettingsPermissionActionProjectionObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsPermissionActionProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSettingsPermissionActionProjectionExpectation,
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
            FlowTabUITestSettingsPermissionActionProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "expectedAccessibilityLabel="
                    + "\(String(reflecting: expectation.expectedAccessibilityLabel)) "
                    + "expectedScreenCaptureLabel="
                    + "\(String(reflecting: expectation.expectedScreenCaptureLabel)) "
                    + "maximumActionHeight="
                    + "\(expectation.maximumActionHeight) "
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
        FlowTabUITestSettingsPermissionActionProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsPermissionActionProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsPermissionActionProjectionSnapshot
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

private struct FlowTabUITestSettingsPermissionActionProjectionElements {
    let settingsContent: XCUIElement
    let accessibilityAction: XCUIElement
    let screenCaptureAction: XCUIElement
}

extension FlowTabUITests {
    @discardableResult
    func assertSettingsPermissionActionProjection(
        in app: XCUIApplication,
        expectedAccessibilityLabel: String? = nil,
        expectedScreenCaptureLabel: String? = nil,
        targetDescription: String,
        trigger: () -> Void
    ) -> Bool {
        let elements = settingsPermissionActionProjectionElements(
            in: app
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
        var triggerDidComplete = false
        let owner =
            FlowTabUITestSettingsPermissionActionProjectionObservationOwner(
                expectation: .init(
                    expectedAccessibilityLabel:
                        expectedAccessibilityLabel,
                    expectedScreenCaptureLabel:
                        expectedScreenCaptureLabel
                ),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: { triggerDidComplete },
                readback: settingsPermissionActionProjectionReadback(
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
                "Settings permission actions initial readback was "
                    + "unavailable. target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        XCTAssertNil(owner.resolvedEvidence)

        trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        guard owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsPermissionActionProjectionPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "Settings permission actions projection watchdog "
                    + "expired. target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func settingsPermissionActionProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestSettingsPermissionActionProjectionElements {
        FlowTabUITestSettingsPermissionActionProjectionElements(
            settingsContent: element(
                in: app,
                identifier: Identifier.settingsTabContent
            ),
            accessibilityAction: element(
                in: app,
                identifier:
                    Identifier.settingsPermissionAccessibilityAction
            ),
            screenCaptureAction: element(
                in: app,
                identifier:
                    Identifier.settingsPermissionScreenCaptureAction
            )
        )
    }

    private func settingsPermissionActionProjectionReadback(
        in app: XCUIApplication,
        elements:
            FlowTabUITestSettingsPermissionActionProjectionElements
    ) -> () -> FlowTabUITestSettingsPermissionActionProjectionSnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return FlowTabUITestSettingsPermissionActionProjectionSnapshot(
                    applicationState: applicationState,
                    settingsContentExists: false,
                    accessibilityActionExists: false,
                    accessibilityActionIsHittable: false,
                    accessibilityActionLabel: "",
                    accessibilityActionHeight: 0,
                    screenCaptureActionExists: false,
                    screenCaptureActionIsHittable: false,
                    screenCaptureActionLabel: "",
                    screenCaptureActionHeight: 0
                )
            }
            let accessibilityActionExists =
                elements.accessibilityAction.exists
            let screenCaptureActionExists =
                elements.screenCaptureAction.exists
            return FlowTabUITestSettingsPermissionActionProjectionSnapshot(
                applicationState: applicationState,
                settingsContentExists: elements.settingsContent.exists,
                accessibilityActionExists: accessibilityActionExists,
                accessibilityActionIsHittable:
                    accessibilityActionExists
                    && elements.accessibilityAction.isHittable,
                accessibilityActionLabel:
                    accessibilityActionExists
                    ? elements.accessibilityAction.label
                    : "",
                accessibilityActionHeight:
                    accessibilityActionExists
                    ? elements.accessibilityAction.frame.height
                    : 0,
                screenCaptureActionExists: screenCaptureActionExists,
                screenCaptureActionIsHittable:
                    screenCaptureActionExists
                    && elements.screenCaptureAction.isHittable,
                screenCaptureActionLabel:
                    screenCaptureActionExists
                    ? elements.screenCaptureAction.label
                    : "",
                screenCaptureActionHeight:
                    screenCaptureActionExists
                    ? elements.screenCaptureAction.frame.height
                    : 0
            )
        }
    }
}
