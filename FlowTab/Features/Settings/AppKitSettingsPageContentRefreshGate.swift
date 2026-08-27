struct AppKitSettingsPageContentRefreshGate {
    private var lastAppliedState: AppKitSettingsPageState?

    mutating func consume(_ state: AppKitSettingsPageState) -> Bool {
        guard lastAppliedState != state else { return false }
        lastAppliedState = state
        return true
    }
}
