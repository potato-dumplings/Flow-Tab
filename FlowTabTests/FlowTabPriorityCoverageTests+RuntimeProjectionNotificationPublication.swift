import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherRuntimeProjectionNotificationsPublishWhileMainActorIsUnavailable() {
        let controller = SwitcherPanelController()
        let notificationNames: [Notification.Name] = [
            .runtimeAppSwitcherProjectionDidUpdate,
            .runtimeCurrentAppWindowProjectionDidUpdate,
            .runtimeCommittedSearchIndexDidUpdate
        ]
        let publishers = DispatchGroup()

        for name in notificationNames {
            publishers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                NotificationCenter.default.post(name: name, object: nil)
                publishers.leave()
            }
        }

        let publicationResult = publishers.wait(timeout: .now() + 0.5)
        XCTAssertEqual(
            publicationResult,
            .success,
            "Runtime projection publishers must not synchronously wait for MainActor delivery."
        )

        let cleanupDeadline = Date().addingTimeInterval(1)
        while publishers.wait(timeout: .now()) == .timedOut, Date() < cleanupDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(publishers.wait(timeout: .now()), .success)
        withExtendedLifetime(controller) {}
    }
}
