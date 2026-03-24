import Carbon
import Foundation

final class OptionTabHotkeyMonitor {
    var onHotkeyPressed: ((Bool) -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]

    private let signature: OSType = 0x46544142 // "FTAB"
    private let forwardHotkeyID: UInt32 = 1
    private let backwardHotkeyID: UInt32 = 2

    init() {
        installHandler()
        registerHotkeys()
    }

    deinit {
        stop()
    }

    func stop() {
        for hotkeyRef in hotkeyRefs.values {
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let monitor = Unmanaged<OptionTabHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                return monitor.handleHotkeyEvent(event)
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
        }
    }

    private func registerHotkeys() {
        registerHotkey(id: forwardHotkeyID, modifiers: UInt32(optionKey))
        registerHotkey(id: backwardHotkeyID, modifiers: UInt32(optionKey | shiftKey))
    }

    private func registerHotkey(id: UInt32, modifiers: UInt32) {
        let hotkeyID = EventHotKeyID(signature: signature, id: id)
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(kVK_Tab),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr, let hotkeyRef {
            hotkeyRefs[id] = hotkeyRef
        }
    }

    private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr, hotkeyID.signature == signature else {
            return noErr
        }

        switch hotkeyID.id {
        case forwardHotkeyID:
            onHotkeyPressed?(false)
        case backwardHotkeyID:
            onHotkeyPressed?(true)
        default:
            break
        }
        return noErr
    }
}
