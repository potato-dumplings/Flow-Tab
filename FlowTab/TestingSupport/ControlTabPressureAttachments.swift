#if FLOWTAB_TESTING
import ObjectiveC

@MainActor
private enum ControlTabPressureAttachmentKeys {
    static var model: UInt8 = 0
    static var panel: UInt8 = 0
}

extension LiveSwitcherModel {
    func installControlTabPressureDiagnostics(_ diagnostics: ControlTabPressureModelDiagnostics) {
        objc_setAssociatedObject(self, &ControlTabPressureAttachmentKeys.model,
                                 diagnostics, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    var controlTabPressureDiagnostics: ControlTabPressureModelDiagnostics {
        if let existing = objc_getAssociatedObject(self, &ControlTabPressureAttachmentKeys.model)
            as? ControlTabPressureModelDiagnostics { return existing }
        let state = ControlTabPressureModelDiagnostics()
        objc_setAssociatedObject(self, &ControlTabPressureAttachmentKeys.model,
                                 state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }
}

extension SwitcherPanelController {
    func installControlTabPressureDiagnostics(_ diagnostics: ControlTabPressurePanelDiagnostics) {
        objc_setAssociatedObject(self, &ControlTabPressureAttachmentKeys.panel,
                                 diagnostics, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    var controlTabPressureDiagnostics: ControlTabPressurePanelDiagnostics {
        if let existing = objc_getAssociatedObject(self, &ControlTabPressureAttachmentKeys.panel)
            as? ControlTabPressurePanelDiagnostics { return existing }
        let state = ControlTabPressurePanelDiagnostics()
        objc_setAssociatedObject(self, &ControlTabPressureAttachmentKeys.panel,
                                 state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }
}
#endif
