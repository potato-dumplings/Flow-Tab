import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension SessionMode {
    var debugName: String {
        switch self {
        case .appCycle:
            return "appCycle"
        case .groupCycle:
            return "groupCycle"
        case .windowCycle(let appID):
            return "windowCycle(\(appID))"
        }
    }
}

extension KeyInput {
    var debugName: String {
        switch self {
        case .tabForward:
            return "tabForward"
        case .tabBackward:
            return "tabBackward"
        case .upArrow:
            return "upArrow"
        case .downArrow:
            return "downArrow"
        case .leftArrow:
            return "leftArrow"
        case .rightArrow:
            return "rightArrow"
        }
    }
}

extension CycleDirection {
    var debugName: String {
        switch self {
        case .forward:
            return "forward"
        case .backward:
            return "backward"
        }
    }
}

enum SwitcherOverlayStyle {
    case appAndWindow
    case windowOnly

    var debugName: String {
        switch self {
        case .appAndWindow:
            return "appAndWindow"
        case .windowOnly:
            return "windowOnly"
        }
    }

    var contentTraceKind: String {
        switch self {
        case .appAndWindow:
            return "global"
        case .windowOnly:
            return "inApp"
        }
    }
}

enum SwitcherRenderMilestone: String, Equatable {
    case appContent
    case windowContent
    case searchShell
    case searchFirstRow
}

struct SwitcherRenderMilestoneEvent: Equatable {
    let milestone: SwitcherRenderMilestone
    let renderGeneration: UInt64
    let drawnAtMilliseconds: Double
}

struct SwitcherRenderMilestoneDisplayEvidence: Equatable {
    let milestone: SwitcherRenderMilestone
    let renderGeneration: UInt64
    let durationMilliseconds: Double
    let completedAtMilliseconds: Double
}

struct SwitcherRenderMilestonePreparation {
    let milestone: SwitcherRenderMilestone
    let renderGeneration: UInt64
    private let displayAction:
        () -> SwitcherRenderMilestoneDisplayEvidence?

    init(
        milestone: SwitcherRenderMilestone,
        renderGeneration: UInt64,
        displayAction:
            @escaping () -> SwitcherRenderMilestoneDisplayEvidence?
    ) {
        self.milestone = milestone
        self.renderGeneration = renderGeneration
        self.displayAction = displayAction
    }

    func displayPreparedRegion()
        -> SwitcherRenderMilestoneDisplayEvidence?
    {
        displayAction()
    }
}

private final class SwitcherRenderMilestoneNSView: NSView {
    var milestone: SwitcherRenderMilestone = .appContent
    var renderGeneration: UInt64 = 0
    var onDraw: ((SwitcherRenderMilestoneEvent) -> Void)?
    var onPreparation:
        ((SwitcherRenderMilestonePreparation) -> Void)?
    private var deliveredToken: String?
    private var deliveredPreparationToken: String?

    override var isOpaque: Bool { false }

    func publishPreparationIfNeeded() {
        let token = renderToken
        guard deliveredPreparationToken != token,
              let onPreparation
        else {
            return
        }
        deliveredPreparationToken = token
        let expectedMilestone = milestone
        let expectedRenderGeneration = renderGeneration
        onPreparation(
            SwitcherRenderMilestonePreparation(
                milestone: expectedMilestone,
                renderGeneration: expectedRenderGeneration,
                displayAction: { [weak self] in
                    self?.displayPreparedRegion(
                        expectedMilestone: expectedMilestone,
                        expectedRenderGeneration:
                            expectedRenderGeneration
                    )
                }
            )
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.isVisible == true else { return }
        let token = renderToken
        guard deliveredToken != token else { return }
        deliveredToken = token
        let event = SwitcherRenderMilestoneEvent(
            milestone: milestone,
            renderGeneration: renderGeneration,
            drawnAtMilliseconds:
                ProcessInfo.processInfo.systemUptime * 1_000
        )
        DispatchQueue.main.async { [weak self] in
            self?.onDraw?(event)
        }
    }

    private var renderToken: String {
        "\(milestone.rawValue):\(renderGeneration)"
    }

    private func displayPreparedRegion(
        expectedMilestone: SwitcherRenderMilestone,
        expectedRenderGeneration: UInt64
    ) -> SwitcherRenderMilestoneDisplayEvidence? {
        guard milestone == expectedMilestone,
              renderGeneration == expectedRenderGeneration,
              let window,
              window.isVisible,
              let contentView = window.contentView,
              isDescendant(of: contentView)
        else {
            return nil
        }

        let startedAtMilliseconds =
            ProcessInfo.processInfo.systemUptime * 1_000
        needsDisplay = true
        contentView.layoutSubtreeIfNeeded()
        let appStripRect = convert(bounds, to: contentView)
            .integral
            .intersection(contentView.bounds)
        guard !appStripRect.isEmpty else { return nil }
        deliveredToken = nil
        contentView.displayIgnoringOpacity(appStripRect)
        let completedAtMilliseconds =
            ProcessInfo.processInfo.systemUptime * 1_000
        return SwitcherRenderMilestoneDisplayEvidence(
            milestone: expectedMilestone,
            renderGeneration: expectedRenderGeneration,
            durationMilliseconds:
                completedAtMilliseconds - startedAtMilliseconds,
            completedAtMilliseconds: completedAtMilliseconds
        )
    }
}

struct SwitcherRenderMilestoneProbe: NSViewRepresentable {
    let milestone: SwitcherRenderMilestone
    let renderGeneration: UInt64
    let onPreparation:
        ((SwitcherRenderMilestonePreparation) -> Void)?
    let onDraw: (SwitcherRenderMilestoneEvent) -> Void

    init(
        milestone: SwitcherRenderMilestone,
        renderGeneration: UInt64,
        onPreparation:
            ((SwitcherRenderMilestonePreparation) -> Void)? = nil,
        onDraw: @escaping (SwitcherRenderMilestoneEvent) -> Void
    ) {
        self.milestone = milestone
        self.renderGeneration = renderGeneration
        self.onPreparation = onPreparation
        self.onDraw = onDraw
    }

    func makeNSView(context: Context) -> NSView {
        let view = SwitcherRenderMilestoneNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? SwitcherRenderMilestoneNSView else {
            return
        }
        configure(view)
        view.needsDisplay = true
    }

    private func configure(_ view: SwitcherRenderMilestoneNSView) {
        view.milestone = milestone
        view.renderGeneration = renderGeneration
        view.onPreparation = onPreparation
        view.onDraw = onDraw
        view.publishPreparationIfNeeded()
    }
}

struct WindowPreviewItem: Identifiable {
    let id: String
    let title: String
    let image: NSImage?
    let titleBarStyle: WindowTitleBarStyleGuess?
    let isSelected: Bool
}

struct WindowPreviewPageSummary {
    let itemCount: Int
    let selectedIndex: Int?
}

struct SearchAppResultItem: Identifiable {
    let id: String
    let app: AppSwitchCandidate
    let isSelected: Bool
}

struct SearchWindowResultItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let icon: NSImage?
    let isSelected: Bool
}

struct SearchHeaderHighlightItem {
    let title: String
    let icon: NSImage?
}

struct SwitcherAppRenderItem: Identifiable {
    let id: String
    let displayName: String
    let icon: NSImage?
    let windowCount: Int
}

struct SwitcherAppLayerRenderSnapshot {
    let generation: UInt64
    let items: [SwitcherAppRenderItem]
    let selectedAppID: String
    let listChange: SwitcherAppListChange
}

extension LiveSwitcherModel {
    func updateAppLayerRenderSnapshot(
        from session: SwitcherSession,
        previousSession: SwitcherSession?
    ) {
        if overlayStyle == .windowOnly,
           appLayerRenderSnapshot != nil {
            return
        }
        let previousItemsByID = Dictionary(
            uniqueKeysWithValues:
                (appLayerRenderSnapshot?.items ?? []).map {
                    ($0.id, $0)
                }
        )
        let items = session.apps.map { app in
            let previous = previousItemsByID[app.id]
            let icon: NSImage?
            if let previous,
               previous.displayName == app.displayName {
                icon = previous.icon
            } else {
                icon = self.icon(for: app)
            }
            return SwitcherAppRenderItem(
                id: app.id,
                displayName: app.displayName,
                icon: icon,
                windowCount: app.windows.count
            )
        }
        let candidate = SwitcherAppLayerRenderSnapshot(
            generation:
                (appLayerRenderSnapshot?.generation ?? 0) &+ 1,
            items: items,
            selectedAppID: session.selectedApp.id,
            listChange: SwitcherAppListChange.classify(
                previousAppIDs: previousSession?.apps.map(\.id),
                currentAppIDs: session.apps.map(\.id)
            )
        )
        appLayerRenderSnapshot = candidate
    }
}

struct AppSwitcherProjectionSessionPayload {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]

    var windowCount: Int {
        apps.reduce(0) { $0 + $1.windows.count }
    }

    init(apps: [AppSwitchCandidate], contextsByID: [String: RuntimeAppContext]) {
        self.apps = apps
        self.contextsByID = contextsByID
    }

    init(projection: RuntimeAppSwitcherProjection) {
        self.init(
            apps: projection.appCycleApps,
            contextsByID: projection.contextsByID
        )
    }

    func applyingAppOrder(_ orderedAppIDs: [String]) -> Self {
        guard apps.count > 1, !orderedAppIDs.isEmpty else { return self }

        var rankByAppID: [String: Int] = [:]
        for (rank, appID) in orderedAppIDs.enumerated()
        where rankByAppID[appID] == nil {
            rankByAppID[appID] = rank
        }
        let originalRankByAppID = Dictionary(
            uniqueKeysWithValues: apps.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        let reorderedApps = apps.sorted { lhs, rhs in
            let lhsRank = rankByAppID[lhs.id] ?? Int.max
            let rhsRank = rankByAppID[rhs.id] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return (originalRankByAppID[lhs.id] ?? Int.max)
                < (originalRankByAppID[rhs.id] ?? Int.max)
        }
        guard reorderedApps.map(\.id) != apps.map(\.id) else { return self }
        return Self(
            apps: reorderedApps,
            contextsByID: contextsByID
        )
    }
}
