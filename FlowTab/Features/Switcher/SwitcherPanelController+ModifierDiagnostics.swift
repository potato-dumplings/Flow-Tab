extension SwitcherPanelController {
    func hotkeyHoldSetHardwareStateSummary(
        for sessionKind: HotkeySessionKind?
    ) -> String {
        let resolvedSessionKind = sessionKind ?? activeHotkeySessionKind ?? .globalAppSwitcher
        let keys = hotkeyHoldKeys(for: resolvedSessionKind)
        let pressed = isHotkeyKeySetPressedInHardwareState(keys)
        return "holdKeys=\(keys.rawValue) pressed=\(pressed ? 1 : 0)"
    }
}
