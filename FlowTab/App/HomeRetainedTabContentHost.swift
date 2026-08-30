import AppKit
import SwiftUI

@MainActor
struct HomeRetainedTabContentHost: NSViewRepresentable {
    typealias ContentProvider = HomeRetainedTabContentProvider

    let selectedTab: HomeTab
    var targetAppearance: NSAppearance = NSApp.effectiveAppearance
    let descriptor: HomeRetainedTabPageDescriptor
    let contentForTab: ContentProvider

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.present(
            selectedTab: selectedTab,
            targetAppearance: targetAppearance,
            descriptor: descriptor,
            contentForTab: contentForTab,
            in: container
        )
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.present(
            selectedTab: selectedTab,
            targetAppearance: targetAppearance,
            descriptor: descriptor,
            contentForTab: contentForTab,
            in: container
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSView,
        context: Context
    ) -> CGSize? {
        FlowFillViewportSizing.resolve(
            proposal: proposal,
            currentSize: nsView.bounds.size
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
        private final class PageBinding {
            let hostingView: NSHostingView<HomeRetainedTabPageRoot>
            let presentation: HomeRetainedTabPagePresentation
            var descriptor: HomeRetainedTabPageDescriptor

            init(
                hostingView: NSHostingView<HomeRetainedTabPageRoot>,
                presentation: HomeRetainedTabPagePresentation,
                descriptor: HomeRetainedTabPageDescriptor
            ) {
                self.hostingView = hostingView
                self.presentation = presentation
                self.descriptor = descriptor
            }
        }

        private var bindings: [HomeTab: PageBinding] = [:]
        private var activeTab: HomeTab?

        func present(
            selectedTab: HomeTab,
            targetAppearance: NSAppearance,
            descriptor: HomeRetainedTabPageDescriptor,
            contentForTab: @escaping ContentProvider,
            in container: NSView
        ) {
            for binding in bindings.values {
                binding.presentation.updateContentProvider(contentForTab)
            }
            let identityChanged = bindings[selectedTab].map {
                $0.descriptor.identity != descriptor.identity
            } ?? false

            if activeTab == selectedTab,
               let binding = bindings[selectedTab],
               binding.hostingView.superview === container,
               !identityChanged
            {
                apply(targetAppearance, to: binding.hostingView)
                apply(container.bounds, to: binding.hostingView)
                if binding.descriptor.contentRevision
                    != descriptor.contentRevision
                {
                    binding.presentation.update(
                        contentRevision: descriptor.contentRevision
                    )
                }
                binding.descriptor = descriptor
                return
            }

            if let outgoingTab = activeTab,
               let outgoingBinding = bindings[outgoingTab]
            {
                outgoingBinding.presentation.lifecycle.transition(
                    to: .inactive
                )
                clearFirstResponder(
                    in: outgoingBinding.hostingView,
                    container: container
                )
                if !outgoingBinding.hostingView.isHidden {
                    outgoingBinding.hostingView.isHidden = true
                }
            }

            if identityChanged,
               let replacedBinding = bindings.removeValue(
                    forKey: selectedTab
                )
            {
                replacedBinding.presentation.lifecycle.transition(
                    to: .inactive
                )
                replacedBinding.hostingView.removeFromSuperview()
            }

            let incomingBinding: PageBinding
            let requiresInitialLayout: Bool
            if let cachedBinding = bindings[selectedTab] {
                incomingBinding = cachedBinding
                requiresInitialLayout = false
            } else {
                let lifecycle = HomeRetainedTabLifecycle()
                let presentation = HomeRetainedTabPagePresentation(
                    tab: selectedTab,
                    lifecycle: lifecycle,
                    contentRevision: descriptor.contentRevision,
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
                    descriptor: descriptor
                )
                bindings[selectedTab] = incomingBinding
                requiresInitialLayout = true
            }

            let incomingView = incomingBinding.hostingView
            incomingBinding.presentation.updateContentProvider(contentForTab)
            apply(targetAppearance, to: incomingView)
            apply(container.bounds, to: incomingView)
            if incomingBinding.descriptor.contentRevision
                != descriptor.contentRevision
            {
                incomingBinding.presentation.update(
                    contentRevision: descriptor.contentRevision
                )
            }
            incomingBinding.descriptor = descriptor
            if incomingView.superview !== container {
                container.addSubview(incomingView)
            }
            incomingBinding.presentation.lifecycle.transition(to: .active)
            if incomingView.isHidden {
                incomingView.isHidden = false
            }
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

        private func apply(_ frame: NSRect, to hostingView: NSView) {
            guard hostingView.frame != frame else { return }
            hostingView.frame = frame
        }

        func dismantle(from container: NSView) {
            for binding in bindings.values {
                binding.presentation.lifecycle.transition(to: .inactive)
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
