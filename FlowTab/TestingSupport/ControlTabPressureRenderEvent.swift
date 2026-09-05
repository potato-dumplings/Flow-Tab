#if FLOWTAB_TESTING
import AppKit

struct ControlTabPressureDrawIdentity: Equatable {
    let presentationGeneration: Int
    let selectedWindowID: String?
    let previewVersion: UInt64
}

struct ControlTabPressureRenderEvent: Equatable {
    let milestone: SwitcherRenderMilestone
    let renderGeneration: UInt64
    let drawnAtMilliseconds: Double
    var processCPUSnapshot: RuntimeProcessCPUSnapshot? = nil
    let identity: ControlTabPressureDrawIdentity
}

@MainActor
final class ControlTabPressurePanelVisibilityObservation {
    private var alphaObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []

    init(controller: SwitcherPanelController) {
        alphaObservation = controller.panel.observe(\.alphaValue, options: [.new]) { [weak controller] _, _ in
            MainActor.assumeIsolated { controller?.deliverPressureRenderMilestoneIfVisible() }
        }
        for name in [NSWindow.didExposeNotification, NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didBecomeKeyNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: controller.panel,
                queue: .main) { [weak controller] _ in
                    MainActor.assumeIsolated { controller?.deliverPressureRenderMilestoneIfVisible() }
                })
        }
    }

    func cancel() {
        alphaObservation?.invalidate()
        alphaObservation = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
    }

    deinit {
        alphaObservation?.invalidate()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension SwitcherPanelController {
    var pressureDrawIdentity: ControlTabPressureDrawIdentity {
        .init(presentationGeneration: presentationSessionGeneration,
              selectedWindowID: model.session?.selectedWindow?.id,
              previewVersion: model.windowContentRenderGeneration)
    }
}
#endif
