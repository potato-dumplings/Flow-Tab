import Foundation
import FlowTabCore

extension LiveSwitcherModel {
    private static let projectionLogCategory = "Projection"

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
        RuntimeLog.debug(
            Self.projectionLogCategory,
            Self.projectionLogLine(
                event,
                fields: [
                    ("result", "empty"),
                    ("trigger", triggerDirection.debugName),
                    ("projectionMs", Self.formatMilliseconds(projectionReadMs - startMs)),
                    ("recencyMs", Self.formatMilliseconds(recencyAppliedMs - projectionReadMs)),
                    ("totalMs", Self.formatMilliseconds(recencyAppliedMs - startMs))
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
        RuntimeLog.debug(
            Self.projectionLogCategory,
            Self.projectionLogLine(
                event,
                fields: [
                    ("result", "ready"),
                    ("trigger", triggerDirection.debugName),
                    ("apps", "\(payload.apps.count)"),
                    ("windows", "\(payload.windowCount)"),
                    ("projectionMs", Self.formatMilliseconds(projectionReadMs - startMs)),
                    ("recencyMs", Self.formatMilliseconds(recencyAppliedMs - projectionReadMs)),
                    ("sessionBuildMs", Self.formatMilliseconds(sessionReadyMs - recencyAppliedMs)),
                    ("indexMs", Self.formatMilliseconds(indexReadyMs - sessionReadyMs)),
                    ("publishMs", Self.formatMilliseconds(completeMs - indexReadyMs)),
                    ("totalMs", Self.formatMilliseconds(completeMs - startMs))
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
        homeAppSnapshot: RuntimeHomeAppSnapshot?,
        startMs: Double,
        projectionReadMs: Double,
        applyEndMs: Double
    ) {
        let windowCount = homeAppSnapshot?.candidate.windows.count ?? 0
        let pidCount = homeAppSnapshot.map { selectedHomeAppSnapshot in
            Set(selectedHomeAppSnapshot.context.windowsByID.values.map { context in
                if context.ownerPID == 0 {
                    return selectedHomeAppSnapshot.context.runningApp.processIdentifier
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
