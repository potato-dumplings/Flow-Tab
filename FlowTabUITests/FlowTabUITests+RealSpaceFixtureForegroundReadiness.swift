import XCTest

enum FlowTabUITestRealSpaceFixtureReadinessPolicy {
    static let postFixtureActivationWatchdog: TimeInterval = 5
}

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

    static func resolve(
        targetDescription: String,
        waiterCompleted: Bool,
        finalStateReadback: () -> XCUIApplication.State
    ) -> Self {
        Self(
            targetDescription: targetDescription,
            waiterCompleted: waiterCompleted,
            finalState:
                waiterCompleted
                    ? .runningForeground
                    : finalStateReadback()
        )
    }
}

extension FlowTabUITests {
    @discardableResult
    func assertRealSpaceFixtureFlowTabIsForegroundReady(
        _ app: XCUIApplication,
        traceLabel: String?,
        targetDescription: String,
        watchdog: TimeInterval =
            FlowTabUITestSupportWatchdogPolicy
                .foregroundActivation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestRealSpaceFixtureReadinessEvidence {
        let waiterCompleted =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout: watchdog,
                traceLabel: traceLabel
            )
        let evidence =
            FlowTabUITestRealSpaceFixtureReadinessEvidence.resolve(
                targetDescription: targetDescription,
                waiterCompleted: waiterCompleted,
                finalStateReadback: { app.state }
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

    @discardableResult
    func assertRealSpaceFixtureFlowTabIsForegroundReadyAfterFixtureLaunch(
        _ app: XCUIApplication,
        targetDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestRealSpaceFixtureReadinessEvidence {
        assertRealSpaceFixtureFlowTabIsForegroundReady(
            app,
            traceLabel: nil,
            targetDescription: targetDescription,
            watchdog:
                FlowTabUITestRealSpaceFixtureReadinessPolicy
                    .postFixtureActivationWatchdog,
            file: file,
            line: line
        )
    }

    func testRealSpaceFixturePostFixtureActivationUsesCompatiblePolicy() {
        XCTAssertEqual(
            FlowTabUITestRealSpaceFixtureReadinessPolicy
                .postFixtureActivationWatchdog,
            5
        )
        XCTAssertTrue(
            FlowTabUITestRealSpaceFixtureReadinessPolicy
                .postFixtureActivationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestRealSpaceFixtureReadinessPolicy
                .postFixtureActivationWatchdog,
            0
        )
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

        var finalStateReadbackCount = 0
        let waiterEvidence =
            FlowTabUITestRealSpaceFixtureReadinessEvidence.resolve(
                targetDescription: "waiter",
                waiterCompleted: true,
                finalStateReadback: {
                    finalStateReadbackCount += 1
                    return .runningBackground
                }
            )
        XCTAssertTrue(waiterEvidence.isSatisfied)
        XCTAssertEqual(waiterEvidence.finalState, .runningForeground)
        XCTAssertEqual(finalStateReadbackCount, 0)

        let boundaryEvidence =
            FlowTabUITestRealSpaceFixtureReadinessEvidence.resolve(
                targetDescription: "boundary-readback",
                waiterCompleted: false,
                finalStateReadback: {
                    finalStateReadbackCount += 1
                    return .runningForeground
                }
            )
        XCTAssertTrue(boundaryEvidence.isSatisfied)
        XCTAssertEqual(boundaryEvidence.finalState, .runningForeground)
        XCTAssertEqual(finalStateReadbackCount, 1)

        let missing =
            FlowTabUITestRealSpaceFixtureReadinessEvidence.resolve(
                targetDescription: "prelaunch-before-fixture",
                waiterCompleted: false,
                finalStateReadback: {
                    finalStateReadbackCount += 1
                    return .runningBackground
                }
            )
        XCTAssertFalse(missing.isSatisfied)
        XCTAssertEqual(finalStateReadbackCount, 2)
        XCTAssertTrue(
            missing.diagnosticSummary.contains(
                "target=prelaunch-before-fixture "
                    + "unmetCondition=runningForeground "
                    + "waiterCompleted=0 finalState="
            )
        )
    }

    func testRealSpaceFixtureOpenWindowMutationReadinessReportsFinalState() {
        var finalStateReadbackCount = 0
        let evidence =
            FlowTabUITestRealSpaceFixtureReadinessEvidence.resolve(
                targetDescription:
                    "open-window-mutation-before-app-projection",
                waiterCompleted: false,
                finalStateReadback: {
                    finalStateReadbackCount += 1
                    return .runningBackground
                }
            )

        XCTAssertFalse(evidence.isSatisfied)
        XCTAssertEqual(finalStateReadbackCount, 1)
        XCTAssertTrue(
            evidence.diagnosticSummary.contains(
                "target=open-window-mutation-before-app-projection "
                    + "unmetCondition=runningForeground "
                    + "waiterCompleted=0 finalState="
            )
        )
    }
}
