import AppKit
import Carbon
import FlowTabCore
import XCTest
@testable import FlowTab

private final class ShortcutRecorderMouseDownProbeView: NSView {
    private(set) var mouseDownCount = 0

    override func mouseDown(with event: NSEvent) {
        mouseDownCount += 1
        super.mouseDown(with: event)
    }
}

extension FlowTabTests {
    @MainActor
    func testShortcutRecorderShowsPersistentEditIndicator() throws {
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let control = FlowSettingsShortcutRecorderControl(
            frame: NSRect(x: 0, y: 0, width: 220, height: 32)
        )
        control.applySettingsAppearance(lightAppearance)
        control.update(
            keys: [.option],
            recordingPrompt: "Press shortcut",
            keyRequiredPrompt: "Press at least one key",
            accessibilityLabel: "Main modifiers",
            editHint: "Click to edit shortcut"
        )
        control.layoutSubtreeIfNeeded()

        let editIndicator = try XCTUnwrap(
            control.subviews.compactMap { $0 as? NSImageView }.first
        )
        let valueLabel = try XCTUnwrap(
            control.subviews.compactMap { $0 as? NSTextField }.first
        )
        let normalTint = try XCTUnwrap(editIndicator.contentTintColor)
        let hoverEvent = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )
        control.mouseEntered(with: hoverEvent)
        let hoverTint = try XCTUnwrap(editIndicator.contentTintColor)

        XCTAssertNotNil(editIndicator.image)
        XCTAssertEqual(control.toolTip, "Click to edit shortcut")
        XCTAssertEqual(valueLabel.frame.midX, control.bounds.midX, accuracy: 1)
        XCTAssertLessThanOrEqual(editIndicator.frame.maxX, control.bounds.maxX)
        XCTAssertFalse(normalTint.isEqual(hoverTint))

        control.applySettingsAppearance(darkAppearance)
        XCTAssertEqual(
            control.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]),
            .darkAqua
        )
        control.isEnabled = false
        XCTAssertEqual(control.alphaValue, 0.55)
        XCTAssertFalse(editIndicator.isHidden)
        XCTAssertEqual(
            AppStrings.text(.hotkeyRecorderEditHint, language: .simplifiedChinese),
            "点击修改快捷键"
        )
        XCTAssertEqual(
            AppStrings.text(.hotkeyRecorderEditHint, language: .english),
            "Click to edit shortcut"
        )
    }

    @MainActor
    func testShortcutRecorderOutsideMouseDownCancelsPendingRecordingAndPreservesEvent() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        let control = FlowSettingsShortcutRecorderControl(
            frame: NSRect(x: 20, y: 80, width: 220, height: 32)
        )
        let outsideView = ShortcutRecorderMouseDownProbeView(
            frame: NSRect(x: 300, y: 20, width: 160, height: 80)
        )
        control.translatesAutoresizingMaskIntoConstraints = true
        outsideView.translatesAutoresizingMaskIntoConstraints = true
        contentView.addSubview(control)
        contentView.addSubview(outsideView)
        window.contentView = contentView
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        control.update(
            keys: [.control],
            recordingPrompt: "Press shortcut",
            keyRequiredPrompt: "Press at least one key",
            accessibilityLabel: "Main modifiers"
        )
        var changedKeys: [SwitcherHotkeyKeySet] = []
        var interactionCount = 0
        control.onKeysChanged = { changedKeys.append($0) }
        control.onInteraction = { interactionCount += 1 }

        XCTAssertTrue(control.accessibilityPerformPress())
        XCTAssertEqual(interactionCount, 1)
        control.flagsChanged(
            with: try shortcutRecorderModifierEvent(
                flags: [.option],
                keyCode: UInt16(kVK_Option)
            )
        )
        XCTAssertTrue(control.isRecording)
        XCTAssertEqual(control.accessibilityValue() as? String, "Option")

        try sendShortcutRecorderMouseDown(
            at: NSPoint(x: control.frame.midX, y: control.frame.midY),
            in: window,
            eventNumber: 1
        )
        XCTAssertTrue(control.isRecording)
        XCTAssertEqual(interactionCount, 2)
        XCTAssertEqual(control.accessibilityValue() as? String, "Press shortcut")
        control.flagsChanged(
            with: try shortcutRecorderModifierEvent(
                flags: [.option],
                keyCode: UInt16(kVK_Option)
            )
        )
        try sendShortcutRecorderMouseDown(
            at: NSPoint(x: outsideView.frame.midX, y: outsideView.frame.midY),
            in: window,
            eventNumber: 2
        )

        XCTAssertEqual(outsideView.mouseDownCount, 1)
        XCTAssertFalse(control.isRecording)
        XCTAssertFalse(window.firstResponder === control)
        XCTAssertEqual(control.recordedKeys, [.control])
        XCTAssertEqual(control.accessibilityValue() as? String, "Control")
        XCTAssertTrue(changedKeys.isEmpty)
    }

    @MainActor
    func testShortcutRecorderWindowResignCancelsPendingRecording() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let control = FlowSettingsShortcutRecorderControl(
            frame: NSRect(x: 20, y: 40, width: 220, height: 32)
        )
        control.translatesAutoresizingMaskIntoConstraints = true
        window.contentView = NSView(frame: window.contentLayoutRect)
        window.contentView?.addSubview(control)
        defer { window.contentView = nil }

        control.update(
            keys: [.option],
            recordingPrompt: "Press shortcut",
            keyRequiredPrompt: "Press at least one key",
            accessibilityLabel: "Main modifiers"
        )
        XCTAssertTrue(control.accessibilityPerformPress())
        control.flagsChanged(
            with: try shortcutRecorderModifierEvent(
                flags: [.shift],
                keyCode: UInt16(kVK_Shift)
            )
        )

        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: window
        )

        XCTAssertFalse(control.isRecording)
        XCTAssertEqual(control.recordedKeys, [.option])
        XCTAssertEqual(control.accessibilityValue() as? String, "Option")
    }

    private func shortcutRecorderModifierEvent(
        flags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    private func sendShortcutRecorderMouseDown(
        at location: NSPoint,
        in window: NSWindow,
        eventNumber: Int
    ) throws {
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: eventNumber,
                clickCount: 1,
                pressure: 1
            )
        )
        NSApp.postEvent(event, atStart: true)
        let deliveredEvent = try XCTUnwrap(
            NSApp.nextEvent(
                matching: .leftMouseDown,
                until: Date(timeIntervalSinceNow: 1),
                inMode: .default,
                dequeue: true
            )
        )
        NSApp.sendEvent(deliveredEvent)
    }
}
