import AppKit
import FlowTabCore

extension SwitcherPreviewPlanner.Operation {
    func plan(visibleRange: Range<Int>?) -> SwitcherPreviewPlan? {

        guard let session else { return nil }
        guard case .windowCycle(let appID) = session.mode else { return nil }
        guard let app = session.apps.first(where: { $0.id == appID }) else { return nil }

        let previewWindows = SwitcherPreviewSupport.frozenPreviewWindows(for: appID, fallbackApp: app, snapshots: state.previewWindowSnapshotsByAppID)
        let selectedIndex = SwitcherPreviewSupport.selectedPreviewWindowIndex(
            appID: appID,
            session: session,
            previewWindows: previewWindows
        ) ?? 0
        let indexedWindows = SwitcherPreviewSupport.indexedPreviewWindows(in: previewWindows, visibleRange: visibleRange)
        let shouldRequestPreviews = visibleRange != nil || overlayStyle == .windowOnly
        let previewCaptureWindowIDs = shouldRequestPreviews
            ? Set(indexedWindows.map { $0.window.id })
            : []
        var pendingCaptures: [PendingPreviewCapture] = []
        var items: [WindowPreviewItem] = []
        items.reserveCapacity(indexedWindows.count)
        pendingCaptures.reserveCapacity(previewCaptureWindowIDs.count)
        for (index, window) in indexedWindows {
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = overlayStyle == .windowOnly
                ? "Window \(index + 1)"
                : app.displayName
            let preview: (image: NSImage?, titleBarStyle: WindowTitleBarStyleGuess?)
            if previewCaptureWindowIDs.contains(window.id) {
                let previewResult = resolvePreviewData(
                    for: appID,
                    window: window,
                    pinForSession: true
                )
                preview = previewResult.preview
                if let pendingCapture = previewResult.pendingCapture {
                    pendingCaptures.append(pendingCapture)
                }
            } else {
                preview = (image: nil, titleBarStyle: nil)
            }
            items.append(
                WindowPreviewItem(
                    id: window.id,
                    title: title.isEmpty ? fallbackTitle : title,
                    image: preview.image,
                    titleBarStyle: preview.titleBarStyle,
                    isSelected: index == selectedIndex
                )
            )
        }
        return SwitcherPreviewPlan(appID: appID, selectedIndex: selectedIndex,
            items: items, pendingCaptures: pendingCaptures)
    }
}
