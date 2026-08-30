import AppKit
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testCompactActionButtonIntrinsicSizeCacheMeasuresOnlyDistinctSignatures() {
        let font = FlowTypography.appKit(.controlTextEmphasized)
        let metrics = FlowCompactActionButtonMetrics(
            height: 32,
            minimumWidth: 68,
            horizontalPadding: 14
        )
        let signature = FlowCompactActionButtonIntrinsicSizeSignature(
            title: "Open Directory",
            metrics: metrics,
            font: font
        )
        var cache = FlowCompactActionButtonIntrinsicSizeCache()
        var measurementCount = 0
        let measure: () -> NSSize = {
            measurementCount += 1
            return NSSize(width: 124, height: 32)
        }

        XCTAssertEqual(cache.size(for: signature, measure: measure).width, 124)
        XCTAssertEqual(cache.size(for: signature, measure: measure).width, 124)
        XCTAssertEqual(measurementCount, 1)

        let changedTitle = FlowCompactActionButtonIntrinsicSizeSignature(
            title: "Clear Logs",
            metrics: metrics,
            font: font
        )
        _ = cache.size(for: changedTitle, measure: measure)
        XCTAssertEqual(measurementCount, 2)

        let changedMetrics = FlowCompactActionButtonIntrinsicSizeSignature(
            title: "Clear Logs",
            metrics: FlowCompactActionButtonMetrics(
                height: 34,
                minimumWidth: 72,
                horizontalPadding: 16
            ),
            font: font
        )
        _ = cache.size(for: changedMetrics, measure: measure)
        XCTAssertEqual(measurementCount, 3)

        let changedFont = FlowCompactActionButtonIntrinsicSizeSignature(
            title: "Clear Logs",
            metrics: changedMetrics.metrics,
            font: NSFont.systemFont(ofSize: font.pointSize + 1)
        )
        _ = cache.size(for: changedFont, measure: measure)
        XCTAssertEqual(measurementCount, 4)
    }

    @MainActor
    func testCompactActionButtonUpdatesTitleAccessibilityAndWidthForLanguageTitles() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let button = FlowCompactActionButtonControl()
        button.configure(
            title: "Manage",
            accessibilityLabel: "Manage",
            presentation: .compact(targetAppearance: appearance)
        )
        let manageWidth = button.intrinsicContentSize.width

        XCTAssertEqual(button.attributedTitle.string, "Manage")
        XCTAssertEqual(button.accessibilityLabel(), "Manage")
        XCTAssertGreaterThanOrEqual(manageWidth, 68)

        button.configure(
            title: "管理",
            accessibilityLabel: "管理",
            presentation: .compact(targetAppearance: appearance)
        )

        XCTAssertEqual(button.attributedTitle.string, "管理")
        XCTAssertEqual(button.accessibilityLabel(), "管理")
        XCTAssertGreaterThanOrEqual(button.intrinsicContentSize.width, 68)

        button.configure(
            title: "Open Directory",
            accessibilityLabel: "Open Directory",
            presentation: .compact(targetAppearance: appearance)
        )

        XCTAssertGreaterThan(button.intrinsicContentSize.width, manageWidth)
    }

    @MainActor
    func testRuntimeLogsActionsUseSharedCompactActionButtons() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        var runtimeLogLevelRaw = RuntimeLogLevel.info.rawValue
        let hostedView = NSHostingView(
            rootView: RuntimeLogsSection(
                runtimeLogLevelRaw: Binding(
                    get: { runtimeLogLevelRaw },
                    set: { runtimeLogLevelRaw = $0 }
                ),
                isActive: true,
                hotkeyShortcutText: "Option + Tab",
                appLanguage: .english,
                targetAppearance: appearance
            )
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 620, height: 620)
        hostedView.layoutSubtreeIfNeeded()

        let openButton = try XCTUnwrap(
            compactActionButton(
                in: hostedView,
                identifier: "flowtab.logs.open-directory"
            )
        )
        let clearButton = try XCTUnwrap(
            compactActionButton(
                in: hostedView,
                identifier: "flowtab.logs.clear"
            )
        )

        XCTAssertEqual(openButton.attributedTitle.string, "Open Directory")
        XCTAssertEqual(clearButton.attributedTitle.string, "Clear Logs")
        XCTAssertEqual(openButton.presentationForTesting.metrics.height, 32)
        XCTAssertEqual(clearButton.presentationForTesting.metrics.minimumWidth, 68)
        assertCompactActionButtonStyle(
            openButton.presentationForTesting.style(for: .normal),
            matchesLogsActionBlueIn: appearance
        )
        assertCompactActionButtonStyle(
            clearButton.presentationForTesting.style(for: .normal),
            matchesLogsActionBlueIn: appearance
        )
    }

    private func compactActionButton(
        in view: NSView,
        identifier: String
    ) -> FlowCompactActionButtonControl? {
        if view.identifier?.rawValue == identifier || view.accessibilityIdentifier() == identifier {
            return view as? FlowCompactActionButtonControl
        }
        for subview in view.subviews {
            if let match = compactActionButton(in: subview, identifier: identifier) {
                return match
            }
        }
        return nil
    }

    private func assertCompactActionButtonStyle(
        _ style: FlowCompactActionButtonStyle,
        matchesLogsActionBlueIn appearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertColor(style.textColor, matches: .white, in: appearance, file: file, line: line)
        assertColor(
            style.backgroundColor,
            matches: NSColor(srgbRed: 58 / 255, green: 128 / 255, blue: 247 / 255, alpha: 1),
            in: appearance,
            file: file,
            line: line
        )
    }

    private func assertColor(
        _ color: NSColor,
        matches expectedColor: NSColor,
        in appearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var actualColor: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            actualColor = color.usingColorSpace(.sRGB)
        }
        guard let actual = actualColor, let expected = expectedColor.usingColorSpace(.sRGB) else {
            XCTFail("Expected comparable sRGB colors", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.01, file: file, line: line)
    }
}
