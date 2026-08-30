struct AppKitSettingsPageContentRefreshGate {
    private var lastAppliedState: AppKitSettingsPageState?
    private(set) var contentRevision: UInt64 = 0

    var hasAppliedState: Bool {
        lastAppliedState != nil
    }

    mutating func consume(_ state: AppKitSettingsPageState) -> Bool {
        guard lastAppliedState != state else { return false }
        lastAppliedState = state
        contentRevision &+= 1
        return true
    }
}
