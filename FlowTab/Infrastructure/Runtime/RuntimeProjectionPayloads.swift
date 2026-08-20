import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import FlowTabCore

struct RuntimeAppSwitcherProjectionPayload {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
    let homeSummaries: [RuntimeHomeAppSummary]
    let hasCompleteWindowCoverage: Bool
    let coveredCGWindowIDs: Set<CGWindowID>
    let coverageDiagnostics: RuntimeProjectionCoverageDiagnostics

    init(
        apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext],
        homeSummaries: [RuntimeHomeAppSummary]? = nil,
        hasCompleteWindowCoverage: Bool = false,
        coveredCGWindowIDs: Set<CGWindowID>? = nil,
        coverageDiagnostics: RuntimeProjectionCoverageDiagnostics? = nil
    ) {
        self.apps = apps
        self.contextsByID = contextsByID
        self.homeSummaries = homeSummaries ?? Self.homeSummaries(
            for: apps,
            contextsByID: contextsByID
        )
        self.coverageDiagnostics = coverageDiagnostics ?? RuntimeProjectionCoverageDiagnostics(
            projectedAppCount: apps.count,
            contextAppCount: contextsByID.count,
            completeAppGroupCount: hasCompleteWindowCoverage ? apps.count : 0,
            missingWindowCoveragePIDs: [],
            incompleteContextAppIDs: Set(apps.map(\.id)).subtracting(contextsByID.keys)
        )
        self.hasCompleteWindowCoverage = hasCompleteWindowCoverage
            && self.coverageDiagnostics.hasCompleteCoverage
        self.coveredCGWindowIDs = coveredCGWindowIDs ?? Set(
            contextsByID.values.flatMap { context in
                context.windowsByID.values.compactMap(\.cgWindowID)
            }
        )
    }

    private static func homeSummaries(
        for apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext]
    ) -> [RuntimeHomeAppSummary] {
        apps.map { app in
            let context = contextsByID[app.id]
            return RuntimeHomeAppSummary(
                appID: app.id,
                displayName: app.displayName,
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt,
                windowCount: app.windows.count,
                pid: context?.ownerPID ?? 0,
                bundleIdentifier: context?.runningApp.bundleIdentifier,
                bundleURL: context?.runningApp.bundleURL
            )
        }
    }
}

struct RuntimeAppContext {
    let appID: String
    let runningApp: NSRunningApplication
    let ownerPID: pid_t
    let windowsByID: [String: RuntimeWindowContext]

    init(
        appID: String,
        runningApp: NSRunningApplication,
        ownerPID: pid_t? = nil,
        windowsByID: [String: RuntimeWindowContext]
    ) {
        self.appID = appID
        self.runningApp = runningApp
        self.ownerPID = ownerPID ?? runningApp.processIdentifier
        self.windowsByID = windowsByID
    }
}

struct RuntimeAppWindowProjectionSeed {
    let windowID: String
    let title: String
    let isMinimized: Bool
    let lastActiveAt: TimeInterval
    let ownerPID: pid_t
    let cgWindowID: CGWindowID?
    let spaceIDs: [Int]
    let activationHandleID: String?
    let axWindow: AXUIElement?
    let frame: CGRect?
    let isOnscreen: Bool
    let allowsPublicAXRecovery: Bool
    let hasStickyBinding: Bool
    let lastConfirmationSource: WindowBindingConfirmationSource?
    let bindingConfidenceOverride: WindowBindingConfidence?
    let bindingAllowedActionsOverride: Set<WindowBindingAction>?
    let bindingCandidateCount: Int?
    let spaceEvidence: RuntimeSpaceEvidence?

    init(
        windowID: String,
        title: String,
        isMinimized: Bool,
        lastActiveAt: TimeInterval,
        ownerPID: pid_t = 0,
        cgWindowID: CGWindowID? = nil,
        spaceIDs: [Int] = [],
        activationHandleID: String? = nil,
        axWindow: AXUIElement? = nil,
        frame: CGRect? = nil,
        isOnscreen: Bool = false,
        allowsPublicAXRecovery: Bool = false,
        hasStickyBinding: Bool = false,
        lastConfirmationSource: WindowBindingConfirmationSource? = nil,
        bindingConfidenceOverride: WindowBindingConfidence? = nil,
        bindingAllowedActionsOverride: Set<WindowBindingAction>? = nil,
        bindingCandidateCount: Int? = nil,
        spaceEvidence: RuntimeSpaceEvidence? = nil
    ) {
        self.windowID = windowID
        self.title = title
        self.isMinimized = isMinimized
        self.lastActiveAt = lastActiveAt
        self.ownerPID = ownerPID
        self.cgWindowID = cgWindowID
        self.spaceIDs = spaceIDs
        self.activationHandleID = activationHandleID
        self.axWindow = axWindow
        self.frame = frame
        self.isOnscreen = isOnscreen
        self.allowsPublicAXRecovery = allowsPublicAXRecovery
        self.hasStickyBinding = hasStickyBinding
        self.lastConfirmationSource = lastConfirmationSource
        self.bindingConfidenceOverride = bindingConfidenceOverride
        self.bindingAllowedActionsOverride = bindingAllowedActionsOverride
        self.bindingCandidateCount = bindingCandidateCount
        self.spaceEvidence = spaceEvidence
    }

    var candidate: WindowCandidate {
        WindowCandidate(
            id: windowID,
            title: title,
            isMinimized: isMinimized,
            lastActiveAt: lastActiveAt
        )
    }

    var context: RuntimeWindowContext {
        RuntimeWindowContext(
            id: windowID,
            title: title,
            isMinimized: isMinimized,
            ownerPID: ownerPID,
            cgWindowID: cgWindowID,
            spaceIDs: spaceIDs,
            inferredTitleBarStyle: nil,
            activationHandleID: activationHandleID,
            axWindow: axWindow,
            frame: frame,
            isOnscreen: isOnscreen,
            allowsPublicAXRecovery: allowsPublicAXRecovery,
            hasStickyBinding: hasStickyBinding,
            lastConfirmationSource: lastConfirmationSource,
            bindingConfidenceOverride: bindingConfidenceOverride,
            bindingAllowedActionsOverride: bindingAllowedActionsOverride,
            bindingCandidateCount: bindingCandidateCount,
            spaceEvidence: spaceEvidence
        )
    }
}

extension RuntimeWindowListEntry {
    func projectionSeed(lastActiveAt: TimeInterval) -> RuntimeAppWindowProjectionSeed {
        RuntimeAppWindowProjectionSeed(
            windowID: windowID,
            title: title,
            isMinimized: isMinimized,
            lastActiveAt: lastActiveAt,
            ownerPID: ownerPID,
            cgWindowID: cgWindowID,
            spaceIDs: spaceIDs,
            activationHandleID: activationHandleID,
            axWindow: axWindow,
            frame: frame,
            isOnscreen: isOnscreen,
            allowsPublicAXRecovery: allowsPublicAXRecovery,
            hasStickyBinding: hasStickyBinding,
            lastConfirmationSource: lastConfirmationSource,
            bindingConfidenceOverride: bindingConfidenceOverride,
            bindingAllowedActionsOverride: bindingAllowedActionsOverride,
            bindingCandidateCount: bindingCandidateCount,
            spaceEvidence: spaceEvidence
        )
    }
}

struct RuntimeCurrentAppWindowProjectionAssemblyInput {
    let appID: String
    let displayName: String
    let groupID: String
    let summaryLastActiveAt: TimeInterval
    let candidateLastActiveAt: TimeInterval
    let pid: pid_t
    let runningApp: NSRunningApplication
    let windowSeeds: [RuntimeAppWindowProjectionSeed]
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]

    init(
        appID: String,
        displayName: String,
        groupID: String,
        summaryLastActiveAt: TimeInterval,
        candidateLastActiveAt: TimeInterval,
        pid: pid_t,
        runningApp: NSRunningApplication,
        windowSeeds: [RuntimeAppWindowProjectionSeed],
        appDirectoryEntries: [RuntimeAppDirectoryEntry]
    ) {
        self.appID = appID
        self.displayName = displayName
        self.groupID = groupID
        self.summaryLastActiveAt = summaryLastActiveAt
        self.candidateLastActiveAt = candidateLastActiveAt
        self.pid = pid
        self.runningApp = runningApp
        self.windowSeeds = windowSeeds
        self.appDirectoryEntries = appDirectoryEntries
    }

    init(
        appID: String,
        app: NSRunningApplication,
        appGroup: [NSRunningApplication],
        rankByPID: [pid_t: Int],
        rankFallback: Int,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate,
        windowSeeds: [RuntimeAppWindowProjectionSeed]
    ) {
        let displayName = app.localizedName ?? appID
        let rank = RuntimeAppDirectory(apps: appGroup).preferredRank(
            for: appGroup,
            rankByPID: rankByPID,
            fallback: rankFallback
        )
        self.init(
            appID: appID,
            displayName: displayName,
            groupID: RuntimeAppIdentity.groupID(for: app.bundleIdentifier, fallbackName: displayName),
            summaryLastActiveAt: RuntimeAppDirectory.stableLastActiveValue(forRank: rank),
            candidateLastActiveAt: generatedAt - Double(rank),
            pid: app.processIdentifier,
            runningApp: app,
            windowSeeds: windowSeeds,
            appDirectoryEntries: RuntimeAppDirectoryFactSource.entries(
                from: appGroup,
                preservingRankFrom: rankByPID
            )
        )
    }
}

struct RuntimeCurrentAppWindowPayload {
    let summary: RuntimeHomeAppSummary
    let candidate: AppSwitchCandidate
    let context: RuntimeAppContext
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]

    init(
        summary: RuntimeHomeAppSummary,
        candidate: AppSwitchCandidate,
        context: RuntimeAppContext,
        appDirectoryEntries: [RuntimeAppDirectoryEntry]
    ) {
        self.summary = summary
        self.candidate = candidate
        self.context = context
        self.appDirectoryEntries = appDirectoryEntries
    }

    private init(
        appID: String,
        displayName: String,
        groupID: String,
        summaryLastActiveAt: TimeInterval,
        candidateLastActiveAt: TimeInterval,
        pid: pid_t,
        runningApp: NSRunningApplication,
        windowSeeds: [RuntimeAppWindowProjectionSeed],
        appDirectoryEntries: [RuntimeAppDirectoryEntry]
    ) {
        let windowCandidates = windowSeeds.map(\.candidate)
        let windowContexts = Dictionary(
            uniqueKeysWithValues: windowSeeds.map { seed in
                (seed.windowID, seed.context)
            }
        )
        self.init(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: displayName,
                groupID: groupID,
                lastActiveAt: summaryLastActiveAt,
                windowCount: windowSeeds.count,
                pid: pid,
                bundleIdentifier: runningApp.bundleIdentifier,
                bundleURL: runningApp.bundleURL
            ),
            candidate: AppSwitchCandidate(
                id: appID,
                displayName: displayName,
                groupID: groupID,
                lastActiveAt: candidateLastActiveAt,
                windows: windowCandidates
            ),
            context: RuntimeAppContext(
                appID: appID,
                runningApp: runningApp,
                ownerPID: pid,
                windowsByID: windowContexts
            ),
            appDirectoryEntries: appDirectoryEntries
        )
    }

    init(assemblyInput input: RuntimeCurrentAppWindowProjectionAssemblyInput) {
        self.init(
            appID: input.appID,
            displayName: input.displayName,
            groupID: input.groupID,
            summaryLastActiveAt: input.summaryLastActiveAt,
            candidateLastActiveAt: input.candidateLastActiveAt,
            pid: input.pid,
            runningApp: input.runningApp,
            windowSeeds: input.windowSeeds,
            appDirectoryEntries: input.appDirectoryEntries
        )
    }
}
