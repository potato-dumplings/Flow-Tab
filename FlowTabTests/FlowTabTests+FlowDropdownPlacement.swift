import AppKit
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testFlowDropdownPlacementResolverKeepsDefaultBelowAndUsesSideOnlyWhenFullyVisible() {
        let metrics = settingsDropdownMetricsForTesting()
        let contentFrame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        let sideContentFrame = NSRect(x: 0, y: 0, width: 1000, height: 620)
        let screenFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let sideVisibleRows = 17
        let sideHeight = metrics.menuVerticalPadding * 2 + CGFloat(sideVisibleRows) * metrics.menuRowHeight

        let defaultLayout = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 160,
            controlFrame: NSRect(x: 700, y: 90, width: 160, height: 32),
            contentFrame: contentFrame,
            screenVisibleFrame: screenFrame,
            preference: .defaultBelow
        )
        XCTAssertEqual(defaultLayout.direction, .below)
        XCTAssertEqual(defaultLayout.frame.maxY, 90, accuracy: 0.001)
        XCTAssertLessThanOrEqual(defaultLayout.frame.height, 90)

        let rightLayout = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 160,
            controlFrame: NSRect(x: 620, y: 294, width: 160, height: 32),
            contentFrame: sideContentFrame,
            screenVisibleFrame: screenFrame,
            preference: .preferRight
        )
        XCTAssertEqual(rightLayout.direction, .right)
        XCTAssertEqual(rightLayout.frame.minX, 780, accuracy: 0.001)
        XCTAssertEqual(rightLayout.frame.midY, 310, accuracy: 0.001)
        XCTAssertEqual(rightLayout.frame.height, sideHeight, accuracy: 0.001)
        XCTAssertEqual(rightLayout.contentSize.width, 170, accuracy: 0.001)
        XCTAssertGreaterThan(rightLayout.visibleRowCount, metrics.maximumVisibleRows)

        let leftLayout = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 160,
            controlFrame: NSRect(x: 220, y: 294, width: 160, height: 32),
            contentFrame: sideContentFrame,
            screenVisibleFrame: screenFrame,
            preference: .preferLeft
        )
        XCTAssertEqual(leftLayout.direction, .left)
        XCTAssertEqual(leftLayout.frame.maxX, 220, accuracy: 0.001)
        XCTAssertEqual(leftLayout.frame.midY, 310, accuracy: 0.001)
        XCTAssertEqual(leftLayout.frame.height, sideHeight, accuracy: 0.001)
    }

    func testFlowDropdownPlacementResolverFallsBackVerticallyByAvailableRows() {
        let metrics = settingsDropdownMetricsForTesting()
        let screenFrame = NSRect(x: 0, y: 0, width: 900, height: 800)
        let preferredHeight = metrics.menuArrowHeight
            + metrics.menuVerticalPadding * 2
            + CGFloat(metrics.maximumVisibleRows) * metrics.menuRowHeight

        let belowFull = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 160,
            controlFrame: NSRect(x: 800, y: 450, width: 160, height: 32),
            contentFrame: NSRect(x: 0, y: 0, width: 1000, height: 600),
            screenVisibleFrame: screenFrame,
            preference: .preferRight
        )
        XCTAssertEqual(belowFull.direction, .below)
        XCTAssertEqual(belowFull.frame.height, preferredHeight, accuracy: 0.001)

        let aboveFull = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 160,
            controlFrame: NSRect(x: 800, y: 80, width: 160, height: 32),
            contentFrame: NSRect(x: 0, y: 0, width: 1000, height: 600),
            screenVisibleFrame: screenFrame,
            preference: .preferRight
        )
        XCTAssertEqual(aboveFull.direction, .above)
        XCTAssertEqual(aboveFull.frame.height, preferredHeight, accuracy: 0.001)

        let belowMinimumRows = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 160,
            controlFrame: NSRect(x: 800, y: 120, width: 160, height: 32),
            contentFrame: NSRect(x: 0, y: 0, width: 1000, height: 230),
            screenVisibleFrame: screenFrame,
            preference: .preferRight
        )
        XCTAssertEqual(belowMinimumRows.direction, .below)
        XCTAssertEqual(belowMinimumRows.visibleRowCount, 2)
        XCTAssertLessThan(belowMinimumRows.frame.height, preferredHeight)

        let aboveMinimumRows = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 160,
            controlFrame: NSRect(x: 800, y: 80, width: 160, height: 32),
            contentFrame: NSRect(x: 0, y: 0, width: 1000, height: 232),
            screenVisibleFrame: screenFrame,
            preference: .preferRight
        )
        XCTAssertEqual(aboveMinimumRows.direction, .above)
        XCTAssertEqual(aboveMinimumRows.visibleRowCount, 2)
        XCTAssertLessThan(aboveMinimumRows.frame.height, preferredHeight)

        let preferAbove = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 160,
            controlFrame: NSRect(x: 200, y: 420, width: 160, height: 32),
            contentFrame: NSRect(x: 0, y: 0, width: 1000, height: 572),
            screenVisibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            preference: .preferAbove
        )
        XCTAssertEqual(preferAbove.direction, .above)
        XCTAssertEqual(preferAbove.visibleRowCount, 2)
    }

    @MainActor
    func testFlowDropdownMenuBodyAndScrollAreaExcludeArrowForAllDirections() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let presentation = FlowDropdownPresentation.form(targetAppearance: appearance)
        let metrics = presentation.metrics
        let options = (0..<12).map { FlowDropdownOption(id: "\($0)", title: "Option \($0)") }
        let visibleRows = 4
        let viewportHeight = metrics.menuVerticalPadding * 2
            + CGFloat(visibleRows) * metrics.menuRowHeight
        let cases: [(FlowDropdownMenuDirection, body: NSRect, scrollFrame: NSRect)] = [
            (
                .below,
                NSRect(x: 0, y: 0, width: 200, height: viewportHeight),
                NSRect(x: 0, y: 0, width: 200, height: viewportHeight)
            ),
            (
                .above,
                NSRect(x: 0, y: 10, width: 200, height: viewportHeight),
                NSRect(x: 0, y: 10, width: 200, height: viewportHeight)
            ),
            (
                .right,
                NSRect(x: 10, y: 0, width: 190, height: viewportHeight),
                NSRect(x: 10, y: 0, width: 190, height: viewportHeight)
            ),
            (
                .left,
                NSRect(x: 0, y: 0, width: 190, height: viewportHeight),
                NSRect(x: 0, y: 0, width: 190, height: viewportHeight)
            )
        ]

        for (direction, expectedBody, expectedScrollFrame) in cases {
            let menuView = FlowDropdownMenuView(
                options: options,
                selectedID: "0",
                controlIdentifier: "flowtab.test.dropdown",
                presentation: presentation,
                direction: direction,
                visibleRowCount: visibleRows,
                arrowAnchor: 100
            )
            let height = direction == .below || direction == .above
                ? viewportHeight + presentation.metrics.menuArrowHeight
                : viewportHeight
            menuView.frame = NSRect(x: 0, y: 0, width: 200, height: height)
            menuView.layoutSubtreeIfNeeded()

            XCTAssertEqual(menuView.directionForTesting, direction)
            XCTAssertEqual(menuView.menuBodyRectForTesting.minX, expectedBody.minX, accuracy: 0.001)
            XCTAssertEqual(menuView.menuBodyRectForTesting.minY, expectedBody.minY, accuracy: 0.001)
            XCTAssertEqual(menuView.menuBodyRectForTesting.width, expectedBody.width, accuracy: 0.001)
            XCTAssertEqual(menuView.menuBodyRectForTesting.height, expectedBody.height, accuracy: 0.001)
            XCTAssertTrue(menuView.usesScrollViewForTesting)
            XCTAssertEqual(menuView.scrollViewFrameForTesting.minX, expectedScrollFrame.minX, accuracy: 0.001)
            XCTAssertEqual(menuView.scrollViewFrameForTesting.minY, expectedScrollFrame.minY, accuracy: 0.001)
            XCTAssertEqual(menuView.scrollViewFrameForTesting.width, expectedScrollFrame.width, accuracy: 0.001)
            XCTAssertEqual(menuView.scrollViewFrameForTesting.height, expectedScrollFrame.height, accuracy: 0.001)
            XCTAssertEqual(menuView.scrollViewFrameForTesting.maxY, expectedBody.maxY, accuracy: 0.001)

            for row in menuView.rowsForTesting {
                let rowFrameInMenu = row.convert(row.bounds, to: menuView)
                XCTAssertGreaterThanOrEqual(rowFrameInMenu.minX, expectedBody.minX)
                XCTAssertLessThanOrEqual(rowFrameInMenu.maxX, expectedBody.maxX)
            }
        }
    }

    @MainActor
    func testFlowDropdownSidePlacementShrinksToCompleteRowsAndCentersInContentWhenTriggerIsOffCenter() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let presentation = FlowDropdownPresentation.form(targetAppearance: appearance)
        let metrics = presentation.metrics
        let visibleRows = 17
        let contentFrame = NSRect(x: 0, y: 0, width: 1000, height: 620)
        let controlFrame = NSRect(x: 240, y: 214, width: 160, height: 32)
        let layout = FlowDropdownMenuLayoutResolver.resolve(
            optionCount: 30,
            metrics: metrics,
            menuBodyWidth: 210,
            controlFrame: controlFrame,
            contentFrame: contentFrame,
            screenVisibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 900),
            preference: .preferRight
        )
        let expectedHeight = metrics.menuVerticalPadding * 2
            + CGFloat(visibleRows) * metrics.menuRowHeight
        XCTAssertEqual(layout.direction, .right)
        XCTAssertEqual(layout.visibleRowCount, visibleRows)
        XCTAssertEqual(layout.frame.height, expectedHeight, accuracy: 0.001)
        XCTAssertEqual(layout.frame.midY, contentFrame.midY, accuracy: 0.001)
        XCTAssertEqual(layout.frame.minY - contentFrame.minY, contentFrame.maxY - layout.frame.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.arrowAnchor, controlFrame.midY - layout.frame.minY, accuracy: 0.001)
        XCTAssertEqual(layout.contentSize.height, expectedHeight, accuracy: 0.001)

        let options = (0..<30).map { FlowDropdownOption(id: "\($0)", title: "Option \($0)") }
        let menuView = FlowDropdownMenuView(
            options: options,
            selectedID: "0",
            controlIdentifier: "flowtab.test.dropdown",
            presentation: presentation,
            direction: layout.direction,
            visibleRowCount: layout.visibleRowCount,
            arrowAnchor: layout.arrowAnchor
        )
        menuView.frame = NSRect(origin: .zero, size: layout.contentSize)
        menuView.layoutSubtreeIfNeeded()

        let expectedBody = NSRect(x: metrics.menuArrowHeight, y: 0, width: 210, height: expectedHeight)
        XCTAssertEqual(menuView.menuBodyRectForTesting, expectedBody)
        XCTAssertEqual(menuView.scrollViewFrameForTesting, expectedBody)
        XCTAssertEqual(
            (menuView.scrollViewFrameForTesting.height - metrics.menuVerticalPadding * 2) / metrics.menuRowHeight,
            CGFloat(visibleRows),
            accuracy: 0.001
        )
    }

    @MainActor
    func testHotkeyControlsUseRecordersAndOtherSelectsKeepDefaultPlacement() throws {
        let view = HotkeySettingsCardAppKitView()
        view.frame = NSRect(x: 0, y: 0, width: 860, height: 520)
        view.layoutSubtreeIfNeeded()

        for identifier in [
            "flowtab.settings.hotkey.main-modifiers",
            "flowtab.settings.hotkey.main-reverse-modifiers",
            "flowtab.settings.hotkey.main-key",
            "flowtab.settings.hotkey.quit-key",
            "flowtab.settings.hotkey.in-app-shortcut",
            "flowtab.settings.hotkey.in-app-reverse-modifiers"
        ] {
            let recorder = try XCTUnwrap(descendant(
                in: view,
                identifier: identifier,
                as: FlowSettingsShortcutRecorderControl.self
            ))
            XCTAssertFalse(recorder.subviews.contains { $0 is FlowDropdownControl })
        }

        let defaultSelect = FlowSettingsSelectControl(frame: .zero)
        defaultSelect.configure(options: [(id: "tab", title: "Tab")])
        XCTAssertEqual(defaultSelect.placementPreferenceForTesting, .defaultBelow)
    }

    private func settingsDropdownMetricsForTesting() -> FlowDropdownMetrics {
        FlowDropdownPresentation.form(
            targetAppearance: NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
        ).metrics
    }

    private func descendant<T: NSView>(
        in view: NSView,
        identifier: String,
        as type: T.Type = T.self
    ) -> T? {
        if view.identifier?.rawValue == identifier || view.accessibilityIdentifier() == identifier {
            return view as? T
        }
        for subview in view.subviews {
            if let match: T = descendant(in: subview, identifier: identifier, as: type) {
                return match
            }
        }
        return nil
    }
}
