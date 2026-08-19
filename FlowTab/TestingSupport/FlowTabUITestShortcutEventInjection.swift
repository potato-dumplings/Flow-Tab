#if FLOWTAB_TESTING
import AppKit
import Carbon
import CoreGraphics
import Foundation

private enum FlowTabUITestShortcutEventInjectionTransport {
    static let notificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab.ui-test.shortcut-event-injection"
    )

    enum UserInfoKey {
        static let targetProcessID = "targetProcessID"
        static let keyCodes = "keyCodes"
        static let modifierFlags = "modifierFlags"
        static let mode = "mode"
        static let phase = "phase"
    }
}

@MainActor
private final class FlowTabUITestShortcutEventInjectionObserver {
    private let center: DistributedNotificationCenter
    private var token: NSObjectProtocol?
    private var runtimePressedKeyCodes: Set<UInt16> = []
    private var runtimeModifierFlags: NSEvent.ModifierFlags = []

    init(center: DistributedNotificationCenter = .default()) {
        self.center = center
        token = center.addObserver(
            forName:
                FlowTabUITestShortcutEventInjectionTransport
                    .notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.injectShortcutEvents(from: notification)
            }
        }
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }

    private func injectShortcutEvents(from notification: Notification) {
        let userInfo = notification.userInfo
        guard
            let targetProcessID = (
                userInfo?[
                    FlowTabUITestShortcutEventInjectionTransport
                        .UserInfoKey.targetProcessID
                ] as? NSNumber
            )?.int32Value,
            targetProcessID == ProcessInfo.processInfo.processIdentifier,
            let rawKeyCodes = userInfo?[
                FlowTabUITestShortcutEventInjectionTransport
                    .UserInfoKey.keyCodes
            ] as? [NSNumber],
            let modifierFlagsRawValue = (
                userInfo?[
                    FlowTabUITestShortcutEventInjectionTransport
                        .UserInfoKey.modifierFlags
                ] as? NSNumber
            )?.uintValue
        else {
            return
        }

        let keyCodes = rawKeyCodes.map(\.uint16Value)
        let modifierFlags = NSEvent.ModifierFlags(
            rawValue: modifierFlagsRawValue
        )
        let mode = userInfo?[
            FlowTabUITestShortcutEventInjectionTransport
                .UserInfoKey.mode
        ] as? String
        if mode == "runtime-state" {
            applyRuntimePressedState(
                keyCodes: Set(keyCodes),
                modifierFlags: modifierFlags
            )
            return
        }
        if mode == "runtime" {
            injectRuntimeShortcutEvents(
                keyCodes: keyCodes,
                modifierFlags: modifierFlags,
                phase: userInfo?[
                    FlowTabUITestShortcutEventInjectionTransport
                        .UserInfoKey.phase
                ] as? String
            )
            return
        }
        guard let recorder = NSApp.keyWindow?.firstResponder
            as? FlowSettingsShortcutRecorderControl
        else {
            return
        }
        if keyCodes.isEmpty,
           let modifierPress = event(
               type: .flagsChanged,
               keyCode: UInt16(kVK_Option),
               modifierFlags: modifierFlags
           ) {
            recorder.flagsChanged(with: modifierPress)
        }
        for keyCode in keyCodes {
            guard let keyDown = event(
                type: .keyDown,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            ) else {
                continue
            }
            recorder.keyDown(with: keyDown)
        }
        for keyCode in keyCodes.reversed() {
            guard let keyUp = event(
                type: .keyUp,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            ) else {
                continue
            }
            recorder.keyUp(with: keyUp)
        }
        if !modifierFlags.isEmpty,
           let modifierRelease = event(
               type: .flagsChanged,
               keyCode: UInt16(kVK_Option),
               modifierFlags: []
           ) {
            recorder.flagsChanged(with: modifierRelease)
        }
    }

    private func applyRuntimePressedState(
        keyCodes: Set<UInt16>,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        var currentModifiers = runtimeModifierFlags
        let releasedKeyCodes = runtimePressedKeyCodes
            .subtracting(keyCodes)
            .sorted(by: >)
        for keyCode in releasedKeyCodes {
            postKeyEvent(
                keyCode: keyCode,
                keyDown: false,
                flags: cgEventFlags(for: currentModifiers)
            )
        }

        for binding in runtimeModifierBindings.reversed()
        where currentModifiers.contains(binding.eventFlag)
            && !modifierFlags.contains(binding.eventFlag)
        {
            currentModifiers.remove(binding.eventFlag)
            postFlagsChanged(
                keyCode: binding.keyCode,
                flags: cgEventFlags(for: currentModifiers)
            )
        }
        for binding in runtimeModifierBindings
        where !currentModifiers.contains(binding.eventFlag)
            && modifierFlags.contains(binding.eventFlag)
        {
            currentModifiers.insert(binding.eventFlag)
            postFlagsChanged(
                keyCode: binding.keyCode,
                flags: cgEventFlags(for: currentModifiers)
            )
        }

        let pressedKeyCodes = keyCodes
            .subtracting(runtimePressedKeyCodes)
            .sorted()
        for keyCode in pressedKeyCodes {
            postKeyEvent(
                keyCode: keyCode,
                keyDown: true,
                flags: cgEventFlags(for: currentModifiers)
            )
        }
        runtimePressedKeyCodes = keyCodes
        runtimeModifierFlags = modifierFlags
    }

    private func injectRuntimeShortcutEvents(
        keyCodes: [UInt16],
        modifierFlags: NSEvent.ModifierFlags,
        phase: String?
    ) {
        let eventFlags = cgEventFlags(for: modifierFlags)
        if phase == "press" {
            if keyCodes.isEmpty,
               let modifierKeyCode = modifierKeyCode(
                   for: modifierFlags
               ) {
                postFlagsChanged(
                    keyCode: modifierKeyCode,
                    flags: eventFlags
                )
            }
            for keyCode in keyCodes {
                postKeyEvent(
                    keyCode: keyCode,
                    keyDown: true,
                    flags: eventFlags
                )
            }
            return
        }
        guard phase == "release" else { return }
        for keyCode in keyCodes.reversed() {
            postKeyEvent(
                keyCode: keyCode,
                keyDown: false,
                flags: eventFlags
            )
        }
        if let modifierKeyCode = modifierKeyCode(
            for: modifierFlags
        ) {
            postFlagsChanged(
                keyCode: modifierKeyCode,
                flags: []
            )
        }
    }

    private func postKeyEvent(
        keyCode: UInt16,
        keyDown: Bool,
        flags: CGEventFlags
    ) {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: keyDown
        )
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func postFlagsChanged(
        keyCode: UInt16,
        flags: CGEventFlags
    ) {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: !flags.isEmpty
        )
        event?.type = .flagsChanged
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func cgEventFlags(
        for modifierFlags: NSEvent.ModifierFlags
    ) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifierFlags.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifierFlags.contains(.control) {
            flags.insert(.maskControl)
        }
        if modifierFlags.contains(.option) {
            flags.insert(.maskAlternate)
        }
        if modifierFlags.contains(.shift) {
            flags.insert(.maskShift)
        }
        return flags
    }

    private func modifierKeyCode(
        for modifierFlags: NSEvent.ModifierFlags
    ) -> UInt16? {
        if modifierFlags.contains(.command) {
            return UInt16(kVK_Command)
        }
        if modifierFlags.contains(.control) {
            return UInt16(kVK_Control)
        }
        if modifierFlags.contains(.option) {
            return UInt16(kVK_Option)
        }
        if modifierFlags.contains(.shift) {
            return UInt16(kVK_Shift)
        }
        return nil
    }

    private var runtimeModifierBindings: [
        (
            eventFlag: NSEvent.ModifierFlags,
            keyCode: UInt16
        )
    ] {
        [
            (.command, UInt16(kVK_Command)),
            (.control, UInt16(kVK_Control)),
            (.option, UInt16(kVK_Option)),
            (.shift, UInt16(kVK_Shift))
        ]
    }

    private func event(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

@MainActor
enum FlowTabUITestShortcutEventInjectionBootstrap {
    private static var observer:
        FlowTabUITestShortcutEventInjectionObserver?

    static func prepareIfNeeded() {
        observer = nil
        guard
            FlowTabTestLaunchOptions.isRunningUITests,
            FlowTabTestLaunchOptions.enablesShortcutEventInjection
        else {
            return
        }
        observer = FlowTabUITestShortcutEventInjectionObserver()
    }
}
#endif
