import FlowTabCore

@MainActor
protocol SwitcherFocusedWindowSessionInstalling {
    func applyRecency(_ payload: RuntimeCurrentAppWindowPayload) -> RuntimeCurrentAppWindowPayload
    func install(payload: RuntimeCurrentAppWindowPayload, triggerDirection: CycleDirection) -> Bool
}

@MainActor
struct SwitcherFocusedWindowSessionInstaller: SwitcherFocusedWindowSessionInstalling {
    unowned let model: LiveSwitcherModel

    func applyRecency(_ payload: RuntimeCurrentAppWindowPayload) -> RuntimeCurrentAppWindowPayload {
        model.currentAppWindowPayloadWithWindowRecencyApplied(payload)
    }

    func install(
        payload: RuntimeCurrentAppWindowPayload,
        triggerDirection: CycleDirection
    ) -> Bool {

        let appCandidate = payload.candidate
        guard !appCandidate.windows.isEmpty else { return false }

        model.overlayStyle = .windowOnly
        model.titleBarStyleInferenceEnabled = true
        model.runtimeContextsByID = [appCandidate.id: payload.context]
        model.clearPreviewSnapshotState()
        model.autoEnterSuppressedAppID = nil
        guard let rebuiltSession = model.sessionState.buildWindowSession(
            app: appCandidate,
            preferences: SwitcherBehaviorPreferencesStore.loadSwitcherPreferences(),
            direction: triggerDirection,
            rememberedWindows: model.rememberedWindowIDByAppID
        ) else { return false }
        model.session = rebuiltSession
        _ = model.searchCoordinator.exit()
        model.publishSearchStateIfNeeded()
        return true
    }

}
