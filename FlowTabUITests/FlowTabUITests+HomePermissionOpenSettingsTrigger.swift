import Foundation
import XCTest

enum FlowTabUITestHomePermissionOpenSettingsTriggerPolicy {
    static let readinessWatchdog: TimeInterval = 5
}

extension FlowTabUITests {
    @discardableResult
    func assertHomePermissionOpenSettingsTriggerReady(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let query = app.buttons.matching(
            identifier: Identifier.permissionOpenSettings
        )
        let didTap = tapFirstHittable(
            in: query,
            timeout:
                FlowTabUITestHomePermissionOpenSettingsTriggerPolicy
                    .readinessWatchdog
        )
        let finalCandidate = query.firstMatch
        XCTAssertTrue(
            didTap,
            "Home permission Open Settings trigger watchdog expired. "
                + "target=\(targetDescription) "
                + "identifier=\(Identifier.permissionOpenSettings) "
                + "finalCandidateCount=\(query.count) "
                + "finalExists=\(finalCandidate.exists) "
                + "finalHittable=\(finalCandidate.isHittable)",
            file: file,
            line: line
        )
        return didTap
    }

    func testHomePermissionOpenSettingsTriggerPolicyCompatibility() {
        let watchdog =
            FlowTabUITestHomePermissionOpenSettingsTriggerPolicy
                .readinessWatchdog
        XCTAssertEqual(watchdog, 5)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }
}
