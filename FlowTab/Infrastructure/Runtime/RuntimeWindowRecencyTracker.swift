import CoreGraphics
import Foundation
import FlowTabCore

enum RuntimeRecencyIdentityConfidence: String {
    case exactWindowID
    case exactCGWindowID
    case semanticTitleFrame
}

struct RuntimeRecencyMatchDiagnostic: Equatable {
    let appID: String
    let recordWindowID: String
    let matchedWindowID: String?
    let confidence: RuntimeRecencyIdentityConfidence
    let candidateCount: Int
    let ageSeconds: TimeInterval
    let recordGeneration: UInt64
    let evaluationGeneration: UInt64
    let generationAge: UInt64
    let action: String
    let reason: String?

    var logMessage: String {
        [
            "event=recency_match",
            "appID=\(appID)",
            "recordWindowID=\(recordWindowID)",
            "matchedWindowID=\(matchedWindowID ?? "nil")",
            "confidence=\(confidence.rawValue)",
            "candidateCount=\(candidateCount)",
            "ageSeconds=\(String(format: "%.1f", max(0, ageSeconds)))",
            "recordGeneration=\(recordGeneration)",
            "evaluationGeneration=\(evaluationGeneration)",
            "generationAge=\(generationAge)",
            "action=\(action)",
            "reason=\(reason ?? "none")"
        ].joined(separator: " ")
    }
}

final class RuntimeWindowRecencyTracker: @unchecked Sendable {
    static let shared = RuntimeWindowRecencyTracker()

    private struct Match {
        let windowID: String
        let confidence: RuntimeRecencyIdentityConfidence
        let candidateCount: Int
    }

    private struct Record {
        let appID: String
        let windowID: String
        let ownerPID: pid_t
        let cgWindowID: CGWindowID?
        let normalizedTitle: String?
        let frame: CGRect?
        let timestamp: TimeInterval
        let generation: UInt64

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

        func semanticFallbackRejectionReason(
            at evaluationTime: TimeInterval,
            evaluationGeneration: UInt64,
            maxAge: TimeInterval,
            maxGenerationAge: UInt64
        ) -> String? {
            if evaluationTime - timestamp > maxAge {
                return "semantic_fallback_expired"
            }
            if generationAge(at: evaluationGeneration) > maxGenerationAge {
                return "semantic_fallback_generation_expired"
            }
            return nil
        }

        func generationAge(at evaluationGeneration: UInt64) -> UInt64 {
            evaluationGeneration >= generation ? evaluationGeneration - generation : 0
        }
    }

    private let clock: () -> TimeInterval
    private let maxRecordsPerApp: Int
    private let semanticFallbackMaxAge: TimeInterval
    private let semanticFallbackMaxGenerationAge: UInt64
    private let lock = NSLock()
    private var recordsByAppID: [String: [Record]] = [:]
    private var snapshotGeneration: UInt64 = 0

    init(
        clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
        maxRecordsPerApp: Int = 128,
        semanticFallbackMaxAge: TimeInterval = 300,
        semanticFallbackMaxGenerationAge: UInt64 = 3
    ) {
        self.clock = clock
        self.maxRecordsPerApp = max(1, maxRecordsPerApp)
        self.semanticFallbackMaxAge = max(0, semanticFallbackMaxAge)
        self.semanticFallbackMaxGenerationAge = semanticFallbackMaxGenerationAge
    }

    func record(
        appID: String,
        windowID: String,
        ownerPID: pid_t,
        cgWindowID: CGWindowID?,
        title: String,
        frame: CGRect?,
        allowedActions: Set<WindowBindingAction> = WindowBindingConfidence.exact.allowedActions
    ) {
        guard allowedActions.contains(.updateRecency) else {
            logSkippedRecencyUpdate(
                appID: appID,
                windowID: windowID,
                reason: "binding_action_disallowed",
                allowedActions: allowedActions
            )
            return
        }
        let timestamp = clock()
        lock.lock()
        let record = Record(
            appID: appID,
            windowID: windowID,
            ownerPID: ownerPID,
            cgWindowID: cgWindowID,
            normalizedTitle: normalizedRuntimeWindowTitle(title),
            frame: frame?.standardized,
            timestamp: timestamp,
            generation: snapshotGeneration
        )
        defer { lock.unlock() }
        upsert(record)
    }

    func recordVerifiedFocus(
        appID: String,
        windowID: String,
        ownerPID: pid_t,
        cgWindowID: CGWindowID?,
        title: String,
        frame: CGRect?,
        allowedActions: Set<WindowBindingAction>
    ) {
        guard Self.allowsVerifiedFocusRecencyUpdate(allowedActions) else {
            logSkippedRecencyUpdate(
                appID: appID,
                windowID: windowID,
                reason: "verified_focus_action_disallowed",
                allowedActions: allowedActions
            )
            return
        }

        record(
            appID: appID,
            windowID: windowID,
            ownerPID: ownerPID,
            cgWindowID: cgWindowID,
            title: title,
            frame: frame,
            allowedActions: allowedActions.union([.updateRecency])
        )
    }

    func record(appID: String, windowID: String, context: RuntimeAppContext) {
        guard let window = context.windowsByID[windowID] else { return }
        record(
            appID: appID,
            windowID: windowID,
            ownerPID: ownerPID(for: window, context: context),
            cgWindowID: window.cgWindowID,
            title: window.title,
            frame: window.frame,
            allowedActions: window.bindingAllowedActions
        )
    }

    func recordVerifiedFocus(appID: String, windowID: String, context: RuntimeAppContext) {
        guard let window = context.windowsByID[windowID] else { return }
        recordVerifiedFocus(
            appID: appID,
            windowID: windowID,
            ownerPID: ownerPID(for: window, context: context),
            cgWindowID: window.cgWindowID,
            title: window.title,
            frame: window.frame,
            allowedActions: window.bindingAllowedActions
        )
    }

    func appsWithRecencyApplied(
        _ apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext]
    ) -> [AppSwitchCandidate] {
        let evaluation = beginSnapshotEvaluation()
        return apps.map { app in
            guard let context = contextsByID[app.id] else {
                return app
            }
            return appWithRecencyApplied(
                app,
                context: context,
                records: evaluation.recordsByAppID[app.id] ?? [],
                evaluationGeneration: evaluation.generation
            )
        }
    }

    func homeSnapshotWithRecencyApplied(
        _ snapshot: RuntimeHomeAppSnapshot
    ) -> RuntimeHomeAppSnapshot {
        let orderedApps = appsWithRecencyApplied(
            [snapshot.candidate],
            contextsByID: [snapshot.context.appID: snapshot.context]
        )
        guard let candidate = orderedApps.first else {
            return snapshot
        }
        return RuntimeHomeAppSnapshot(
            summary: snapshot.summary,
            candidate: candidate,
            context: snapshot.context
        )
    }

    func removeAll() {
        lock.lock()
        recordsByAppID.removeAll()
        snapshotGeneration = 0
        lock.unlock()
    }

    private func beginSnapshotEvaluation() -> (
        recordsByAppID: [String: [Record]],
        generation: UInt64
    ) {
        lock.lock()
        defer { lock.unlock() }
        snapshotGeneration &+= 1
        return (recordsByAppID, snapshotGeneration)
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

    private func logSkippedRecencyUpdate(
        appID: String,
        windowID: String,
        reason: String,
        allowedActions: Set<WindowBindingAction>
    ) {
        let actionList = allowedActions
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        RuntimeLog.debug(
            .recency,
            "event=recency_record appID=\(appID) windowID=\(windowID) action=skip reason=\(reason) allowedActions=\(actionList)"
        )
    }

    private func appWithRecencyApplied(
        _ app: AppSwitchCandidate,
        context: RuntimeAppContext,
        records: [Record],
        evaluationGeneration: UInt64
    ) -> AppSwitchCandidate {
        guard !records.isEmpty else {
            return app
        }

        let appWindowIDs = Set(app.windows.map(\.id))
        let evaluationTime = clock()
        var timestampByWindowID: [String: TimeInterval] = [:]
        for record in records {
            guard
                let match = matchingWindow(
                    for: record,
                    appWindowIDs: appWindowIDs,
                    context: context,
                    evaluationTime: evaluationTime,
                    evaluationGeneration: evaluationGeneration
                )
            else {
                continue
            }
            if (timestampByWindowID[match.windowID] ?? -.infinity) < record.timestamp {
                timestampByWindowID[match.windowID] = record.timestamp
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

    private func matchingWindow(
        for record: Record,
        appWindowIDs: Set<String>,
        context: RuntimeAppContext,
        evaluationTime: TimeInterval,
        evaluationGeneration: UInt64
    ) -> Match? {
        if
            appWindowIDs.contains(record.windowID),
            let window = context.windowsByID[record.windowID],
            record.matchesProcess(window: window, context: context)
        {
            let match = Match(
                windowID: record.windowID,
                confidence: .exactWindowID,
                candidateCount: 1
            )
            logRecencyMatch(
                record: record,
                context: context,
                match: match,
                evaluationTime: evaluationTime,
                evaluationGeneration: evaluationGeneration,
                action: "apply_exact_ordering",
                reason: nil
            )
            return match
        }

        if let cgWindowID = record.cgWindowID {
            let cgMatches = Array(appWindowIDs).filter { windowID in
                guard let window = context.windowsByID[windowID] else { return false }
                return window.cgWindowID == cgWindowID
                    && record.matchesProcess(window: window, context: context)
            }
            if cgMatches.count == 1 {
                let match = Match(
                    windowID: cgMatches[0],
                    confidence: .exactCGWindowID,
                    candidateCount: cgMatches.count
                )
                logRecencyMatch(
                    record: record,
                    context: context,
                    match: match,
                    evaluationTime: evaluationTime,
                    evaluationGeneration: evaluationGeneration,
                    action: "apply_exact_ordering",
                    reason: nil
                )
                return match
            }
            if cgMatches.count > 1 {
                logRecencyRejection(
                    record: record,
                    context: context,
                    confidence: .exactCGWindowID,
                    candidateCount: cgMatches.count,
                    evaluationTime: evaluationTime,
                    evaluationGeneration: evaluationGeneration,
                    reason: "duplicate_cg_window_id"
                )
            }
        }

        if let rejectionReason = record.semanticFallbackRejectionReason(
            at: evaluationTime,
            evaluationGeneration: evaluationGeneration,
            maxAge: semanticFallbackMaxAge,
            maxGenerationAge: semanticFallbackMaxGenerationAge
        ) {
            logRecencyRejection(
                record: record,
                context: context,
                confidence: .semanticTitleFrame,
                candidateCount: 0,
                evaluationTime: evaluationTime,
                evaluationGeneration: evaluationGeneration,
                reason: rejectionReason
            )
            return nil
        }
        let semanticMatches = Array(appWindowIDs).filter { windowID in
            guard let window = context.windowsByID[windowID] else { return false }
            return record.matchesProcess(window: window, context: context)
                && record.matchesTitleAndFrame(window)
        }
        guard semanticMatches.count == 1 else {
            if semanticMatches.count > 1 {
                logRecencyRejection(
                    record: record,
                    context: context,
                    confidence: .semanticTitleFrame,
                    candidateCount: semanticMatches.count,
                    evaluationTime: evaluationTime,
                    evaluationGeneration: evaluationGeneration,
                    reason: "duplicate_title_frame"
                )
            }
            return nil
        }
        let match = Match(
            windowID: semanticMatches[0],
            confidence: .semanticTitleFrame,
            candidateCount: semanticMatches.count
        )
        logRecencyMatch(
            record: record,
            context: context,
            match: match,
            evaluationTime: evaluationTime,
            evaluationGeneration: evaluationGeneration,
            action: "apply_low_confidence_ordering",
            reason: nil
        )
        return match
    }

    private func ownerPID(for window: RuntimeWindowContext, context: RuntimeAppContext) -> pid_t {
        window.ownerPID == 0 ? context.runningApp.processIdentifier : window.ownerPID
    }

    private static func allowsVerifiedFocusRecencyUpdate(
        _ allowedActions: Set<WindowBindingAction>
    ) -> Bool {
        allowedActions.contains(.updateRecency)
            || allowedActions.contains(.useForAXActivation)
            || allowedActions.contains(.useForCGActivationFallback)
    }

    private func logRecencyMatch(
        record: Record,
        context: RuntimeAppContext,
        match: Match,
        evaluationTime: TimeInterval,
        evaluationGeneration: UInt64,
        action: String,
        reason: String?
    ) {
        RuntimeLog.debug(
            .recency,
            RuntimeRecencyMatchDiagnostic(
                appID: context.appID,
                recordWindowID: record.windowID,
                matchedWindowID: match.windowID,
                confidence: match.confidence,
                candidateCount: match.candidateCount,
                ageSeconds: evaluationTime - record.timestamp,
                recordGeneration: record.generation,
                evaluationGeneration: evaluationGeneration,
                generationAge: record.generationAge(at: evaluationGeneration),
                action: action,
                reason: reason
            ).logMessage
        )
    }

    private func logRecencyRejection(
        record: Record,
        context: RuntimeAppContext,
        confidence: RuntimeRecencyIdentityConfidence,
        candidateCount: Int,
        evaluationTime: TimeInterval,
        evaluationGeneration: UInt64,
        reason: String
    ) {
        RuntimeLog.debug(
            .recency,
            RuntimeRecencyMatchDiagnostic(
                appID: context.appID,
                recordWindowID: record.windowID,
                matchedWindowID: nil,
                confidence: confidence,
                candidateCount: candidateCount,
                ageSeconds: evaluationTime - record.timestamp,
                recordGeneration: record.generation,
                evaluationGeneration: evaluationGeneration,
                generationAge: record.generationAge(at: evaluationGeneration),
                action: "ignore_record_for_this_snapshot",
                reason: reason
            ).logMessage
        )
    }
}
