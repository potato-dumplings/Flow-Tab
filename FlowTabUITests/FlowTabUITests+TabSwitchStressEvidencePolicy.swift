import Foundation
import XCTest

enum TabSwitchStressUITestPolicy {
    static let measurementIterations = 3
    static let workloadDurationSeconds: UInt64 = 2
    static let switchCadenceMilliseconds: UInt64 = 16

    static let applicationReadinessWatchdog: TimeInterval = 5
    static let completionEvidenceWatchdog: TimeInterval = 10
    static let naturalTerminationWatchdog: TimeInterval = 10

    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    private static let nanosecondsPerMillisecond: UInt64 = 1_000_000

    static var workloadDurationArgument: String {
        String(workloadDurationSeconds)
    }

    static var switchCadenceArgument: String {
        String(switchCadenceMilliseconds)
    }

    static var workloadDurationNanoseconds: UInt64 {
        workloadDurationSeconds * nanosecondsPerSecond
    }

    static var switchCadenceNanoseconds: UInt64 {
        switchCadenceMilliseconds * nanosecondsPerMillisecond
    }

    static var requiredSwitches: UInt64 {
        (
            workloadDurationNanoseconds
                + switchCadenceNanoseconds
                - 1
        ) / switchCadenceNanoseconds
    }
}

extension FlowTabUITests {
    func assertTabSwitchStressApplicationCleanup(
        _ app: XCUIApplication
    ) {
        guard app.state != .notRunning else { return }
        let evidence = terminateFlowTabUITestApplication(
            app,
            targetDescription: "tab-switch-stress-measurement"
        )
        XCTAssertTrue(
            evidence.isSatisfied,
            "Tab-switch stress cleanup did not reach "
                + "the exact not-running state. "
                + evidence.diagnosticSummary
        )
    }

    func testTabSwitchStressEvidencePolicyCompatibility() {
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.measurementIterations,
            3
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.workloadDurationSeconds,
            2
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.switchCadenceMilliseconds,
            16
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.workloadDurationArgument,
            "2"
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.switchCadenceArgument,
            "16"
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.workloadDurationNanoseconds,
            2_000_000_000
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.switchCadenceNanoseconds,
            16_000_000
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.requiredSwitches,
            125
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.applicationReadinessWatchdog,
            5
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.completionEvidenceWatchdog,
            10
        )
        XCTAssertEqual(
            TabSwitchStressUITestPolicy.naturalTerminationWatchdog,
            10
        )
    }
}
