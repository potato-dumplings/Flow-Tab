import CoreGraphics
import Foundation
import FlowTabCore

struct RuntimeReadModelGeneration: Equatable {
    var appLifecycle: UInt64 = 0
    var cg: UInt64 = 0
    var space: UInt64 = 0
    var axDirty: UInt64 = 0
    var projection: UInt64 = 0
}

struct RuntimeProjectionFreshness: Equatable {
    let generatedAt: TimeInterval
    let sourceGeneration: RuntimeReadModelGeneration
    let dirtyAppIDs: Set<String>
    let dirtyPIDs: Set<pid_t>
    let dirtyCGWindowIDs: Set<CGWindowID>
    let spaceTopologySignatureSummary: String?
    let pendingRepairScopes: Set<String>
    let isCompleteForScope: Bool

    init(
        generatedAt: TimeInterval,
        sourceGeneration: RuntimeReadModelGeneration,
        dirtyAppIDs: Set<String>,
        dirtyPIDs: Set<pid_t>,
        dirtyCGWindowIDs: Set<CGWindowID>,
        spaceTopologySignatureSummary: String? = nil,
        pendingRepairScopes: Set<String>,
        isCompleteForScope: Bool
    ) {
        self.generatedAt = generatedAt
        self.sourceGeneration = sourceGeneration
        self.dirtyAppIDs = dirtyAppIDs
        self.dirtyPIDs = dirtyPIDs
        self.dirtyCGWindowIDs = dirtyCGWindowIDs
        self.spaceTopologySignatureSummary = spaceTopologySignatureSummary
        self.pendingRepairScopes = pendingRepairScopes
        self.isCompleteForScope = isCompleteForScope
    }

    var isDirty: Bool {
        !dirtyAppIDs.isEmpty
            || !dirtyPIDs.isEmpty
            || !dirtyCGWindowIDs.isEmpty
            || !pendingRepairScopes.isEmpty
    }
}

struct RuntimeAppSwitcherProjection {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
    var freshness: RuntimeProjectionFreshness

    var appCycleApps: [AppSwitchCandidate] {
        guard !freshness.isCompleteForScope else { return apps }
        let suppressesAllWindowLists = !freshness.dirtyCGWindowIDs.isEmpty
            || (!freshness.pendingRepairScopes.isEmpty && freshness.dirtyAppIDs.isEmpty)
        return apps.map { app -> AppSwitchCandidate in
            guard suppressesAllWindowLists || freshness.dirtyAppIDs.contains(app.id) else {
                return app
            }
            var app = app
            app.windows = []
            return app
        }
    }
}

struct RuntimeHomeSummaryProjection {
    let summaries: [RuntimeHomeAppSummary]
    var freshness: RuntimeProjectionFreshness

    func summary(for appID: String) -> RuntimeHomeAppSummary? {
        summaries.first { $0.appID == appID }
    }
}

struct RuntimeHomeAppDetailProjection {
    let summary: RuntimeHomeAppSummary
    let candidate: AppSwitchCandidate
    let context: RuntimeAppContext
    var freshness: RuntimeProjectionFreshness

    init(
        summary: RuntimeHomeAppSummary,
        candidate: AppSwitchCandidate,
        context: RuntimeAppContext,
        freshness: RuntimeProjectionFreshness
    ) {
        self.summary = summary
        self.candidate = candidate
        self.context = context
        self.freshness = freshness
    }

    init(
        currentAppWindowPayload payload: RuntimeCurrentAppWindowPayload,
        freshness: RuntimeProjectionFreshness
    ) {
        self.init(
            summary: payload.summary,
            candidate: payload.candidate,
            context: payload.context,
            freshness: freshness
        )
    }
}

struct RuntimeAppDirectoryProjection {
    let entries: [RuntimeAppDirectoryEntry]
    var freshness: RuntimeProjectionFreshness

    func entries(forAppID appID: String) -> [RuntimeAppDirectoryEntry] {
        entries.filter { $0.appID == appID }
    }
}

struct RuntimeSpaceTopologyProjection {
    let signature: RuntimeSpaceTopologySignature
    let affectedCGWindowIDs: Set<CGWindowID>
    var freshness: RuntimeProjectionFreshness
}

struct RuntimeActivationTargetProjection: Equatable {
    let appID: String
    let windowID: String
    let ownerPID: pid_t
    let targetCGWindowID: CGWindowID?
    let focusedCGWindowID: CGWindowID?
    let affectedCGWindowIDs: Set<CGWindowID>
    let title: String
    let frame: CGRect?
    let allowedActions: Set<WindowBindingAction>
    var freshness: RuntimeProjectionFreshness

    init(
        verification: RuntimeWindowFocusVerification,
        affectedCGWindowIDs: Set<CGWindowID>,
        freshness: RuntimeProjectionFreshness
    ) {
        appID = verification.appID
        windowID = verification.windowID
        ownerPID = verification.ownerPID
        targetCGWindowID = verification.targetCGWindowID
        focusedCGWindowID = verification.focusedCGWindowID
        self.affectedCGWindowIDs = affectedCGWindowIDs
        title = verification.title
        frame = verification.frame
        allowedActions = verification.allowedActions
        self.freshness = freshness
    }
}

struct RuntimeCurrentAppWindowProjection {
    let appID: String
    let currentAppWindowPayload: RuntimeCurrentAppWindowPayload
    var freshness: RuntimeProjectionFreshness

    init(
        appID: String,
        currentAppWindowPayload: RuntimeCurrentAppWindowPayload,
        freshness: RuntimeProjectionFreshness
    ) {
        self.appID = appID
        self.currentAppWindowPayload = currentAppWindowPayload
        self.freshness = freshness
    }
}

struct RuntimeFocusedCurrentAppWindowProjectionRead {
    let appID: String
    let pid: pid_t
    let projection: RuntimeCurrentAppWindowProjection?
}

struct RuntimeReadModelDiagnostics: Equatable {
    let generation: RuntimeReadModelGeneration
    let dirtyAppIDs: Set<String>
    let dirtyPIDs: Set<pid_t>
    let dirtyCGWindowIDs: Set<CGWindowID>
    let spaceTopologySignatureSummary: String?
    let pendingRepairScopes: Set<String>
    let hasAppSwitcherProjection: Bool
    let hasHomeSummaryProjection: Bool
    let hasCompleteAppSwitcherProjection: Bool
    let hasCompleteHomeSummaryProjection: Bool
    let hasAppDirectoryProjection: Bool
    let hasCompleteAppDirectoryProjection: Bool
    let hasSpaceTopologyProjection: Bool
    let spaceTopologyTrackedSpaceCount: Int
    let spaceTopologyTrackedWindowCount: Int
    let spaceTopologyFullscreenWindowCount: Int
    let hasActivationTargetProjection: Bool
    let hasCommittedSearchIndex: Bool
    let currentAppWindowProjectionAppIDs: Set<String>
    let appDirectoryEntryPIDs: Set<pid_t>

    var hasDirtyState: Bool {
        !dirtyAppIDs.isEmpty
            || !dirtyPIDs.isEmpty
            || !dirtyCGWindowIDs.isEmpty
            || !pendingRepairScopes.isEmpty
    }
}

struct RuntimeAppSwitcherProjectionCommitSummary {
    var coldStartCommittedCount = 0
    var degradedCommittedCount = 0
}
