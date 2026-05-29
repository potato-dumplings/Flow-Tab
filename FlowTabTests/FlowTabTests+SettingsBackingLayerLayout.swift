import AppKit
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testSettingsCardLayoutDoesNotResetBackingLayerOrigin() throws {
        let card = FlowSettingsCardView(
            title: "Card",
            subtitle: "Subtitle",
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        )
        try assertBackingLayerTracksViewFrame(card, size: NSSize(width: 320, height: 180))
    }

    @MainActor
    func testSettingsLayerBackedChromeControlsDoNotResetBackingLayerOrigin() throws {
        let segmented = FlowSettingsSegmentedControl(options: [
            (id: "light", title: "Light"),
            (id: "dark", title: "Dark")
        ])
        segmented.updateSelection(id: "dark")
        try assertBackingLayerTracksViewFrame(segmented, size: NSSize(width: 260, height: 32))

        let dropdown = FlowDropdownControl(frame: .zero)
        dropdown.configure(
            options: [
                FlowDropdownOption(id: "zh", title: "Simplified Chinese"),
                FlowDropdownOption(id: "en", title: "English")
            ],
            selectedID: "zh",
            presentation: .form(targetAppearance: NSAppearance(named: .darkAqua) ?? NSApp.effectiveAppearance)
        )
        try assertBackingLayerTracksViewFrame(dropdown, size: NSSize(width: 240, height: 32))
    }

    private func assertBackingLayerTracksViewFrame(
        _ view: NSView,
        size: NSSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        parent.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = NSRect(x: 48, y: 72, width: size.width, height: size.height)
        parent.addSubview(view)
        view.needsLayout = true
        parent.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()

        let layer = try XCTUnwrap(view.layer, file: file, line: line)
        XCTAssertEqual(layer.frame.minX, view.frame.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(layer.frame.minY, view.frame.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(layer.frame.width, view.frame.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(layer.frame.height, view.frame.height, accuracy: 1, file: file, line: line)
    }
}
