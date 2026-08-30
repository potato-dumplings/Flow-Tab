import AppKit
import SwiftUI
@testable import FlowTab

@MainActor
extension HomeRetainedTabContentHost.Coordinator {
    func present(
        selectedTab: HomeTab,
        targetAppearance: NSAppearance,
        contentIdentity: AnyHashable? = nil,
        contentRevision: AnyHashable = AnyHashable(0),
        contentForTab: @escaping HomeRetainedTabContentHost.ContentProvider,
        in container: NSView
    ) {
        present(
            selectedTab: selectedTab,
            targetAppearance: targetAppearance,
            descriptor: HomeRetainedTabPageDescriptor(
                identity: contentIdentity ?? AnyHashable(selectedTab),
                contentRevision: contentRevision
            ),
            contentForTab: contentForTab,
            in: container
        )
    }
}

struct HomeRetainedTabProviderCall: Hashable {
    let tab: HomeTab
    let isActive: Bool
}

@MainActor
final class HomeRetainedTabProbeRecorder {
    var providerCalls: [HomeRetainedTabProviderCall] = []
    var stateIdentities: [HomeTab: [UUID]] = [:]
    var probeViews: [HomeTab: NSView] = [:]
}

struct HomeRetainedTabStateProbeView: View {
    let tab: HomeTab
    let isActive: Bool
    let recorder: HomeRetainedTabProbeRecorder
    @State private var stateIdentity = UUID()

    var body: some View {
        HomeRetainedTabStateProbeRepresentable(
            tab: tab,
            isActive: isActive,
            stateIdentity: stateIdentity,
            recorder: recorder
        )
    }
}

struct HomeRetainedTabStateProbeRepresentable: NSViewRepresentable {
    let tab: HomeTab
    let isActive: Bool
    let stateIdentity: UUID
    let recorder: HomeRetainedTabProbeRecorder

    func makeNSView(context: Context) -> HomeRetainedTabResponderProbeView {
        HomeRetainedTabResponderProbeView()
    }

    func updateNSView(
        _ nsView: HomeRetainedTabResponderProbeView,
        context: Context
    ) {
        recorder.probeViews[tab] = nsView
        recorder.stateIdentities[tab, default: []].append(stateIdentity)
    }
}

final class HomeRetainedTabResponderProbeView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

final class HomeRetainedTabTrackingContainerView: NSView {
    private(set) var addCount = 0
    private(set) var removeCount = 0

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        addCount += 1
    }

    override func willRemoveSubview(_ subview: NSView) {
        removeCount += 1
        super.willRemoveSubview(subview)
    }
}
