#if FLOWTAB_TESTING
import AppKit
import SwiftUI

@MainActor
struct ControlTabPressureRenderProbe: NSViewRepresentable {
    let generation: UInt64
    let identity: ControlTabPressureDrawIdentity
    let onDraw: ((ControlTabPressureRenderEvent) -> Void)?

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        configure(view)
        view.needsDisplay = true
    }

    private func configure(_ view: ProbeView) {
        view.generation = generation
        view.identity = identity
        view.onDraw = onDraw
    }

    final class ProbeView: NSView {
        var generation: UInt64 = 0
        var onDraw: ((ControlTabPressureRenderEvent) -> Void)?
        var identity = ControlTabPressureDrawIdentity(presentationGeneration: 0, selectedWindowID: nil, previewVersion: 0)
        private var deliveredIdentity: ControlTabPressureDrawIdentity?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let window, window.isVisible,
                  !isHiddenOrHasHiddenAncestor,
                  deliveredIdentity != identity,
                  let onDraw else { return }
            deliveredIdentity = identity
            let event = ControlTabPressureRenderEvent(
                milestone: .windowContent,
                renderGeneration: generation,
                drawnAtMilliseconds: ProcessInfo.processInfo.systemUptime * 1_000,
                processCPUSnapshot: RuntimeProcessDiagnosticClock.cpuSnapshot(),
                identity: identity
            )
            // Publish after the draw callback without asking the product to redraw or reveal.
            DispatchQueue.main.async { onDraw(event) }
        }
    }
}
#endif
