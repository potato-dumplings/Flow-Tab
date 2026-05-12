import CoreGraphics
import Foundation
import FlowTabCore

final class RuntimeWindowRecencyTracker {
    private struct Record {
        let appID: String
        let windowID: String
        let ownerPID: pid_t
        let cgWindowID: CGWindowID?
        let normalizedTitle: String?
        let frame: CGRect?
        let timestamp: TimeInterval

        func matchesProcess(window: RuntimeWindowContext, context: RuntimeAppContext) -> Bool {
            let candidatePID = window.ownerPID == 0 ? context.runningApp.processIdentifier : window.ownerPID
            return candidatePID == ownerPID
        }

        func matchesTitleAndFrame(_ window: RuntimeWindowContext) -> Bool {
            guard
                let normalizedTitle,
                let windowTitle = normalizedRuntimeWindowTitle(window.title),
                normalizedTitle.caseInsensitiveCompare(windowTitle) == .orderedSame,
                let frame,
                let windowFrame = window.frame?.standardized
            else {
                return false
            }
            return RuntimeWindowTopologyClassifier.framesApproximatelyMatch(frame, windowFrame)
        }
    }

    private let clock: () -> TimeInterval
    private let maxRecordsPerApp: Int
    private var recordsByAppID: [String: [Record]] = [:]

    init(
        clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
        maxRecordsPerApp: Int = 128
    ) {
        self.clock = clock
        self.maxRecordsPerApp = max(1, maxRecordsPerApp)
    }

    func record(
        appID: String,
        windowID: String,
        ownerPID: pid_t,
        cgWindowID: CGWindowID?,
        title: String,
        frame: CGRect?
    ) {
        let record = Record(
            appID: appID,
            windowID: windowID,
            ownerPID: ownerPID,
            cgWindowID: cgWindowID,
            normalizedTitle: normalizedRuntimeWindowTitle(title),
            frame: frame?.standardized,
            timestamp: clock()
        )
        upsert(record)
    }

    func record(appID: String, windowID: String, context: RuntimeAppContext) {
        guard let window = context.windowsByID[windowID] else { return }
        record(
            appID: appID,
            windowID: windowID,
            ownerPID: ownerPID(for: window, context: context),
            cgWindowID: window.cgWindowID,
            title: window.title,
            frame: window.frame
        )
    }

    func snapshotWithRecencyApplied(_ snapshot: RuntimeSnapshot) -> RuntimeSnapshot {
        RuntimeSnapshot(
            apps: snapshot.apps.map { app in
                guard let context = snapshot.contextsByID[app.id] else {
                    return app
                }
                return appWithRecencyApplied(app, context: context)
            },
            contextsByID: snapshot.contextsByID
        )
    }

    private func upsert(_ record: Record) {
        var records = recordsByAppID[record.appID] ?? []
        records.removeAll { existing in
            existing.windowID == record.windowID
                || (
                    record.cgWindowID != nil
                        && existing.ownerPID == record.ownerPID
                        && existing.cgWindowID == record.cgWindowID
                )
        }
        records.append(record)
        if records.count > maxRecordsPerApp {
            records = Array(records.sorted { $0.timestamp < $1.timestamp }.suffix(maxRecordsPerApp))
        }
        recordsByAppID[record.appID] = records
    }

    private func appWithRecencyApplied(
        _ app: AppSwitchCandidate,
        context: RuntimeAppContext
    ) -> AppSwitchCandidate {
        guard let records = recordsByAppID[app.id], !records.isEmpty else {
            return app
        }

        let appWindowIDs = Set(app.windows.map(\.id))
        var timestampByWindowID: [String: TimeInterval] = [:]
        for record in records {
            guard let windowID = matchingWindowID(for: record, appWindowIDs: appWindowIDs, context: context) else {
                continue
            }
            if (timestampByWindowID[windowID] ?? -.infinity) < record.timestamp {
                timestampByWindowID[windowID] = record.timestamp
            }
        }
        guard !timestampByWindowID.isEmpty else { return app }

        let recencyRankByWindowID = Dictionary(
            uniqueKeysWithValues: timestampByWindowID
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.key < rhs.key
                    }
                    return lhs.value < rhs.value
                }
                .enumerated()
                .map { index, pair in (pair.key, index + 1) }
        )
        let baseLastActiveAt = app.windows.map(\.lastActiveAt).max() ?? app.lastActiveAt
        let originalIndexByWindowID = Dictionary(
            uniqueKeysWithValues: app.windows.enumerated().map { index, window in
                (window.id, index)
            }
        )
        let windowsWithRecency = app.windows.map { window in
            guard let rank = recencyRankByWindowID[window.id] else {
                return window
            }
            return WindowCandidate(
                id: window.id,
                title: window.title,
                isMinimized: window.isMinimized,
                lastActiveAt: baseLastActiveAt + TimeInterval(rank)
            )
        }
        let windows = windowsWithRecency.sorted { lhs, rhs in
            let lhsRank = recencyRankByWindowID[lhs.id]
            let rhsRank = recencyRankByWindowID[rhs.id]
            switch (lhsRank, rhsRank) {
            case let (.some(lhsRank), .some(rhsRank)):
                if lhsRank != rhsRank {
                    return lhsRank > rhsRank
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return (originalIndexByWindowID[lhs.id] ?? .max)
                < (originalIndexByWindowID[rhs.id] ?? .max)
        }
        return AppSwitchCandidate(
            id: app.id,
            displayName: app.displayName,
            groupID: app.groupID,
            lastActiveAt: app.lastActiveAt,
            windows: windows
        )
    }

    private func matchingWindowID(
        for record: Record,
        appWindowIDs: Set<String>,
        context: RuntimeAppContext
    ) -> String? {
        if
            appWindowIDs.contains(record.windowID),
            let window = context.windowsByID[record.windowID],
            record.matchesProcess(window: window, context: context)
        {
            return record.windowID
        }

        if let cgWindowID = record.cgWindowID {
            let cgMatches = Array(appWindowIDs).filter { windowID in
                guard let window = context.windowsByID[windowID] else { return false }
                return window.cgWindowID == cgWindowID
                    && record.matchesProcess(window: window, context: context)
            }
            if cgMatches.count == 1 {
                return cgMatches[0]
            }
        }

        let semanticMatches = Array(appWindowIDs).filter { windowID in
            guard let window = context.windowsByID[windowID] else { return false }
            return record.matchesProcess(window: window, context: context)
                && record.matchesTitleAndFrame(window)
        }
        return semanticMatches.count == 1 ? semanticMatches[0] : nil
    }

    private func ownerPID(for window: RuntimeWindowContext, context: RuntimeAppContext) -> pid_t {
        window.ownerPID == 0 ? context.runningApp.processIdentifier : window.ownerPID
    }
}
