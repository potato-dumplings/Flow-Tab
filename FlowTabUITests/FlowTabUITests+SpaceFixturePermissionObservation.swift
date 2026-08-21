import Foundation
import XCTest

enum SpaceFixtureWorkflowPermissionProjection: String, Equatable {
    case projecting
    case granted
    case missing
}

struct SpaceFixtureWorkflowPermissionSnapshot: Equatable {
    static let grantedStatusLabels: Set<String> = [
        "Granted",
        "已授予",
    ]
    static let missingStatusLabels: Set<String> = [
        "Missing",
        "未授权",
    ]

    let applicationState: String
    let statusCardExists: Bool
    let accessibilityRowExists: Bool
    let screenCaptureRowExists: Bool
    let accessibilityStatusExists: Bool
    let accessibilityStatusLabel: String
    let screenCaptureStatusExists: Bool
    let screenCaptureStatusLabel: String
    let bannerExists: Bool
    let openSettingsCandidateCount: Int
    let openSettingsHittable: Bool
    let dismissActionExists: Bool

    var projection: SpaceFixtureWorkflowPermissionProjection {
        guard statusCardExists,
              accessibilityRowExists,
              screenCaptureRowExists,
              accessibilityStatusExists,
              screenCaptureStatusExists
        else {
            return .projecting
        }
        let terminalLabels = [
            accessibilityStatusLabel,
            screenCaptureStatusLabel,
        ]
        guard terminalLabels.allSatisfy({
            Self.grantedStatusLabels.contains($0)
                || Self.missingStatusLabels.contains($0)
        }) else {
            return .projecting
        }
        let missingCount = terminalLabels.filter {
            Self.missingStatusLabels.contains($0)
        }.count
        if missingCount == 0,
           terminalLabels.allSatisfy(
               Self.grantedStatusLabels.contains
           )
        {
            return .granted
        }
        guard missingCount > 0,
              bannerExists,
              openSettingsCandidateCount > 0,
              openSettingsHittable,
              dismissActionExists
        else {
            return .projecting
        }
        return .missing
    }

    var diagnosticSummary: String {
        "applicationState=\(applicationState) "
            + "projection=\(projection.rawValue) "
            + "statusCardExists=\(statusCardExists) "
            + "accessibilityRowExists=\(accessibilityRowExists) "
            + "screenCaptureRowExists=\(screenCaptureRowExists) "
            + "accessibilityStatusExists="
            + "\(accessibilityStatusExists) "
            + "accessibilityStatusLabel="
            + "\(String(reflecting: accessibilityStatusLabel)) "
            + "screenCaptureStatusExists="
            + "\(screenCaptureStatusExists) "
            + "screenCaptureStatusLabel="
            + "\(String(reflecting: screenCaptureStatusLabel)) "
            + "bannerExists=\(bannerExists) "
            + "openSettingsCandidateCount="
            + "\(openSettingsCandidateCount) "
            + "openSettingsHittable=\(openSettingsHittable) "
            + "dismissActionExists=\(dismissActionExists)"
    }
}

final class SpaceFixtureWorkflowPermissionObservationOwner {
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration?
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureWorkflowPermissionSnapshot
        >

    init(
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            SpaceFixtureWorkflowPermissionSnapshot
    ) {
        let deferredReadbacks = observationRegistration.map {
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: $0
            )
        }
        let deferredRegistration:
            FlowTabUITestConditionObservationRegistration? =
                deferredReadbacks.map { deferredReadbacks in
                    { readback in
                        deferredReadbacks.register(readback)
                    }
                }
        self.deferredReadbacks = deferredReadbacks
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: deferredRegistration,
            readback: readback,
            isSatisfied: {
                $0.projection != .projecting
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func markTriggerCompleted() {
        guard conditionOwner.resolvedEvidence == nil else { return }
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks?.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        SpaceFixtureWorkflowPermissionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        SpaceFixtureWorkflowPermissionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        SpaceFixtureWorkflowPermissionSnapshot
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
    func assertSpaceFixtureWorkflowPermissionsAvailable() -> Bool {
        let app = makeRealRuntimeFlowTabApp(
            showsPermissionReminder: true,
            additionalArguments: []
        )
        let observation =
            makeSpaceFixtureWorkflowPermissionObservation(
                in: app
            )
        observation.start()
        launchFlowTabUITestApplication(app)
        defer {
            observation.cancel()
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }

        return resolveSpaceFixtureWorkflowPermissions(
            in: app,
            observation: observation
        )
    }

    func assertSpaceFixtureWorkflowPermissionsAvailable(
        in app: XCUIApplication
    ) -> Bool {
        let observation =
            makeSpaceFixtureWorkflowPermissionObservation(
                in: app
            )
        observation.start()
        defer { observation.cancel() }

        return resolveSpaceFixtureWorkflowPermissions(
            in: app,
            observation: observation
        )
    }

    private func resolveSpaceFixtureWorkflowPermissions(
        in app: XCUIApplication,
        observation:
            SpaceFixtureWorkflowPermissionObservationOwner
    ) -> Bool {
        let readinessSatisfied =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .foregroundActivation
            )
        XCTAssertTrue(
            readinessSatisfied,
            "Space Fixture permission-preflight foreground readiness "
                + "watchdog expired. "
                + "finalState=\(String(describing: app.state))"
        )
        guard readinessSatisfied else { return false }

        let homeButtons = app.buttons.matching(
            identifier: Identifier.homeTabButton
        )
        let navigationSatisfied = tapFirstHittable(
            in: homeButtons,
            timeout:
                FlowTabUITestSupportWatchdogPolicy
                    .spaceFixtureNavigation
        )
        XCTAssertTrue(
            navigationSatisfied,
            "Space Fixture permission-preflight Home navigation trigger "
                + "watchdog expired. "
                + "identifier=\(Identifier.homeTabButton) "
                + "finalCandidateCount=\(homeButtons.count)"
        )
        guard navigationSatisfied else { return false }

        observation.markTriggerCompleted()
        guard let evidence = observation.waitForResolution(
            timeout:
                FlowTabUITestSupportWatchdogPolicy
                    .permissionStateProjection
        ) else {
            XCTFail(
                "Space Fixture permission projection watchdog expired. "
                    + observation.diagnosticSummary
            )
            return false
        }
        guard evidence.value.projection == .granted else {
            XCTFail(
                """
                Space Fixture workflow requires Accessibility and Screen Recording permissions.
                FlowTab published a complete missing-permissions surface instead of two granted statuses.
                \(observation.diagnosticSummary)
                """
            )
            return false
        }
        return true
    }

    private func makeSpaceFixtureWorkflowPermissionObservation(
        in app: XCUIApplication
    ) -> SpaceFixtureWorkflowPermissionObservationOwner {
        let statusCard = element(
            in: app,
            identifier: Identifier.sidebarPermissionStatus
        )
        let accessibilityRow = element(
            in: app,
            identifier: Identifier.sidebarPermissionAccessibility
        )
        let screenCaptureRow = element(
            in: app,
            identifier: Identifier.sidebarPermissionScreenCapture
        )
        let accessibilityStatus = element(
            in: app,
            identifier:
                Identifier.sidebarPermissionAccessibilityStatus
        )
        let screenCaptureStatus = element(
            in: app,
            identifier:
                Identifier.sidebarPermissionScreenCaptureStatus
        )
        let banner = element(
            in: app,
            identifier: Identifier.permissionBanner
        )
        let openSettingsButtons = app.buttons.matching(
            identifier: Identifier.permissionOpenSettings
        )
        let dismissAction = element(
            in: app,
            identifier: Identifier.permissionDismiss
        )
        return SpaceFixtureWorkflowPermissionObservationOwner(
            readback: {
                self.spaceFixtureWorkflowPermissionSnapshot(
                    app: app,
                    statusCard: statusCard,
                    accessibilityRow: accessibilityRow,
                    screenCaptureRow: screenCaptureRow,
                    accessibilityStatus: accessibilityStatus,
                    screenCaptureStatus: screenCaptureStatus,
                    banner: banner,
                    openSettingsButtons: openSettingsButtons,
                    dismissAction: dismissAction
                )
            }
        )
    }

    private func spaceFixtureWorkflowPermissionSnapshot(
        app: XCUIApplication,
        statusCard: XCUIElement,
        accessibilityRow: XCUIElement,
        screenCaptureRow: XCUIElement,
        accessibilityStatus: XCUIElement,
        screenCaptureStatus: XCUIElement,
        banner: XCUIElement,
        openSettingsButtons: XCUIElementQuery,
        dismissAction: XCUIElement
    ) -> SpaceFixtureWorkflowPermissionSnapshot {
        let appState = app.state
        guard appState == .runningForeground
                || appState == .runningBackground
        else {
            return SpaceFixtureWorkflowPermissionSnapshot(
                applicationState: String(describing: appState),
                statusCardExists: false,
                accessibilityRowExists: false,
                screenCaptureRowExists: false,
                accessibilityStatusExists: false,
                accessibilityStatusLabel: "",
                screenCaptureStatusExists: false,
                screenCaptureStatusLabel: "",
                bannerExists: false,
                openSettingsCandidateCount: 0,
                openSettingsHittable: false,
                dismissActionExists: false
            )
        }

        let statusCardExists = statusCard.exists
        let accessibilityStatusExists = accessibilityStatus.exists
        let accessibilityStatusLabel = accessibilityStatusExists
            ? accessibilityStatus.label
            : ""
        let screenCaptureStatusExists = screenCaptureStatus.exists
        let screenCaptureStatusLabel = screenCaptureStatusExists
            ? screenCaptureStatus.label
            : ""
        let containsMissingStatus =
            SpaceFixtureWorkflowPermissionSnapshot
                .missingStatusLabels
                .contains(accessibilityStatusLabel)
            || SpaceFixtureWorkflowPermissionSnapshot
                .missingStatusLabels
                .contains(screenCaptureStatusLabel)
        let openSettingsCandidates = containsMissingStatus
            ? openSettingsButtons.allElementsBoundByIndex
            : []
        return SpaceFixtureWorkflowPermissionSnapshot(
            applicationState: String(describing: appState),
            statusCardExists: statusCardExists,
            accessibilityRowExists: accessibilityRow.exists,
            screenCaptureRowExists: screenCaptureRow.exists,
            accessibilityStatusExists: accessibilityStatusExists,
            accessibilityStatusLabel: accessibilityStatusLabel,
            screenCaptureStatusExists: screenCaptureStatusExists,
            screenCaptureStatusLabel: screenCaptureStatusLabel,
            bannerExists:
                containsMissingStatus && banner.exists,
            openSettingsCandidateCount:
                openSettingsCandidates.count,
            openSettingsHittable:
                openSettingsCandidates.contains(where: \.isHittable),
            dismissActionExists:
                containsMissingStatus && dismissAction.exists
        )
    }
}
