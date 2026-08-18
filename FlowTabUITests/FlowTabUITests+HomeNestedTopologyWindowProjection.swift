import Foundation
import XCTest

enum FlowTabUITestHomeNestedTopologyWindowProjectionPolicy {
    static let watchdog: TimeInterval = 6
    static let titles = [
        "微信",
        "微信（窗口）",
        "Mock Mini Program Window"
    ]
}

extension FlowTabUITests {
    @discardableResult
    func assertHomeAndLogsNestedTopologyWindowsAfterSelectingHost(
        _ hostRow: XCUIElement,
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let titles =
            FlowTabUITestHomeNestedTopologyWindowProjectionPolicy
                .titles
        var triggerCompleted = false
        let expectation =
            FlowTabUITestHomeWindowProjectionExpectation
                .titlesVisible(titles)
        let observation =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: expectation,
                acceptsEvidence: { triggerCompleted },
                readback: {
                    self.homeWindowProjectionSnapshot(
                        in: app,
                        expectation: expectation
                    )
                }
            )
        observation.start()
        defer { observation.cancel() }

        tapElement(hostRow)
        triggerCompleted = true
        observation.requestReadback(source: .triggerReadback)

        guard observation.waitForResolution(
            timeout:
                FlowTabUITestHomeNestedTopologyWindowProjectionPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "Home nested-topology window projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        return true
    }

    func testHomeNestedTopologyWindowProjectionPolicy() {
        XCTAssertEqual(
            FlowTabUITestHomeNestedTopologyWindowProjectionPolicy
                .watchdog,
            6
        )
        XCTAssertTrue(
            FlowTabUITestHomeNestedTopologyWindowProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeNestedTopologyWindowProjectionPolicy
                .watchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeNestedTopologyWindowProjectionPolicy
                .titles,
            ["微信", "微信（窗口）", "Mock Mini Program Window"]
        )
        XCTAssertEqual(
            Set(
                FlowTabUITestHomeNestedTopologyWindowProjectionPolicy
                    .titles
            ).count,
            FlowTabUITestHomeNestedTopologyWindowProjectionPolicy
                .titles.count
        )
    }
}
