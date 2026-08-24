import XCTest
@testable import FlowTabCore

final class ApplicationDirectoryMembershipTests: XCTestCase {
    func testSwitcherEligibilityIsLimitedToDirectoryMembership() {
        let membership = ApplicationDirectoryMembership(
            directoryAppIDs: ["regular", "flowtab"],
            switcherEligibleAppIDs: ["regular", "excluded"]
        )

        XCTAssertEqual(membership.directoryAppIDs, ["regular", "flowtab"])
        XCTAssertEqual(membership.switcherEligibleAppIDs, ["regular"])
    }

    func testRequiredExistingAppsProtectsOnlyCurrentlyEligibleMembers() {
        let membership = ApplicationDirectoryMembership(
            directoryAppIDs: ["stable", "still-regular", "flowtab"],
            switcherEligibleAppIDs: ["stable", "still-regular"]
        )

        XCTAssertEqual(
            membership.requiredExistingSwitcherAppIDs(
                existingAppIDs: ["stable", "still-regular", "accessory"],
                permittedMissingAppIDs: ["stable"]
            ),
            ["still-regular"]
        )
    }
}
