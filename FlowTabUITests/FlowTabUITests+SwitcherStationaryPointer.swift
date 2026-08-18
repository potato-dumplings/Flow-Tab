import Foundation
import XCTest

extension FlowTabUITests {
    func testOptionTabSwitcherStationaryPointerOverAppTileDoesNotSelectOnPresentation() throws {
        let placementApp = makeApp(
            additionalArguments: optionTabPointerHoverArguments
        )
        launchFlowTabUITestApplication(placementApp)
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                placementApp,
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .applicationReadinessWatchdog
            )
        )

        let placementSummary = element(
            in: placementApp,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(
            openGlobalSwitcherForPointerHover(
                placementSummary,
                traceLabel: "pointer.app.stationary-placement"
            )
        )
        let placementMailTile = element(
            in: placementApp,
            identifier: Identifier.switcherAppMockMail
        )
        XCTAssertTrue(
            placementMailTile.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .elementReadbackWatchdog
            )
        )
        let stationaryPoint = CGPoint(
            x: placementMailTile.frame.midX,
            y: placementMailTile.frame.midY
        )
        placementMailTile.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).hover()
        terminateStationaryPointerPlacementApplication(placementApp)

        let gateObservation =
            preparePointerSelectionGateObservation(
                targetKind: "application",
                targetID: "com.flowtab.mock.mail",
                preservedSelection:
                    "com.flowtab.mock.browser"
            )
        defer { gateObservation.cancel() }
        let app = makeApp(
            additionalArguments: optionTabPointerHoverArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .applicationReadinessWatchdog
            )
        )

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let mailTile = element(
            in: app,
            identifier: Identifier.switcherAppMockMail
        )
        XCTAssertTrue(
            openGlobalSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel: "pointer.app.stationary-validation"
            )
        )
        XCTAssertTrue(
            mailTile.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .elementReadbackWatchdog
            )
        )
        assertStationaryPointerFrame(
            mailTile.frame,
            contains: stationaryPoint
        )
        assertPointerSelectionGateBlocked(
            gateObservation,
            diagnosticsSummary: diagnosticsSummary,
            selectionKey: "selected",
            expectedSelection: "com.flowtab.mock.browser"
        )
    }

    func testControlTabSwitcherStationaryPointerOverWindowCardDoesNotSelectOnPresentation() throws {
        let placementApp = makeApp(
            additionalArguments: controlTabPointerHoverArguments
        )
        launchFlowTabUITestApplication(placementApp)
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                placementApp,
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .applicationReadinessWatchdog
            )
        )

        let placementSummary = element(
            in: placementApp,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(
            openInAppSwitcherForPointerHover(
                placementSummary,
                traceLabel:
                    "pointer.window.stationary-placement"
            )
        )
        let secondaryWindowID =
            "flowtab.switcher.window."
            + "mock-current-secondary"
                .flowTabUITestAccessibilityIdentifierComponent
        let placementSecondaryWindow = element(
            in: placementApp,
            identifier: secondaryWindowID
        )
        XCTAssertTrue(
            placementSecondaryWindow.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .elementReadbackWatchdog
            )
        )
        let stationaryPoint = CGPoint(
            x: placementSecondaryWindow.frame.midX,
            y: placementSecondaryWindow.frame.midY
        )
        placementSecondaryWindow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).hover()
        terminateStationaryPointerPlacementApplication(
            placementApp
        )

        let gateObservation =
            preparePointerSelectionGateObservation(
                targetKind: "window",
                targetID: "mock-current-secondary",
                targetAppID:
                    FlowTabUITestAppIdentity.configured()
                        .bundleIdentifier,
                preservedSelection: "mock-current-primary"
            )
        defer { gateObservation.cancel() }
        let app = makeApp(
            additionalArguments: controlTabPointerHoverArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .applicationReadinessWatchdog
            )
        )

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(
            openInAppSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel:
                    "pointer.window.stationary-validation"
            )
        )
        let secondaryWindow = element(
            in: app,
            identifier: secondaryWindowID
        )
        XCTAssertTrue(
            secondaryWindow.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .elementReadbackWatchdog
            )
        )
        assertStationaryPointerFrame(
            secondaryWindow.frame,
            contains: stationaryPoint
        )
        assertPointerSelectionGateBlocked(
            gateObservation,
            diagnosticsSummary: diagnosticsSummary,
            selectionKey: "selectedWindow",
            expectedSelection: "mock-current-primary"
        )
    }

    func testSearchPanelStationaryPointerOverResultDoesNotSelectOnPresentation() throws {
        let browserResultID =
            "flowtab.switcher.search.app."
            + "com.flowtab.mock.browser"
                .flowTabUITestAccessibilityIdentifierComponent
        let app = makeApp(
            additionalArguments:
                searchPointerHoverTriggerArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .applicationReadinessWatchdog
            )
        )

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(
            openSearchSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel: "pointer.search.prime"
            )
        )

        let primingBrowserResult = app.descendants(
            matching: .any
        )
        .matching(identifier: browserResultID)
        .firstMatch
        XCTAssertTrue(
            primingBrowserResult.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .elementReadbackWatchdog
            )
        )
        dismissStationaryPointerSearch(
            in: app,
            diagnosticsSummary: diagnosticsSummary
        )
        XCTAssertTrue(
            openSearchSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel: "pointer.search.placement"
            )
        )

        let placementBrowserResult = app.descendants(
            matching: .any
        )
        .matching(identifier: browserResultID)
        .firstMatch
        XCTAssertTrue(
            placementBrowserResult.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .elementReadbackWatchdog
            )
        )
        assertSearchResultUsesRowSizedFrame(
            placementBrowserResult
        )
        let stationaryPoint = CGPoint(
            x: placementBrowserResult.frame.midX,
            y: placementBrowserResult.frame.midY
        )
        dismissStationaryPointerSearch(
            in: app,
            diagnosticsSummary: diagnosticsSummary
        )
        let homeContent = element(
            in: app,
            identifier: Identifier.homeTabContent
        )
        XCTAssertTrue(
            homeContent.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .panelDismissalWatchdog
            )
        )
        hoverStationaryPointerScreenPoint(
            stationaryPoint,
            relativeTo: homeContent
        )

        let gateObservation =
            preparePointerSelectionGateObservation(
                targetKind: "searchResult",
                targetID:
                    "app:com.flowtab.mock.browser",
                preservedSelection:
                    "app:com.flowtab.mock.mail"
            )
        defer { gateObservation.cancel() }
        XCTAssertTrue(
            openSearchSwitcherForPointerHover(
                diagnosticsSummary,
                traceLabel:
                    "pointer.search.stationary-validation"
            )
        )

        let browserResult = app.descendants(matching: .any)
            .matching(identifier: browserResultID)
            .firstMatch
        XCTAssertTrue(
            diagnosticsSummary.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .elementReadbackWatchdog
            )
        )
        XCTAssertTrue(
            browserResult.waitForExistence(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .elementReadbackWatchdog
            )
        )
        assertSearchResultUsesRowSizedFrame(browserResult)
        assertStationaryPointerFrame(
            browserResult.frame,
            contains: stationaryPoint
        )
        assertPointerSelectionGateBlocked(
            gateObservation,
            diagnosticsSummary: diagnosticsSummary,
            selectionKey: "searchSelectedResult",
            expectedSelection:
                "app%3Acom.flowtab.mock.mail"
        )
    }

}
