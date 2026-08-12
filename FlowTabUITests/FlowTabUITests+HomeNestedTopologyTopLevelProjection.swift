import Foundation
import XCTest

enum FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy {
    static let watchdog: TimeInterval = 8
    static let identifiers = [
        FlowTabUITests.Identifier.homeAppWeChat,
        FlowTabUITests.Identifier.homeAppTopLevelZeroWindow
    ]
}

extension FlowTabUITests {
    func assertHomeAndLogsNestedTopologyTopLevelRowsAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement? {
        let identifiers =
            FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy
                .identifiers
        let elements = waitForExactElementCollection(
            in: app,
            identifiers: identifiers,
            watchdog:
                FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy
                    .watchdog,
            targetDescription:
                "Home nested-topology top-level rows "
                + "target=\(targetDescription)",
            file: file,
            line: line,
            trigger: {
                self.assertHomeAndLogsHomeTabProjectionAfterNavigation(
                    in: app,
                    targetDescription: targetDescription,
                    file: file,
                    line: line
                )
            }
        )
        return elements?.first
    }

    func testHomeNestedTopologyTopLevelProjectionPolicy() {
        XCTAssertEqual(
            FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy
                .watchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy
                .watchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy
                .identifiers,
            [Identifier.homeAppWeChat, Identifier.homeAppTopLevelZeroWindow]
        )
        XCTAssertEqual(
            Set(
                FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy
                    .identifiers
            ).count,
            FlowTabUITestHomeNestedTopologyTopLevelProjectionPolicy
                .identifiers.count
        )
    }
}
