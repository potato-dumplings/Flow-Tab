import AppKit
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testHomeRetainedTabHostMountsOnlySelectedPageAndReusesHosts() {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        XCTAssertEqual(container.subviews.count, 1)
        let homeHost = container.subviews[0]
        let initialAddCount = container.addCount
        let initialRemoveCount = container.removeCount

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        XCTAssertTrue(container.subviews[0] === homeHost)
        XCTAssertEqual(container.addCount, initialAddCount)
        XCTAssertEqual(container.removeCount, initialRemoveCount)

        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        XCTAssertEqual(container.subviews.count, 1)
        XCTAssertFalse(container.subviews[0] === homeHost)

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        XCTAssertEqual(container.subviews.count, 1)
        XCTAssertTrue(container.subviews[0] === homeHost)
    }

    @MainActor
    func testHomeRetainedTabHostDeactivatesOutgoingPageBeforeMountingIncoming() {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )

        XCTAssertEqual(
            Array(recorder.providerCalls.suffix(2)),
            [
                HomeRetainedTabProviderCall(tab: .home, isActive: false),
                HomeRetainedTabProviderCall(tab: .logs, isActive: true)
            ]
        )
    }

    @MainActor
    func testHomeRetainedTabHostClearsOutgoingFirstResponder() throws {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        let homeResponder = try XCTUnwrap(recorder.probeViews[.home])
        XCTAssertTrue(window.makeFirstResponder(homeResponder))
        XCTAssertTrue(window.firstResponder === homeResponder)

        coordinator.present(
            selectedTab: .settings,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)

        XCTAssertFalse(window.firstResponder === homeResponder)
    }

    @MainActor
    func testHomeRetainedTabHostPreservesSwiftUIStateAcrossRoundTrip() throws {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        let initialIdentity = try XCTUnwrap(
            recorder.stateIdentities[.home]?.last
        )

        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)

        XCTAssertEqual(
            recorder.stateIdentities[.home]?.last,
            initialIdentity
        )
    }

    @MainActor
    func testHomeRetainedTabHostUpdatesAppearanceWithoutRemounting() throws {
        let aqua = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAqua = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        coordinator.present(
            selectedTab: .settings,
            targetAppearance: aqua,
            contentIdentity: "settings-stable",
            contentForTab: content,
            in: container
        )
        let initialHost = try XCTUnwrap(container.subviews.first)
        let initialAddCount = container.addCount

        coordinator.present(
            selectedTab: .settings,
            targetAppearance: darkAqua,
            contentIdentity: "settings-stable",
            contentForTab: content,
            in: container
        )

        XCTAssertTrue(container.subviews.first === initialHost)
        XCTAssertEqual(container.addCount, initialAddCount)
        XCTAssertEqual(initialHost.appearance?.name, .darkAqua)
    }

    @MainActor
    func testHomeRetainedTabHostReplacesOnlyChangedContentIdentity() throws {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        coordinator.present(
            selectedTab: .settings,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "settings-light",
            contentForTab: content,
            in: container
        )
        let initialHost = try XCTUnwrap(container.subviews.first)
        let initialAddCount = container.addCount
        let initialRemoveCount = container.removeCount

        coordinator.present(
            selectedTab: .settings,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "settings-dark",
            contentForTab: content,
            in: container
        )

        XCTAssertFalse(container.subviews.first === initialHost)
        XCTAssertEqual(container.addCount, initialAddCount + 1)
        XCTAssertEqual(container.removeCount, initialRemoveCount + 1)
        XCTAssertEqual(
            Array(recorder.providerCalls.suffix(2)),
            [
                HomeRetainedTabProviderCall(
                    tab: .settings,
                    isActive: false
                ),
                HomeRetainedTabProviderCall(
                    tab: .settings,
                    isActive: true
                )
            ]
        )
    }

    @MainActor
    func testHomeRetainedTabHostDismantleDeactivatesAndReleasesCachedHosts() {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        let homeHost = container.subviews[0]
        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        coordinator.dismantle(from: container)

        XCTAssertTrue(container.subviews.isEmpty)
        let dismantleCalls = Set(recorder.providerCalls.suffix(2))
        XCTAssertEqual(
            dismantleCalls,
            Set([
                HomeRetainedTabProviderCall(tab: .home, isActive: false),
                HomeRetainedTabProviderCall(tab: .logs, isActive: false)
            ])
        )

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        XCTAssertFalse(container.subviews[0] === homeHost)
    }

    @MainActor
    private func makeHomeRetainedTabProbeContent(
        recorder: HomeRetainedTabProbeRecorder
    ) -> HomeRetainedTabContentHost.ContentProvider {
        { tab, isActive in
            recorder.providerCalls.append(
                HomeRetainedTabProviderCall(
                    tab: tab,
                    isActive: isActive
                )
            )
            return AnyView(
                HomeRetainedTabStateProbeView(
                    tab: tab,
                    isActive: isActive,
                    recorder: recorder
                )
            )
        }
    }

    @MainActor
    private func settleHomeRetainedTabHost(_ container: NSView) {
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        container.subviews.forEach {
            $0.needsLayout = true
            $0.layoutSubtreeIfNeeded()
        }
    }
}

private struct HomeRetainedTabProviderCall: Hashable {
    let tab: HomeTab
    let isActive: Bool
}

@MainActor
private final class HomeRetainedTabProbeRecorder {
    var providerCalls: [HomeRetainedTabProviderCall] = []
    var stateIdentities: [HomeTab: [UUID]] = [:]
    var probeViews: [HomeTab: NSView] = [:]
}

private struct HomeRetainedTabStateProbeView: View {
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

private struct HomeRetainedTabStateProbeRepresentable: NSViewRepresentable {
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

private final class HomeRetainedTabResponderProbeView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private final class HomeRetainedTabTrackingContainerView: NSView {
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
