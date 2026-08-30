import AppKit
import SwiftUI

@MainActor
struct HomeRetainedTabContentHost: NSViewRepresentable {
    typealias ContentProvider = HomeRetainedTabContentProvider

    let selectedTab: HomeTab
    var targetAppearance: NSAppearance = NSApp.effectiveAppearance
    var contentIdentity: AnyHashable? = nil
    var contentRevision: AnyHashable = AnyHashable(0)
    let contentForTab: ContentProvider

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.present(
            selectedTab: selectedTab,
            targetAppearance: targetAppearance,
            contentIdentity: contentIdentity,
            contentRevision: contentRevision,
            contentForTab: contentForTab,
            in: container
        )
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.present(
            selectedTab: selectedTab,
            targetAppearance: targetAppearance,
            contentIdentity: contentIdentity,
            contentRevision: contentRevision,
            contentForTab: contentForTab,
            in: container
        )
    }

    static func dismantleNSView(
        _ container: NSView,
        coordinator: Coordinator
    ) {
        coordinator.dismantle(from: container)
    }

    @MainActor
    final class Coordinator {
        private struct PageBinding {
            let hostingView: NSHostingView<HomeRetainedTabPageRoot>
            let presentation: HomeRetainedTabPagePresentation
            let contentIdentity: AnyHashable?
        }

        private var bindings: [HomeTab: PageBinding] = [:]
        private var activeTab: HomeTab?

        func present(
            selectedTab: HomeTab,
            targetAppearance: NSAppearance,
            contentIdentity: AnyHashable? = nil,
            contentRevision: AnyHashable = AnyHashable(0),
            contentForTab: @escaping ContentProvider,
            in container: NSView
        ) {
            for binding in bindings.values {
                binding.presentation.updateContentProvider(contentForTab)
            }
            let identityChanged = bindings[selectedTab].map {
                $0.contentIdentity != contentIdentity
            } ?? false

            if activeTab == selectedTab,
               let binding = bindings[selectedTab],
               binding.hostingView.superview === container,
               !identityChanged
            {
                apply(targetAppearance, to: binding.hostingView)
                binding.hostingView.frame = container.bounds
                binding.presentation.update(
                    isActive: true,
                    contentRevision: contentRevision
                )
                return
            }

            if let outgoingTab = activeTab,
               let outgoingBinding = bindings[outgoingTab]
            {
                outgoingBinding.presentation.update(
                    isActive: false,
                    contentRevision:
                        outgoingBinding.presentation.snapshot.contentRevision
                )
                clearFirstResponder(
                    in: outgoingBinding.hostingView,
                    container: container
                )
                outgoingBinding.hostingView.isHidden = true
            }

            if identityChanged,
               let replacedBinding = bindings.removeValue(
                    forKey: selectedTab
                )
            {
                replacedBinding.hostingView.removeFromSuperview()
            }

            let incomingBinding: PageBinding
            let requiresInitialLayout: Bool
            if let cachedBinding = bindings[selectedTab] {
                incomingBinding = cachedBinding
                requiresInitialLayout = false
            } else {
                let presentation = HomeRetainedTabPagePresentation(
                    tab: selectedTab,
                    isActive: true,
                    contentRevision: contentRevision,
                    contentProvider: contentForTab
                )
                let hostingView = NSHostingView(
                    rootView: HomeRetainedTabPageRoot(
                        presentation: presentation
                    )
                )
                hostingView.translatesAutoresizingMaskIntoConstraints = true
                hostingView.autoresizingMask = [.width, .height]
                hostingView.sizingOptions = []
                hostingView.isHidden = true
                incomingBinding = PageBinding(
                    hostingView: hostingView,
                    presentation: presentation,
                    contentIdentity: contentIdentity
                )
                bindings[selectedTab] = incomingBinding
                requiresInitialLayout = true
            }

            let incomingView = incomingBinding.hostingView
            incomingBinding.presentation.updateContentProvider(contentForTab)
            apply(targetAppearance, to: incomingView)
            incomingView.frame = container.bounds
            incomingBinding.presentation.update(
                isActive: true,
                contentRevision: contentRevision
            )
            if incomingView.superview !== container {
                container.addSubview(incomingView)
            }
            incomingView.isHidden = false
            if requiresInitialLayout,
               container.bounds.width > 0,
               container.bounds.height > 0
            {
                container.layoutSubtreeIfNeeded()
                incomingView.layoutSubtreeIfNeeded()
            }
            activeTab = selectedTab
        }

        private func apply(
            _ targetAppearance: NSAppearance,
            to hostingView: NSView
        ) {
            guard hostingView.appearance?.name != targetAppearance.name else {
                return
            }
            hostingView.appearance = targetAppearance
        }

        func dismantle(from container: NSView) {
            for binding in bindings.values {
                binding.presentation.update(
                    isActive: false,
                    contentRevision:
                        binding.presentation.snapshot.contentRevision
                )
            }
            container.window?.makeFirstResponder(nil)
            for binding in bindings.values {
                binding.hostingView.removeFromSuperview()
            }
            bindings.removeAll()
            activeTab = nil
        }

        private func clearFirstResponder(
            in outgoingView: NSView,
            container: NSView
        ) {
            guard let window = container.window,
                  let responderView = window.firstResponder as? NSView,
                  responderView === outgoingView
                    || responderView.isDescendant(of: outgoingView)
            else {
                return
            }
            window.makeFirstResponder(nil)
        }
    }
}
