import Foundation
import XCTest

enum FlowTabUITestHomeAndLogsWatchdogPolicy {
    static let applicationForegroundReadiness: TimeInterval = 8
    static let frontmostApplicationActivation: TimeInterval = 5
    static let homeTabTriggerReadiness: TimeInterval = 5
    static let homeTabProjectionReadiness: TimeInterval = 5
    static let liveApplicationDirectoryReadiness: TimeInterval = 2
    static let overviewChromeProjectionReadiness: TimeInterval = 8
    static let hiddenAppRowProjectionReadiness: TimeInterval = 8
}

enum FlowTabUITestHomeOverviewProjectionPolicy {
    static let identifiers = [
        FlowTabUITests.Identifier.homeHeader,
        FlowTabUITests.Identifier.homeAppCount,
        FlowTabUITests.Identifier.homeWindowCount,
        FlowTabUITests.Identifier.homeStatsTotalApps,
        FlowTabUITests.Identifier.homeStatsVisibleApps,
        FlowTabUITests.Identifier.homeStatsHiddenApps,
        FlowTabUITests.Identifier.homeStatsTotalWindows,
        FlowTabUITests.Identifier.sidebarPermissionAccessibility,
        FlowTabUITests.Identifier.sidebarPermissionScreenCapture
    ]
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
    func assertHomeAndLogsOverviewChromeAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let identifiers =
            FlowTabUITestHomeOverviewProjectionPolicy.identifiers
        let elements = waitForExactElementCollection(
            in: app,
            identifiers: identifiers,
            watchdog:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .overviewChromeProjectionReadiness,
            targetDescription:
                "Home Overview chrome target=\(targetDescription)",
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
        return elements != nil
    }

    @discardableResult
    func assertHomeAndLogsLiveApplicationDirectoryAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let identifierPrefix = "flowtab.home.app."
        let firstLiveAppRow = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                identifierPrefix
            )
        ).firstMatch
        let observation =
            FlowTabUITestElementExistenceObservationOwner(
                elementIdentifier: "\(identifierPrefix)*",
                readback: { firstLiveAppRow.exists }
            )
        observation.start()
        defer { observation.cancel() }

        let didNavigate =
            assertHomeAndLogsHomeTabProjectionAfterNavigation(
                in: app,
                targetDescription: targetDescription,
                file: file,
                line: line
            )
        observation.markTriggerCompleted()
        guard didNavigate else { return false }

        guard observation.waitForResolution(
            timeout:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .liveApplicationDirectoryReadiness
        ) != nil else {
            XCTFail(
                "Home live application directory watchdog expired. "
                    + "target=\(targetDescription) "
                    + "identifierPrefix=\(identifierPrefix) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        return true
    }

    @discardableResult
    func assertHomeAndLogsHomeTabProjectionAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let didProject = assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .home,
            triggerWatchdog:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .homeTabTriggerReadiness,
            projectionWatchdog:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .homeTabProjectionReadiness
        )
        XCTAssertTrue(
            didProject,
            "Home/Logs Home-tab projection watchdog expired. "
                + "target=\(targetDescription)",
            file: file,
            line: line
        )
        return didProject
    }

    @discardableResult
    func assertHomeAndLogsHomeTabTriggerReady(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let query = app.buttons.matching(
            identifier: Identifier.homeTabButton
        )
        let didTap = tapFirstHittable(
            in: query,
            timeout:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .homeTabTriggerReadiness
        )
        XCTAssertTrue(
            didTap,
            "Home/Logs Home-tab trigger watchdog expired. "
                + "target=\(targetDescription) "
                + "identifier=\(Identifier.homeTabButton) "
                + "finalCandidateCount=\(query.count)",
            file: file,
            line: line
        )
        return didTap
    }

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
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .frontmostApplicationActivation,
            5
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .frontmostApplicationActivation.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .frontmostApplicationActivation,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabTriggerReadiness,
            5
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabTriggerReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabTriggerReadiness,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabProjectionReadiness,
            5
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabProjectionReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabProjectionReadiness,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .liveApplicationDirectoryReadiness,
            2
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .liveApplicationDirectoryReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .liveApplicationDirectoryReadiness,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .overviewChromeProjectionReadiness,
            8
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .overviewChromeProjectionReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .overviewChromeProjectionReadiness,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .hiddenAppRowProjectionReadiness,
            8
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .hiddenAppRowProjectionReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .hiddenAppRowProjectionReadiness,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeHiddenAppRowProjectionPolicy.rows,
            [
                .init(
                    identifier: Identifier.homeAppMockBrowser,
                    value: nil
                ),
                .init(
                    identifier: Identifier.homeAppMockMail,
                    value: nil
                )
            ]
        )
        XCTAssertTrue(
            FlowTabUITestHomeHiddenAppRowProjectionPolicy
                .isHiddenAccessibilityValue("0w hidden")
        )
        XCTAssertTrue(
            FlowTabUITestHomeHiddenAppRowProjectionPolicy
                .isHiddenAccessibilityValue("2w hidden")
        )
        XCTAssertFalse(
            FlowTabUITestHomeHiddenAppRowProjectionPolicy
                .isHiddenAccessibilityValue(nil)
        )
        XCTAssertFalse(
            FlowTabUITestHomeHiddenAppRowProjectionPolicy
                .isHiddenAccessibilityValue("-1w hidden")
        )
        XCTAssertFalse(
            FlowTabUITestHomeHiddenAppRowProjectionPolicy
                .isHiddenAccessibilityValue("2w")
        )
        XCTAssertFalse(
            FlowTabUITestHomeHiddenAppRowProjectionPolicy
                .isHiddenAccessibilityValue("2w hidden extra")
        )
        XCTAssertEqual(
            FlowTabUITestHomeOverviewProjectionPolicy.identifiers,
            [
                Identifier.homeHeader,
                Identifier.homeAppCount,
                Identifier.homeWindowCount,
                Identifier.homeStatsTotalApps,
                Identifier.homeStatsVisibleApps,
                Identifier.homeStatsHiddenApps,
                Identifier.homeStatsTotalWindows,
                Identifier.sidebarPermissionAccessibility,
                Identifier.sidebarPermissionScreenCapture
            ]
        )
        XCTAssertEqual(
            Set(FlowTabUITestHomeOverviewProjectionPolicy.identifiers)
                .count,
            FlowTabUITestHomeOverviewProjectionPolicy.identifiers.count
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
