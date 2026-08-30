import AppKit
import Combine
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testHomeRetainedTabHostKeepsVisitedPagesAttachedAndReusesHosts() {
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
        XCTAssertEqual(container.subviews.count, 1)
        let homeHost = container.subviews[0]
        XCTAssertFalse(homeHost.isHidden)
        XCTAssertTrue(homeHost.window === window)
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
        XCTAssertEqual(container.subviews.count, 2)
        let logsHost = container.subviews[1]
        XCTAssertTrue(homeHost.isHidden)
        XCTAssertFalse(logsHost.isHidden)
        XCTAssertTrue(logsHost.window === window)

        coordinator.present(
            selectedTab: .settings,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        XCTAssertEqual(container.subviews.count, 3)
        let settingsHost = container.subviews[2]
        XCTAssertTrue(homeHost.isHidden)
        XCTAssertTrue(logsHost.isHidden)
        XCTAssertFalse(settingsHost.isHidden)
        XCTAssertTrue(settingsHost.window === window)
        let warmAddCount = container.addCount
        let warmRemoveCount = container.removeCount

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)
        XCTAssertEqual(container.subviews.count, 3)
        XCTAssertFalse(homeHost.isHidden)
        XCTAssertTrue(logsHost.isHidden)
        XCTAssertTrue(settingsHost.isHidden)
        XCTAssertNotNil(homeHost.hitTest(NSPoint(x: 10, y: 10)))
        XCTAssertNil(logsHost.hitTest(NSPoint(x: 10, y: 10)))
        XCTAssertNil(settingsHost.hitTest(NSPoint(x: 10, y: 10)))
        XCTAssertEqual(container.addCount, warmAddCount)
        XCTAssertEqual(container.removeCount, warmRemoveCount)
        XCTAssertTrue(homeHost.window === window)
        XCTAssertTrue(logsHost.window === window)
        XCTAssertTrue(settingsHost.window === window)
    }

    @MainActor
    func testHomeRetainedTabHostTracksContainerBoundsWithoutConstraints() {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: recorder
            ),
            in: container
        )
        settleHomeRetainedTabHost(container)
        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: recorder
            ),
            in: container
        )
        coordinator.present(
            selectedTab: .settings,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: recorder
            ),
            in: container
        )
        settleHomeRetainedTabHost(container)

        XCTAssertEqual(container.subviews.count, 3)
        XCTAssertTrue(container.subviews.allSatisfy(
            \.translatesAutoresizingMaskIntoConstraints
        ))
        XCTAssertTrue(container.constraints.isEmpty)
        XCTAssertTrue(container.subviews.allSatisfy {
            $0.frame == container.bounds
        })

        container.setFrameSize(NSSize(width: 960, height: 720))
        settleHomeRetainedTabHost(container)

        XCTAssertTrue(container.subviews.allSatisfy {
            $0.frame == container.bounds
        })
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
        settleHomeRetainedTabHost(container)

        let homeHost = container.subviews[0]
            as? NSHostingView<HomeRetainedTabPageRoot>
        let logsHost = container.subviews[1]
            as? NSHostingView<HomeRetainedTabPageRoot>

        XCTAssertEqual(
            homeHost?.rootView.presentation.lifecycle.state,
            .inactive
        )
        XCTAssertEqual(
            logsHost?.rootView.presentation.lifecycle.state,
            .active
        )
        XCTAssertTrue(homeHost?.isHidden == true)
        XCTAssertTrue(logsHost?.isHidden == false)
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
        let initialProbeView = try XCTUnwrap(recorder.probeViews[.home])

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
        XCTAssertTrue(recorder.probeViews[.home] === initialProbeView)
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
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "home",
            contentForTab: content,
            in: container
        )
        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "logs",
            contentForTab: content,
            in: container
        )
        coordinator.present(
            selectedTab: .settings,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "settings-light",
            contentForTab: content,
            in: container
        )
        let homeHost = container.subviews[0]
        let logsHost = container.subviews[1]
        let initialHost = try XCTUnwrap(
            container.subviews.last
                as? NSHostingView<HomeRetainedTabPageRoot>
        )
        let initialPresentation = initialHost.rootView.presentation
        let initialAddCount = container.addCount
        let initialRemoveCount = container.removeCount

        coordinator.present(
            selectedTab: .settings,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "settings-dark",
            contentForTab: content,
            in: container
        )

        let replacementHost = try XCTUnwrap(
            container.subviews.last
                as? NSHostingView<HomeRetainedTabPageRoot>
        )
        XCTAssertEqual(container.subviews.count, 3)
        XCTAssertTrue(container.subviews[0] === homeHost)
        XCTAssertTrue(container.subviews[1] === logsHost)
        XCTAssertFalse(replacementHost === initialHost)
        XCTAssertEqual(container.addCount, initialAddCount + 1)
        XCTAssertEqual(container.removeCount, initialRemoveCount + 1)
        XCTAssertEqual(initialPresentation.lifecycle.state, .inactive)
        XCTAssertEqual(
            replacementHost.rootView.presentation.lifecycle.state,
            .active
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
            as? NSHostingView<HomeRetainedTabPageRoot>
        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentForTab: content,
            in: container
        )
        coordinator.dismantle(from: container)

        XCTAssertTrue(container.subviews.isEmpty)
        XCTAssertEqual(
            homeHost?.rootView.presentation.lifecycle.state,
            .inactive
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
    func testHomeRetainedTabHostKeepsStableRootAndGuardsEquivalentRevision() throws {
        let initialRecorder = HomeRetainedTabProbeRecorder()
        let ignoredRecorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "home",
            contentRevision: "revision-1",
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: initialRecorder
            ),
            in: container
        )
        settleHomeRetainedTabHost(container)
        let hostingView = try XCTUnwrap(
            container.subviews.first
                as? NSHostingView<HomeRetainedTabPageRoot>
        )
        let presentation = hostingView.rootView.presentation
        var observedSnapshots: [
            HomeRetainedTabPagePresentation.Snapshot
        ] = []
        let observation = presentation.$snapshot
            .dropFirst()
            .sink { observedSnapshots.append($0) }
        defer { observation.cancel() }

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "home",
            contentRevision: "revision-1",
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: ignoredRecorder
            ),
            in: container
        )
        settleHomeRetainedTabHost(container)

        XCTAssertTrue(container.subviews.first === hostingView)
        XCTAssertTrue(hostingView.rootView.presentation === presentation)
        XCTAssertTrue(observedSnapshots.isEmpty)
        XCTAssertTrue(ignoredRecorder.providerCalls.isEmpty)

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "home",
            contentRevision: "revision-2",
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: ignoredRecorder
            ),
            in: container
        )
        settleHomeRetainedTabHost(container)

        XCTAssertTrue(container.subviews.first === hostingView)
        XCTAssertTrue(hostingView.rootView.presentation === presentation)
        XCTAssertEqual(
            observedSnapshots,
            [
                .init(contentRevision: "revision-2")
            ]
        )
        XCTAssertEqual(
            ignoredRecorder.providerCalls.last,
            HomeRetainedTabProviderCall(tab: .home, isActive: true)
        )
    }

    @MainActor
    func testHomeRetainedTabHostStableSwitchesDoNotPublishContentOrReinvokeProviders() throws {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        for tab in [HomeTab.home, .logs, .settings] {
            coordinator.present(
                selectedTab: tab,
                targetAppearance: NSApp.effectiveAppearance,
                contentIdentity: AnyHashable(tab),
                contentRevision: "stable-revision",
                contentForTab: content,
                in: container
            )
            settleHomeRetainedTabHost(container)
        }

        let presentations = try container.subviews.map {
            try XCTUnwrap(
                ($0 as? NSHostingView<HomeRetainedTabPageRoot>)?
                    .rootView.presentation
            )
        }
        var publicationCount = 0
        let observations = presentations.map { presentation in
            presentation.$snapshot
                .dropFirst()
                .sink { _ in publicationCount += 1 }
        }
        defer { observations.forEach { $0.cancel() } }
        recorder.providerCalls.removeAll()

        for tab in [HomeTab.home, .logs, .settings, .home] {
            coordinator.present(
                selectedTab: tab,
                targetAppearance: NSApp.effectiveAppearance,
                contentIdentity: AnyHashable(tab),
                contentRevision: "stable-revision",
                contentForTab: content,
                in: container
            )
            settleHomeRetainedTabHost(container)
        }

        XCTAssertEqual(publicationCount, 0)
        XCTAssertTrue(recorder.providerCalls.isEmpty)
    }

    @MainActor
    func testHomeRetainedTabHostEmitsOnlyOrderedLifecycleTransitions() throws {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        for tab in [HomeTab.home, .logs, .settings] {
            coordinator.present(
                selectedTab: tab,
                targetAppearance: NSApp.effectiveAppearance,
                contentIdentity: AnyHashable(tab),
                contentRevision: "stable-revision",
                contentForTab: content,
                in: container
            )
        }
        let presentations = try container.subviews.map {
            try XCTUnwrap(
                ($0 as? NSHostingView<HomeRetainedTabPageRoot>)?
                    .rootView.presentation
            )
        }
        var events: [String] = []
        let observations = presentations.map { presentation in
            presentation.lifecycle.transitions.sink { state in
                events.append(
                    "\(presentation.tab):\(state)"
                )
            }
        }
        defer { observations.forEach { $0.cancel() } }

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: AnyHashable(HomeTab.home),
            contentRevision: "stable-revision",
            contentForTab: content,
            in: container
        )
        XCTAssertEqual(events, ["settings:inactive", "home:active"])

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: AnyHashable(HomeTab.home),
            contentRevision: "stable-revision",
            contentForTab: content,
            in: container
        )
        XCTAssertEqual(events, ["settings:inactive", "home:active"])

        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: AnyHashable(HomeTab.logs),
            contentRevision: "stable-revision",
            contentForTab: content,
            in: container
        )
        XCTAssertEqual(
            events,
            [
                "settings:inactive",
                "home:active",
                "home:inactive",
                "logs:active"
            ]
        )
    }

    @MainActor
    func testHomeRetainedTabHostUsesLatestProviderWhenHiddenPageReturns() {
        let initialRecorder = HomeRetainedTabProbeRecorder()
        let latestRecorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "home",
            contentRevision: "home-1",
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: initialRecorder
            ),
            in: container
        )
        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "logs",
            contentRevision: "logs-1",
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: initialRecorder
            ),
            in: container
        )
        settleHomeRetainedTabHost(container)

        coordinator.present(
            selectedTab: .logs,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "logs",
            contentRevision: "logs-1",
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: latestRecorder
            ),
            in: container
        )
        XCTAssertTrue(latestRecorder.providerCalls.isEmpty)

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: "home",
            contentRevision: "home-2",
            contentForTab: makeHomeRetainedTabProbeContent(
                recorder: latestRecorder
            ),
            in: container
        )
        settleHomeRetainedTabHost(container)

        XCTAssertTrue(
            latestRecorder.providerCalls.contains(
                HomeRetainedTabProviderCall(
                    tab: .home,
                    isActive: true
                )
            )
        )
    }

    @MainActor
    func testHomeRetainedTabHostPublishesContentRevisionOnlyToTargetPage() throws {
        let recorder = HomeRetainedTabProbeRecorder()
        let coordinator = HomeRetainedTabContentHost.Coordinator()
        let container = HomeRetainedTabTrackingContainerView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let content = makeHomeRetainedTabProbeContent(recorder: recorder)

        for tab in [HomeTab.home, .logs, .settings] {
            coordinator.present(
                selectedTab: tab,
                targetAppearance: NSApp.effectiveAppearance,
                contentIdentity: AnyHashable(tab),
                contentRevision: "revision-1",
                contentForTab: content,
                in: container
            )
        }
        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: AnyHashable(HomeTab.home),
            contentRevision: "revision-1",
            contentForTab: content,
            in: container
        )
        settleHomeRetainedTabHost(container)

        let hosts = try container.subviews.map {
            try XCTUnwrap(
                $0 as? NSHostingView<HomeRetainedTabPageRoot>
            )
        }
        var snapshotsByTab: [
            HomeTab: [HomeRetainedTabPagePresentation.Snapshot]
        ] = [:]
        let observations = hosts.map { host in
            host.rootView.presentation.$snapshot
                .dropFirst()
                .sink { snapshot in
                    snapshotsByTab[
                        host.rootView.presentation.tab,
                        default: []
                    ].append(snapshot)
                }
        }
        defer { observations.forEach { $0.cancel() } }

        coordinator.present(
            selectedTab: .home,
            targetAppearance: NSApp.effectiveAppearance,
            contentIdentity: AnyHashable(HomeTab.home),
            contentRevision: "revision-2",
            contentForTab: content,
            in: container
        )

        XCTAssertEqual(
            snapshotsByTab[.home],
            [
                .init(contentRevision: "revision-2")
            ]
        )
        XCTAssertNil(snapshotsByTab[.logs])
        XCTAssertNil(snapshotsByTab[.settings])
    }

    @MainActor
    private func makeHomeRetainedTabProbeContent(
        recorder: HomeRetainedTabProbeRecorder
    ) -> HomeRetainedTabContentHost.ContentProvider {
        { tab, lifecycle in
            let isActive = lifecycle.state == .active
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
