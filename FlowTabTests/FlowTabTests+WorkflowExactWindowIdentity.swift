import CoreGraphics
import XCTest

extension FlowTabTests {
    func testWorkflowExactWindowIdentityRejectsAbsentAndMismatchedEvidence() {
        let frame = CGRect(
            x: 100,
            y: 100,
            width: 960,
            height: 640
        )

        XCTAssertFalse(
            SpaceFixtureWorkflowDesktopAnchorSnapshot
                .exactWindowIdentityMatches(
                    cgWindowNumber: nil,
                    xcuiWindowFrame: nil,
                    cgWindowFrame: nil
                )
        )
        XCTAssertFalse(
            SpaceFixtureWorkflowDesktopAnchorSnapshot
                .exactWindowIdentityMatches(
                    cgWindowNumber: 42,
                    xcuiWindowFrame: nil,
                    cgWindowFrame: nil
                )
        )
        XCTAssertFalse(
            SpaceFixtureWorkflowDesktopAnchorSnapshot
                .exactWindowIdentityMatches(
                    cgWindowNumber: 42,
                    xcuiWindowFrame: frame,
                    cgWindowFrame:
                        frame.offsetBy(dx: 10, dy: 0)
                )
        )
        XCTAssertTrue(
            SpaceFixtureWorkflowDesktopAnchorSnapshot
                .exactWindowIdentityMatches(
                    cgWindowNumber: 42,
                    xcuiWindowFrame: frame,
                    cgWindowFrame: frame
                )
        )
    }
}
