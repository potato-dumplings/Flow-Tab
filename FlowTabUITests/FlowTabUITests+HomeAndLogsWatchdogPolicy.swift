import Foundation
import XCTest

enum FlowTabUITestHomeAndLogsWatchdogPolicy {
    static let applicationForegroundReadiness: TimeInterval = 8
}

struct FlowTabUITestHomeAndLogsReadinessEvidence: Equatable {
    let targetDescription: String
    let waitCompleted: Bool
    let finalState: XCUIApplication.State

    var isSatisfied: Bool {
        waitCompleted || finalState == .runningForeground
    }

    var diagnosticSummary: String {
        "target=\(targetDescription) "
            + "unmetCondition=runningForeground "
            + "waitCompleted=\(waitCompleted ? 1 : 0) "
            + "finalState=\(String(describing: finalState))"
    }
}

extension FlowTabUITests {
    @discardableResult
    func assertHomeAndLogsApplicationIsForegroundReady(
        _ app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestHomeAndLogsReadinessEvidence {
        let waitCompleted =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestHomeAndLogsWatchdogPolicy
                        .applicationForegroundReadiness,
                traceLabel: targetDescription
            )
        let evidence = FlowTabUITestHomeAndLogsReadinessEvidence(
            targetDescription: targetDescription,
            waitCompleted: waitCompleted,
            finalState: app.state
        )
        XCTAssertTrue(
            evidence.isSatisfied,
            "Home/Logs application readiness watchdog expired. "
                + evidence.diagnosticSummary,
            file: file,
            line: line
        )
        return evidence
    }

    func testHomeAndLogsWatchdogPolicyAndReadinessEvidence() {
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .applicationForegroundReadiness,
            8
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .applicationForegroundReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .applicationForegroundReadiness,
            0
        )

        XCTAssertTrue(
            FlowTabUITestHomeAndLogsReadinessEvidence(
                targetDescription: "delivered",
                waitCompleted: true,
                finalState: .runningBackground
            ).isSatisfied
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsReadinessEvidence(
                targetDescription: "boundary-readback",
                waitCompleted: false,
                finalState: .runningForeground
            ).isSatisfied
        )

        let missing = FlowTabUITestHomeAndLogsReadinessEvidence(
            targetDescription: "missing",
            waitCompleted: false,
            finalState: .runningBackground
        )
        XCTAssertFalse(missing.isSatisfied)
        XCTAssertTrue(
            missing.diagnosticSummary.contains(
                "target=missing unmetCondition=runningForeground "
                    + "waitCompleted=0 finalState="
            )
        )
    }
}
