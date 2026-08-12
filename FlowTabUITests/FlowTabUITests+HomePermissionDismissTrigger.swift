import Foundation
import XCTest

enum FlowTabUITestHomePermissionDismissTriggerPolicy {
    static let readinessWatchdog: TimeInterval = 5
}

extension FlowTabUITests {
    @discardableResult
    func assertHomePermissionDismissTriggerReady(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let query = app.buttons.matching(
            identifier: Identifier.permissionDismiss
        )
        let didTap = tapFirstHittable(
            in: query,
            timeout:
                FlowTabUITestHomePermissionDismissTriggerPolicy
                    .readinessWatchdog
        )
        let finalCandidate = query.firstMatch
        XCTAssertTrue(
            didTap,
            "Home permission Dismiss trigger watchdog expired. "
                + "target=\(targetDescription) "
                + "identifier=\(Identifier.permissionDismiss) "
                + "finalCandidateCount=\(query.count) "
                + "finalExists=\(finalCandidate.exists) "
                + "finalHittable=\(finalCandidate.isHittable)",
            file: file,
            line: line
        )
        return didTap
    }

    func testHomePermissionDismissTriggerPolicyCompatibility() {
        let watchdog =
            FlowTabUITestHomePermissionDismissTriggerPolicy
                .readinessWatchdog
        XCTAssertEqual(watchdog, 5)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }
}
