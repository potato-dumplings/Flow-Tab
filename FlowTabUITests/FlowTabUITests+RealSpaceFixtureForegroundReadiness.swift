import XCTest

struct FlowTabUITestRealSpaceFixtureReadinessEvidence: Equatable {
    let targetDescription: String
    let waiterCompleted: Bool
    let finalState: XCUIApplication.State

    var isSatisfied: Bool {
        waiterCompleted || finalState == .runningForeground
    }

    var diagnosticSummary: String {
        "target=\(targetDescription) "
            + "unmetCondition=runningForeground "
            + "waiterCompleted=\(waiterCompleted ? 1 : 0) "
            + "finalState=\(String(describing: finalState))"
    }
}

extension FlowTabUITests {
    @discardableResult
    func assertRealSpaceFixtureFlowTabIsForegroundReady(
        _ app: XCUIApplication,
        traceLabel: String?,
        targetDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestRealSpaceFixtureReadinessEvidence {
        let waiterCompleted =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .foregroundActivation,
                traceLabel: traceLabel
            )
        let evidence =
            FlowTabUITestRealSpaceFixtureReadinessEvidence(
                targetDescription: targetDescription,
                waiterCompleted: waiterCompleted,
                finalState: app.state
            )
        XCTAssertTrue(
            evidence.isSatisfied,
            "Real Space Fixture FlowTab readiness watchdog expired. "
                + evidence.diagnosticSummary,
            file: file,
            line: line
        )
        return evidence
    }

    func testRealSpaceFixtureForegroundReadinessUsesSharedPolicyAndFinalReadback() {
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.foregroundActivation,
            12
        )
        XCTAssertTrue(
            FlowTabUITestSupportWatchdogPolicy
                .foregroundActivation.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSupportWatchdogPolicy.foregroundActivation,
            0
        )

        XCTAssertTrue(
            FlowTabUITestRealSpaceFixtureReadinessEvidence(
                targetDescription: "waiter",
                waiterCompleted: true,
                finalState: .runningBackground
            ).isSatisfied
        )
        XCTAssertTrue(
            FlowTabUITestRealSpaceFixtureReadinessEvidence(
                targetDescription: "boundary-readback",
                waiterCompleted: false,
                finalState: .runningForeground
            ).isSatisfied
        )

        let missing =
            FlowTabUITestRealSpaceFixtureReadinessEvidence(
                targetDescription: "prelaunch-before-fixture",
                waiterCompleted: false,
                finalState: .runningBackground
            )
        XCTAssertFalse(missing.isSatisfied)
        XCTAssertTrue(
            missing.diagnosticSummary.contains(
                "target=prelaunch-before-fixture "
                    + "unmetCondition=runningForeground "
                    + "waiterCompleted=0 finalState="
            )
        )
    }
}
