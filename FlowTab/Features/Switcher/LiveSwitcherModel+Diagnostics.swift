import Foundation
import FlowTabCore

extension LiveSwitcherModel {
    private static let projectionLogCategory: RuntimeLogCategory = .projection

    nonisolated static func monotonicMilliseconds() -> Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }

    func logStartFocusedWindowSessionNoFrontmost(startMs: Double) {
        let failedMs = Self.monotonicMilliseconds() - startMs
        RuntimeLog.debug(
            Self.projectionLogCategory,
            Self.projectionLogLine(
                "startFocusedWindowSession",
                fields: [
                    ("result", "noFrontmostApp"),
                    ("totalMs", Self.formatMilliseconds(failedMs))
                ]
            )
        )
    }

    func logStartFocusedWindowSession(
        result: String,
        frontmostAppID: String,
        frontmostReadyMs: Double,
        projectionReadMs: Double,
        recencyAppliedMs: Double,
        completeMs: Double,
        startMs: Double,
        windows: Int? = nil
    ) {
        RuntimeLog.debug(
            Self.projectionLogCategory,
            Self.projectionLogLine(
                "startFocusedWindowSession",
                fields: startFocusedWindowSessionLogFields(
                    result: result,
                    frontmostAppID: frontmostAppID,
                    frontmostReadyMs: frontmostReadyMs,
                    projectionReadMs: projectionReadMs,
                    recencyAppliedMs: recencyAppliedMs,
                    completeMs: completeMs,
                    startMs: startMs,
                    windows: windows
                )
            )
        )
    }

    func logLoadAppSwitcherProjectionSessionEmpty(
        event: String = "loadAppSwitcherProjectionSession",
        triggerDirection: CycleDirection,
        projectionReadMs: Double,
        recencyAppliedMs: Double,
        startMs: Double
    ) {
        let diagnostic = AppSwitcherSessionLoadDiagnostic(
            result: "empty",
            event: event,
            trigger: triggerDirection.debugName,
            appCount: 0,
            windowCount: 0,
            projectionMs: projectionReadMs - startMs,
            recencyMs: recencyAppliedMs - projectionReadMs,
            sessionBuildMs: 0,
            indexMs: 0,
            publishMs: 0
        )
        lastAppSwitcherSessionLoadDiagnostic = diagnostic
        RuntimeLog.debug(
            Self.projectionLogCategory,
            Self.projectionLogLine(
                event,
                fields: [
                    ("result", diagnostic.result),
                    ("trigger", diagnostic.trigger),
                    ("projectionMs", Self.formatMilliseconds(diagnostic.projectionMs)),
                    ("recencyMs", Self.formatMilliseconds(diagnostic.recencyMs)),
                    ("totalMs", Self.formatMilliseconds(diagnostic.totalMs))
                ]
            )
        )
    }

    func logLoadAppSwitcherProjectionSessionReady(
        event: String = "loadAppSwitcherProjectionSession",
        triggerDirection: CycleDirection,
        payload: AppSwitcherProjectionSessionPayload,
        projectionReadMs: Double,
        recencyAppliedMs: Double,
        sessionReadyMs: Double,
        indexReadyMs: Double,
        completeMs: Double,
        startMs: Double
    ) {
        let diagnostic = AppSwitcherSessionLoadDiagnostic(
            result: "ready",
            event: event,
            trigger: triggerDirection.debugName,
            appCount: payload.apps.count,
            windowCount: payload.windowCount,
            projectionMs: projectionReadMs - startMs,
            recencyMs: recencyAppliedMs - projectionReadMs,
            sessionBuildMs: sessionReadyMs - recencyAppliedMs,
            indexMs: indexReadyMs - sessionReadyMs,
            publishMs: completeMs - indexReadyMs
        )
        lastAppSwitcherSessionLoadDiagnostic = diagnostic
        RuntimeLog.debug(
            Self.projectionLogCategory,
            Self.projectionLogLine(
                event,
                fields: [
                    ("result", diagnostic.result),
                    ("trigger", diagnostic.trigger),
                    ("apps", "\(diagnostic.appCount)"),
                    ("windows", "\(diagnostic.windowCount)"),
                    ("projectionMs", Self.formatMilliseconds(diagnostic.projectionMs)),
                    ("recencyMs", Self.formatMilliseconds(diagnostic.recencyMs)),
                    ("sessionBuildMs", Self.formatMilliseconds(diagnostic.sessionBuildMs)),
                    ("indexMs", Self.formatMilliseconds(diagnostic.indexMs)),
                    ("publishMs", Self.formatMilliseconds(diagnostic.publishMs)),
                    ("totalMs", Self.formatMilliseconds(diagnostic.totalMs))
                ]
            )
        )
    }

    func logRuntimeProjectionMaintenance(
        result: String,
        startMs: Double,
        generation: UInt64,
        reason: ProjectionInvalidationReason,
        triggerDirection: CycleDirection,
        applyGeneration: UInt64? = nil
    ) {
        let diagnostic = RuntimeProjectionMaintenanceDiagnostic(
            result: result,
            generation: generation,
            currentGeneration: runtimeProjectionMaintenanceGeneration,
            reason: reason,
            trigger: triggerDirection.debugName,
            applyGeneration: applyGeneration,
            totalMs: Self.formatMilliseconds(Self.monotonicMilliseconds() - startMs)
        )
        lastRuntimeProjectionMaintenanceDiagnostic = diagnostic
        RuntimeLog.debug(
            Self.projectionLogCategory,
            diagnostic.logMessage
        )
    }

    func logSelectedAppWindowProjection(
        result: String,
        appID: String,
        currentAppWindowPayload: RuntimeCurrentAppWindowPayload?,
        startMs: Double,
        projectionReadMs: Double,
        applyEndMs: Double
    ) {
        let windowCount = currentAppWindowPayload?.candidate.windows.count ?? 0
        let pidCount = currentAppWindowPayload.map { payload in
            Set(payload.context.windowsByID.values.map { context in
                if context.ownerPID == 0 {
                    return payload.context.runningApp.processIdentifier
                }
                return context.ownerPID
            }).count
        } ?? 0
        let totalMs = applyEndMs - startMs
        let fields: [(String, String)] = [
            ("result", result),
            ("appID", appID),
            ("pids", "\(pidCount)"),
            ("windows", "\(windowCount)"),
            ("projectionMs", Self.formatMilliseconds(projectionReadMs - startMs)),
            ("applyMs", Self.formatMilliseconds(applyEndMs - projectionReadMs)),
            ("totalMs", Self.formatMilliseconds(totalMs))
        ]
        let message = Self.projectionLogLine("selectedAppWindowProjection", fields: fields)
        if totalMs > 100 {
            RuntimeLog.warning(Self.projectionLogCategory, message)
        } else {
            RuntimeLog.debug(Self.projectionLogCategory, message)
        }
    }

    func logReadAppSwitcherProjectionPayload(
        source: String,
        payload: AppSwitcherProjectionSessionPayload,
        durationMs: Double
    ) {
        RuntimeLog.debug(
            Self.projectionLogCategory,
            Self.projectionLogLine(
                "readAppSwitcherProjectionPayload",
                fields: [
                    ("source", source),
                    ("apps", "\(payload.apps.count)"),
                    ("windows", "\(payload.windowCount)"),
                    ("durationMs", Self.formatMilliseconds(durationMs))
                ]
            )
        )
    }

    private func startFocusedWindowSessionLogFields(
        result: String,
        frontmostAppID: String,
        frontmostReadyMs: Double,
        projectionReadMs: Double,
        recencyAppliedMs: Double,
        completeMs: Double,
        startMs: Double,
        windows: Int?
    ) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("result", result),
            ("appID", frontmostAppID)
        ]
        if let windows {
            fields.append(("windows", "\(windows)"))
        }
        fields.append(contentsOf: [
            ("frontmostMs", Self.formatMilliseconds(frontmostReadyMs - startMs)),
            ("projectionMs", Self.formatMilliseconds(projectionReadMs - frontmostReadyMs)),
            ("recencyMs", Self.formatMilliseconds(recencyAppliedMs - projectionReadMs)),
            ("sessionBuildMs", Self.formatMilliseconds(completeMs - recencyAppliedMs)),
            ("totalMs", Self.formatMilliseconds(completeMs - startMs))
        ])
        return fields
    }

    private static func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func projectionLogLine(_ prefix: String, fields: [(String, String)]) -> String {
        ([prefix] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " ")
    }
}
