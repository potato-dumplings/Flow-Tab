import Foundation
import XCTest

enum FlowTabUITestHomePermissionReminderToggleProjectionPolicy {
    static let publicationWatchdog: TimeInterval = 5
}

extension FlowTabUITests {
    func waitForHomePermissionReminderToggleAfterOpeningSettings(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement? {
        let identifier = Identifier.permissionReminderSwitch
        let reminderToggle = element(in: app, identifier: identifier)
        let observation =
            FlowTabUITestElementExistenceObservationOwner(
                elementIdentifier: identifier,
                readback: { reminderToggle.exists }
            )
        observation.start()
        defer { observation.cancel() }

        guard observation.latestEvidence?.source == .initialReadback,
              observation.latestEvidence?.value.exists == false
        else {
            XCTFail(
                "Home permission reminder-toggle observation did not "
                    + "establish its absent initial readback. "
                    + "target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }

        guard assertHomePermissionOpenSettingsTriggerReady(
            in: app,
            targetDescription: targetDescription,
            file: file,
            line: line
        ) else {
            return nil
        }
        observation.markTriggerCompleted()

        guard observation.waitForResolution(
            timeout:
                FlowTabUITestHomePermissionReminderToggleProjectionPolicy
                    .publicationWatchdog
        ) != nil else {
            XCTFail(
                "Home permission reminder-toggle publication watchdog "
                    + "expired. target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }
        return reminderToggle
    }

    func testHomePermissionReminderToggleProjectionPolicyCompatibility() {
        let watchdog =
            FlowTabUITestHomePermissionReminderToggleProjectionPolicy
                .publicationWatchdog
        XCTAssertEqual(watchdog, 5)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }
}
