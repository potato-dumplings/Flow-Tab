import Foundation
import XCTest

private enum FlowTabUpdateUITestWatchdogPolicy {
    static let presentation: TimeInterval = 8
    static let actionReceipt: TimeInterval = 5
    static let hoverTransition: TimeInterval = 2
}

private enum FlowTabUpdateUITestPresentationOracle {
    static let collapsedButtonWidth: CGFloat = 20
    static let expandedButtonWidth: CGFloat = 44
}

private struct FlowTabUpdateUITestRoute {
    let displayVersion = "0.1.0-alpha.06"
    let buildVersion = "6"
    let notificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab.update-action."
            + UUID().uuidString
    )
    let readbackURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "flowtab-update-action-\(UUID().uuidString).json",
            isDirectory: false
        )

    var launchArguments: [String] {
        [
            "--flowtab-ui-update-available",
            displayVersion,
            buildVersion,
            "--flowtab-ui-update-action-route",
            notificationName.rawValue,
            readbackURL.path
        ]
    }
}

private struct FlowTabUpdateUITestActionEvidence: Decodable {
    let displayVersion: String
    let buildVersion: String
    let requestGeneration: UInt64
}

extension FlowTabUITests {
    func testAvailableUpdateButtonAppearsInSidebarHeaderAndRoutesOneAction()
        throws {
        let route = FlowTabUpdateUITestRoute()
        defer { try? FileManager.default.removeItem(at: route.readbackURL) }

        let app = makeApp(
            additionalArguments: updateAvailableLaunchArguments(route: route)
        )
        launchFlowTabUITestApplication(app)

        let button = app.buttons[Identifier.sidebarUpdateDownload]
        XCTAssertTrue(
            button.waitForExistence(
                timeout: FlowTabUpdateUITestWatchdogPolicy.presentation
            )
        )
        let header = element(in: app, identifier: Identifier.sidebarHeader)
        XCTAssertTrue(header.exists)
        XCTAssertEqual(button.label, "下载 \(route.displayVersion) 更新")
        XCTAssertEqual(button.frame.width, 20, accuracy: 2)
        XCTAssertEqual(button.frame.height, 20, accuracy: 2)
        XCTAssertTrue(
            header.frame.insetBy(dx: -1, dy: -1).contains(button.frame)
        )
        XCTAssertGreaterThan(button.frame.midX, header.frame.midX)

        let receipt = expectation(
            description: "Sparkle update action receipt"
        )
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(
            forName: route.notificationName,
            object: nil,
            queue: .main
        ) { _ in
            receipt.fulfill()
        }
        defer { center.removeObserver(token) }

        button.tap()
        wait(
            for: [receipt],
            timeout: FlowTabUpdateUITestWatchdogPolicy.actionReceipt
        )
        let evidence = try JSONDecoder().decode(
            FlowTabUpdateUITestActionEvidence.self,
            from: Data(contentsOf: route.readbackURL)
        )
        XCTAssertEqual(evidence.displayVersion, route.displayVersion)
        XCTAssertEqual(evidence.buildVersion, route.buildVersion)
        XCTAssertEqual(evidence.requestGeneration, 1)
    }

    func testPermissionCardKeepsFullSidebarWidthWhenUpdateIsAvailable() {
        let route = FlowTabUpdateUITestRoute()
        defer { try? FileManager.default.removeItem(at: route.readbackURL) }

        let app = makeApp(
            additionalArguments: updateAvailableLaunchArguments(route: route)
        )
        launchFlowTabUITestApplication(app)

        let card = element(
            in: app,
            identifier: Identifier.sidebarPermissionStatus
        )
        XCTAssertTrue(
            card.waitForExistence(
                timeout: FlowTabUpdateUITestWatchdogPolicy.presentation
            )
        )
        let homeTab = app.buttons[Identifier.homeTabButton]
        XCTAssertTrue(homeTab.exists)
        XCTAssertEqual(card.frame.minX, homeTab.frame.minX, accuracy: 2)
        XCTAssertEqual(card.frame.maxX, homeTab.frame.maxX, accuracy: 2)
        XCTAssertEqual(card.frame.width, homeTab.frame.width, accuracy: 2)
    }

    func testAvailableUpdateButtonRevealsTitleOnHoverAndCollapsesOnExit() {
        let route = FlowTabUpdateUITestRoute()
        defer { try? FileManager.default.removeItem(at: route.readbackURL) }

        let app = makeApp(
            additionalArguments: updateAvailableLaunchArguments(route: route)
        )
        launchFlowTabUITestApplication(app)

        let button = app.buttons[Identifier.sidebarUpdateDownload]
        XCTAssertTrue(
            button.waitForExistence(
                timeout: FlowTabUpdateUITestWatchdogPolicy.presentation
            )
        )
        let homeTab = app.buttons[Identifier.homeTabButton]
        XCTAssertTrue(homeTab.exists)

        homeTab.hover()
        XCTAssertTrue(
            waitForUpdateButton(
                button,
                width: FlowTabUpdateUITestPresentationOracle.collapsedButtonWidth,
                accessibilityValue: ""
            ),
            updateButtonDiagnosticSummary(button)
        )

        button.hover()
        XCTAssertTrue(
            waitForUpdateButton(
                button,
                width: FlowTabUpdateUITestPresentationOracle.expandedButtonWidth,
                accessibilityValue: "更新"
            ),
            updateButtonDiagnosticSummary(button)
        )

        homeTab.hover()
        XCTAssertTrue(
            waitForUpdateButton(
                button,
                width: FlowTabUpdateUITestPresentationOracle.collapsedButtonWidth,
                accessibilityValue: ""
            ),
            updateButtonDiagnosticSummary(button)
        )
    }

    func testUpdateButtonIsHiddenWhenNoUpdateIsAvailable() {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)

        let card = element(
            in: app,
            identifier: Identifier.sidebarPermissionStatus
        )
        XCTAssertTrue(
            card.waitForExistence(
                timeout: FlowTabUpdateUITestWatchdogPolicy.presentation
            )
        )
        XCTAssertFalse(
            app.buttons[Identifier.sidebarUpdateDownload].exists
        )
    }

    func testUpdateAvailabilitySurvives20MillisecondTabSwitchPressure() {
        assertUpdateAvailabilityUnderTabSwitchPressure(
            cadenceMilliseconds: 20
        )
    }

    func testUpdateAvailabilitySurvives50MillisecondTabSwitchPressure() {
        assertUpdateAvailabilityUnderTabSwitchPressure(
            cadenceMilliseconds: 50
        )
    }

    private func assertUpdateAvailabilityUnderTabSwitchPressure(
        cadenceMilliseconds: UInt64
    ) {
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        let durationSeconds: UInt64 = 2
        let durationNanoseconds = durationSeconds * 1_000_000_000
        let cadenceNanoseconds = cadenceMilliseconds * 1_000_000
        let requiredSwitches =
            (durationNanoseconds + cadenceNanoseconds - 1)
                / cadenceNanoseconds

        measure(
            metrics: [
                XCTClockMetric(),
                XCTCPUMetric(),
                XCTMemoryMetric()
            ],
            options: options
        ) {
            let updateRoute = FlowTabUpdateUITestRoute()
            let stressRoute = TabSwitchStressUITestRoute()
            let observation = TabSwitchStressUITestObservationOwner(
                route: stressRoute
            )
            observation.start()
            defer { observation.cancel() }

            let app = makeApp(
                additionalArguments: [
                    "--flowtab-ui-reset-defaults",
                    "--flowtab-ui-mock-runtime",
                    "--flowtab-tab-stress",
                    "--flowtab-tab-stress-duration",
                    String(durationSeconds),
                    "--flowtab-tab-stress-interval-ms",
                    String(cadenceMilliseconds),
                    "-showPermissionReminder",
                    "NO"
                ] + updateRoute.launchArguments
                    + stressRoute.launchArguments
            )
            defer { assertTabSwitchStressApplicationCleanup(app) }
            launchFlowTabUITestApplication(app)
            XCTAssertTrue(
                app.buttons[Identifier.sidebarUpdateDownload]
                    .waitForExistence(
                        timeout:
                            FlowTabUpdateUITestWatchdogPolicy
                                .presentation
                    )
            )

            let completed = observation.waitForCompletion(timeout: 10)
            XCTAssertNotNil(completed, observation.diagnosticSummary)
            XCTAssertEqual(completed?.ownerGeneration, 1)
            XCTAssertEqual(
                completed?.cadenceNanoseconds,
                cadenceNanoseconds
            )
            XCTAssertEqual(completed?.requiredSwitches, requiredSwitches)
            XCTAssertEqual(completed?.attempts, requiredSwitches)
            XCTAssertEqual(completed?.switches, requiredSwitches)
            XCTAssertTrue(completed?.workloadSatisfied == true)
            XCTAssertTrue(completed?.durationSatisfied == true)
            XCTAssertTrue(
                app.wait(for: .notRunning, timeout: 10),
                observation.diagnosticSummary
            )
        }
    }

    private func updateAvailableLaunchArguments(
        route: FlowTabUpdateUITestRoute
    ) -> [String] {
        [
            "-AppleLanguages",
            "(zh-Hans)",
            "-AppleInterfaceStyle",
            "Light",
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-ax-trusted",
            "NO",
            "--flowtab-ui-screen-trusted",
            "NO"
        ] + route.launchArguments
    }

    private func waitForUpdateButton(
        _ button: XCUIElement,
        width: CGFloat,
        accessibilityValue: String
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return abs(element.frame.width - width) <= 2
                && (element.value as? String ?? "") == accessibilityValue
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: button
        )
        return XCTWaiter().wait(
            for: [expectation],
            timeout: FlowTabUpdateUITestWatchdogPolicy.hoverTransition
        ) == .completed
    }

    private func updateButtonDiagnosticSummary(
        _ button: XCUIElement
    ) -> String {
        "Update button did not reach the expected hover presentation. "
            + "frame=\(button.frame) value=\(button.value ?? "nil")"
    }
}
