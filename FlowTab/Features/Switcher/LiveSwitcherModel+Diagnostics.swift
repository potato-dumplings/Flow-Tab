import Foundation
import FlowTabCore

extension LiveSwitcherModel {
    nonisolated static func monotonicMilliseconds() -> Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }

    func logStartFocusedWindowSessionNoFrontmost(startMs: Double) {
        let failedMs = Self.monotonicMilliseconds() - startMs
        RuntimeLog.debug(
            "Snapshot",
            Self.snapshotLogLine(
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
        snapshotReadMs: Double,
        recencyAppliedMs: Double,
        completeMs: Double,
        startMs: Double,
        windows: Int? = nil
    ) {
        RuntimeLog.debug(
            "Snapshot",
            Self.snapshotLogLine(
                "startFocusedWindowSession",
                fields: startFocusedWindowSessionLogFields(
                    result: result,
                    frontmostAppID: frontmostAppID,
                    frontmostReadyMs: frontmostReadyMs,
                    snapshotReadMs: snapshotReadMs,
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
        snapshotReadMs: Double,
        recencyAppliedMs: Double,
        startMs: Double
    ) {
        RuntimeLog.debug(
            "Snapshot",
            Self.snapshotLogLine(
                event,
                fields: [
                    ("result", "empty"),
                    ("trigger", triggerDirection.debugName),
                    ("snapshotMs", Self.formatMilliseconds(snapshotReadMs - startMs)),
                    ("recencyMs", Self.formatMilliseconds(recencyAppliedMs - snapshotReadMs)),
                    ("totalMs", Self.formatMilliseconds(recencyAppliedMs - startMs))
                ]
            )
        )
    }

    func logLoadAppSwitcherProjectionSessionReady(
        event: String = "loadAppSwitcherProjectionSession",
        triggerDirection: CycleDirection,
        payload: AppSwitcherProjectionSessionPayload,
        snapshotReadMs: Double,
        recencyAppliedMs: Double,
        sessionReadyMs: Double,
        indexReadyMs: Double,
        completeMs: Double,
        startMs: Double
    ) {
        RuntimeLog.debug(
            "Snapshot",
            Self.snapshotLogLine(
                event,
                fields: [
                    ("result", "ready"),
                    ("trigger", triggerDirection.debugName),
                    ("apps", "\(payload.apps.count)"),
                    ("windows", "\(payload.windowCount)"),
                    ("snapshotMs", Self.formatMilliseconds(snapshotReadMs - startMs)),
                    ("recencyMs", Self.formatMilliseconds(recencyAppliedMs - snapshotReadMs)),
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
            "Snapshot",
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
        let message = Self.snapshotLogLine("selectedAppWindowProjection", fields: fields)
        if totalMs > 100 {
            RuntimeLog.warning(.snapshot, message)
        } else {
            RuntimeLog.debug(.snapshot, message)
        }
    }

    func logReadAppSwitcherProjectionPayload(
        source: String,
        payload: AppSwitcherProjectionSessionPayload,
        durationMs: Double
    ) {
        RuntimeLog.debug(
            "Snapshot",
            Self.snapshotLogLine(
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
        snapshotReadMs: Double,
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
            ("snapshotMs", Self.formatMilliseconds(snapshotReadMs - frontmostReadyMs)),
            ("recencyMs", Self.formatMilliseconds(recencyAppliedMs - snapshotReadMs)),
            ("sessionBuildMs", Self.formatMilliseconds(completeMs - recencyAppliedMs)),
            ("totalMs", Self.formatMilliseconds(completeMs - startMs))
        ])
        return fields
    }

    private static func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func snapshotLogLine(_ prefix: String, fields: [(String, String)]) -> String {
        ([prefix] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " ")
    }
}
