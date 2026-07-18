import FlowTabCore

enum RuntimeCurrentAppWindowPreservationPolicy {
    static func allowsPreserving(
        _ window: WindowCandidate,
        context: RuntimeWindowContext,
        currentPayload: RuntimeCurrentAppWindowPayload
    ) -> Bool {
        guard context.activationHandleID == nil, context.axWindow == nil else { return true }
        guard let titleKey = RuntimeWindowPresentationFilter.normalizedTitleKey(window.title) else {
            return true
        }

        let hasCurrentActivationPeer = currentPayload.candidate.windows.contains { currentWindow in
            guard currentWindow.id != window.id else { return false }
            guard RuntimeWindowPresentationFilter.normalizedTitleKey(currentWindow.title) == titleKey else {
                return false
            }
            guard let currentContext = currentPayload.context.windowsByID[currentWindow.id] else {
                return false
            }
            return currentContext.activationHandleID != nil || currentContext.axWindow != nil
        }
        return !hasCurrentActivationPeer
    }
}
