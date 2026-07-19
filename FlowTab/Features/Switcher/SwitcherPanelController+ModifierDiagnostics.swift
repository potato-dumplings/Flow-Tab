import Carbon
import CoreGraphics

extension SwitcherPanelController {
    func primaryModifierHardwareStateSummary(for sessionKind: HotkeySessionKind?) -> String {
        let resolvedSessionKind = sessionKind ?? activeHotkeySessionKind ?? .globalAppSwitcher
        let modifier = primaryModifier(for: resolvedSessionKind)
        let keyCodes: (left: CGKeyCode, right: CGKeyCode)
        switch modifier {
        case .option:
            keyCodes = (CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption))
        case .control:
            keyCodes = (CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl))
        case .command:
            keyCodes = (CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand))
        }
        let leftPressed = CGEventSource.keyState(.combinedSessionState, key: keyCodes.left)
        let rightPressed = CGEventSource.keyState(.combinedSessionState, key: keyCodes.right)
        return "modifier=\(modifier.rawValue) left=\(leftPressed ? 1 : 0) right=\(rightPressed ? 1 : 0)"
    }
}
