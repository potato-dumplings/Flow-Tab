import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import FlowTabCore

struct RuntimeFullRepairProjectionPayload {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
}

struct RuntimeAppContext {
    let appID: String
    let runningApp: NSRunningApplication
    let windowsByID: [String: RuntimeWindowContext]
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
    let allowsPublicAXRecovery: Bool
    let hasStickyBinding: Bool
    let lastConfirmationSource: WindowBindingConfirmationSource?
    let bindingConfidenceOverride: WindowBindingConfidence?
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
        allowsPublicAXRecovery: Bool = false,
        hasStickyBinding: Bool = false,
        lastConfirmationSource: WindowBindingConfirmationSource? = nil,
        bindingConfidenceOverride: WindowBindingConfidence? = nil,
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
        self.allowsPublicAXRecovery = allowsPublicAXRecovery
        self.hasStickyBinding = hasStickyBinding
        self.lastConfirmationSource = lastConfirmationSource
        self.bindingConfidenceOverride = bindingConfidenceOverride
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
            allowsPublicAXRecovery: allowsPublicAXRecovery,
            hasStickyBinding: hasStickyBinding,
            lastConfirmationSource: lastConfirmationSource,
            bindingConfidenceOverride: bindingConfidenceOverride,
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
}

struct RuntimeCurrentAppWindowPayload {
    let summary: RuntimeHomeAppSummary
    let candidate: AppSwitchCandidate
    let context: RuntimeAppContext

    init(summary: RuntimeHomeAppSummary, candidate: AppSwitchCandidate, context: RuntimeAppContext) {
        self.summary = summary
        self.candidate = candidate
        self.context = context
    }

    init(
        appID: String,
        displayName: String,
        groupID: String,
        summaryLastActiveAt: TimeInterval,
        candidateLastActiveAt: TimeInterval,
        pid: pid_t,
        runningApp: NSRunningApplication,
        windowSeeds: [RuntimeAppWindowProjectionSeed]
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
                pid: pid
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
                windowsByID: windowContexts
            )
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
            windowSeeds: input.windowSeeds
        )
    }
}

struct RuntimeFullRepairProjectionAssemblyApp {
    let pid: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let launchDate: Date?
}

struct RuntimeFullRepairProjectionAssemblyWindow {
    let windowID: String
    let title: String
    let isMinimized: Bool
    let cgWindowID: CGWindowID?
    let spaceIDs: [Int]

    init(
        windowID: String,
        title: String,
        isMinimized: Bool,
        cgWindowID: CGWindowID?,
        spaceIDs: [Int] = []
    ) {
        self.windowID = windowID
        self.title = title
        self.isMinimized = isMinimized
        self.cgWindowID = cgWindowID
        self.spaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
    }
}

struct RuntimeFullRepairProjectionAssemblyRow {
    let pid: pid_t
    let candidate: AppSwitchCandidate
}

enum RuntimeAppLayerProjectionFilter {
    static func shouldIncludeRunningApplication(
        activationPolicy: NSApplication.ActivationPolicy,
        isTerminated: Bool,
        pid: pid_t,
        currentPID: pid_t,
        includeCurrentProcessInAppLayer: Bool
    ) -> Bool {
        activationPolicy == .regular
            && !isTerminated
            && (includeCurrentProcessInAppLayer || pid != currentPID)
    }

    static func shouldIncludeAppInAppLayer(
        hasWindows: Bool,
        hasVisibleWindow: Bool,
        hideMinimizedAppsFromAppLayer: Bool
    ) -> Bool {
        guard hideMinimizedAppsFromAppLayer else { return true }
        guard hasWindows else { return true }
        return hasVisibleWindow
    }
}

enum RuntimeFullRepairProjectionAssembler {
    static func payload(
        fromCurrentAppWindowProjectionInputs inputs: [RuntimeCurrentAppWindowProjectionAssemblyInput],
        duplicateContextHandler: ((String) -> Void)? = nil
    ) -> RuntimeFullRepairProjectionPayload {
        payload(
            fromCurrentAppWindowPayloads: inputs.map(RuntimeCurrentAppWindowPayload.init(assemblyInput:)),
            duplicateContextHandler: duplicateContextHandler
        )
    }

    static func payload(
        fromCurrentAppWindowPayloads currentAppWindowPayloads: [RuntimeCurrentAppWindowPayload],
        duplicateContextHandler: ((String) -> Void)? = nil
    ) -> RuntimeFullRepairProjectionPayload {
        let rows = currentAppWindowPayloads
            .map { payload in
                (candidate: payload.candidate, context: payload.context)
            }
            .sorted { lhs, rhs in
                if lhs.candidate.lastActiveAt == rhs.candidate.lastActiveAt {
                    return lhs.candidate.displayName.localizedCaseInsensitiveCompare(
                        rhs.candidate.displayName
                    ) == .orderedAscending
                }
                return lhs.candidate.lastActiveAt > rhs.candidate.lastActiveAt
            }

        var contextsByID: [String: RuntimeAppContext] = [:]
        for row in rows {
            if contextsByID[row.context.appID] != nil {
                duplicateContextHandler?(row.context.appID)
            }
            contextsByID[row.context.appID] = row.context
        }

        return RuntimeFullRepairProjectionPayload(
            apps: rows.map(\.candidate),
            contextsByID: contextsByID
        )
    }

    static func assembleRows(
        apps: [RuntimeFullRepairProjectionAssemblyApp],
        windowsByPID: [pid_t: [RuntimeFullRepairProjectionAssemblyWindow]],
        rankByPID: [pid_t: Int],
        hideMinimizedAppsFromAppLayer: Bool,
        now: TimeInterval
    ) -> [RuntimeFullRepairProjectionAssemblyRow] {
        let appsByPID = Dictionary(uniqueKeysWithValues: apps.map { app in
            (app.pid, app)
        })
        let appDirectoryEntries = apps.map(\.appDirectoryEntry)
        let windowStatsByPID = Dictionary(uniqueKeysWithValues: apps.map { app in
            let windows = windowsByPID[app.pid] ?? []
            return (
                app.pid,
                RuntimeAppWindowStats(
                    windowCount: windows.count,
                    hasVisibleWindow: windows.contains(where: { !$0.isMinimized })
                )
            )
        })
        let groupedApps = RuntimeAppDirectory.groupedEntriesByAppID(appDirectoryEntries)
        var rows: [RuntimeFullRepairProjectionAssemblyRow] = []
        rows.reserveCapacity(groupedApps.count)

        for group in groupedApps.values {
            guard
                let primaryEntry = RuntimeAppDirectory.primaryEntry(
                    in: group,
                    windowStatsByPID: windowStatsByPID,
                    rankByPID: rankByPID
                ),
                let app = appsByPID[primaryEntry.pid]
            else {
                continue
            }
            let appID = primaryEntry.appID
            let displayName = app.localizedName ?? appID
            let windows = RuntimeAppDirectory.sortedEntriesWithinGroup(
                group,
                windowStatsByPID: windowStatsByPID,
                rankByPID: rankByPID
            ).flatMap { groupApp in
                windowsByPID[groupApp.pid] ?? []
            }
            guard RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: !windows.isEmpty,
                hasVisibleWindow: windows.contains(where: { !$0.isMinimized }),
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                continue
            }
            let rank = RuntimeAppDirectory.preferredRank(
                for: group,
                rankByPID: rankByPID,
                fallback: 10_000 + rows.count
            )
            let candidate = AppSwitchCandidate(
                id: appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(for: app.bundleIdentifier, fallbackName: displayName),
                lastActiveAt: now - Double(rank),
                windows: windows.enumerated().map { entryIndex, entry in
                    WindowCandidate(
                        id: entry.windowID,
                        title: entry.title,
                        isMinimized: entry.isMinimized,
                        lastActiveAt: now - Double(entryIndex)
                    )
                }
            )
            rows.append(RuntimeFullRepairProjectionAssemblyRow(pid: app.pid, candidate: candidate))
        }

        rows.sort { lhs, rhs in
            if lhs.candidate.lastActiveAt == rhs.candidate.lastActiveAt {
                return lhs.candidate.displayName.localizedCaseInsensitiveCompare(
                    rhs.candidate.displayName
                ) == .orderedAscending
            }
            return lhs.candidate.lastActiveAt > rhs.candidate.lastActiveAt
        }
        return rows
    }
}

private extension RuntimeFullRepairProjectionAssemblyApp {
    var appDirectoryEntry: RuntimeAppDirectoryEntry {
        RuntimeAppDirectoryEntry(
            pid: pid,
            appID: bundleIdentifier ?? "pid:\(pid)",
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName,
            launchDate: launchDate
        )
    }
}
