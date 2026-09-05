import AppKit

enum SwitcherReusablePanelShellResult: Equatable {
    case prepared
    case notRequired
    case superseded
}

@MainActor
protocol SwitcherReusablePanelShellPreparing: AnyObject {
    func prepare(contentSize: NSSize?, completion: @escaping (SwitcherReusablePanelShellResult) -> Void)
    func cancel()
}

@MainActor
final class SwitcherReusablePanelShell: SwitcherReusablePanelShellPreparing {
    private weak var controller: SwitcherPanelController?
    private struct Pending {
        let id: UUID
        let work: DispatchWorkItem
        let completion: (SwitcherReusablePanelShellResult) -> Void
    }
    private var pending: Pending?

    init(controller: SwitcherPanelController) { self.controller = controller }

    func prepare(contentSize: NSSize?, completion: @escaping (SwitcherReusablePanelShellResult) -> Void) {
        cancel()
        guard let contentSize else { completion(.notRequired); return }
        guard let controller else { completion(.superseded); return }
        let presentationGeneration = controller.presentationSessionGeneration
        let id = UUID()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pending, pending.id == id else { return }
            self.pending = nil
            guard let controller = self.controller, !controller.panelPresentationActive,
                  controller.presentationSessionGeneration == presentationGeneration else {
                pending.completion(.superseded)
                return
            }
            controller.panelGeometry.setPanelContentSize(contentSize, recenterScreen: nil)
            controller.panel.orderFrontRegardless()
            pending.completion(.prepared)
        }
        pending = Pending(id: id, work: work, completion: completion)
        DispatchQueue.main.async(execute: work)
    }

    func cancel() {
        let cancelled = pending
        pending = nil
        cancelled?.work.cancel()
        cancelled?.completion(.superseded)
    }

    deinit {
        MainActor.assumeIsolated {
            pending?.work.cancel()
            pending?.completion(.superseded)
        }
    }
}
