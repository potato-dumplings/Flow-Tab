import AppKit
import SwiftUI

@MainActor
struct HomeRetainedTabContentHost: NSViewRepresentable {
    typealias ContentProvider = (HomeTab, Bool) -> AnyView

    let selectedTab: HomeTab
    var targetAppearance: NSAppearance = NSApp.effectiveAppearance
    var contentIdentity: AnyHashable? = nil
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
        private var hostingViews: [HomeTab: NSHostingView<AnyView>] = [:]
        private var contentIdentities: [HomeTab: AnyHashable] = [:]
        private var activeTab: HomeTab?
        private var latestContentProvider: ContentProvider?

        func present(
            selectedTab: HomeTab,
            targetAppearance: NSAppearance,
            contentIdentity: AnyHashable? = nil,
            contentForTab: @escaping ContentProvider,
            in container: NSView
        ) {
            latestContentProvider = contentForTab
            let identityChanged = contentIdentity.map {
                contentIdentities[selectedTab] != $0
            } ?? false

            if activeTab == selectedTab,
               let hostingView = hostingViews[selectedTab],
               hostingView.superview === container,
               !identityChanged
            {
                apply(targetAppearance, to: hostingView)
                hostingView.rootView = contentForTab(selectedTab, true)
                return
            }

            if let outgoingTab = activeTab,
               let outgoingView = hostingViews[outgoingTab]
            {
                apply(targetAppearance, to: outgoingView)
                outgoingView.rootView = contentForTab(outgoingTab, false)
                clearFirstResponder(in: outgoingView, container: container)
                outgoingView.removeFromSuperview()
            }

            if identityChanged,
               let replacedView = hostingViews.removeValue(
                    forKey: selectedTab
                )
            {
                replacedView.removeFromSuperview()
            }

            let incomingView: NSHostingView<AnyView>
            let requiresInitialLayout: Bool
            if let cachedView = hostingViews[selectedTab] {
                incomingView = cachedView
                requiresInitialLayout = false
                apply(targetAppearance, to: incomingView)
                incomingView.rootView = contentForTab(selectedTab, true)
            } else {
                incomingView = NSHostingView(
                    rootView: contentForTab(selectedTab, true)
                )
                incomingView.appearance = targetAppearance
                incomingView.translatesAutoresizingMaskIntoConstraints = true
                incomingView.autoresizingMask = [.width, .height]
                incomingView.sizingOptions = []
                hostingViews[selectedTab] = incomingView
                requiresInitialLayout = true
            }
            if let contentIdentity {
                contentIdentities[selectedTab] = contentIdentity
            }

            incomingView.frame = container.bounds
            container.addSubview(incomingView)
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
            if let contentForTab = latestContentProvider {
                for (tab, hostingView) in hostingViews {
                    hostingView.rootView = contentForTab(tab, false)
                }
            }
            container.window?.makeFirstResponder(nil)
            container.subviews.forEach { $0.removeFromSuperview() }
            hostingViews.removeAll()
            contentIdentities.removeAll()
            activeTab = nil
            latestContentProvider = nil
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
