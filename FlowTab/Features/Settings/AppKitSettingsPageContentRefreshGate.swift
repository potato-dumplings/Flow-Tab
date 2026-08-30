struct AppKitSettingsPageContentRefreshGate {
    private var lastAppliedState: AppKitSettingsPageState?
    private(set) var contentRevision: UInt64 = 0

    mutating func consume(_ state: AppKitSettingsPageState) -> Bool {
        guard lastAppliedState != state else { return false }
        lastAppliedState = state
        contentRevision &+= 1
        return true
    }

    mutating func invalidateContent() {
        contentRevision &+= 1
    }
}
