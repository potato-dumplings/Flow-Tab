import Darwin
import Foundation

struct ControlTabPressureProof {
    let kind: String
    let generation: Int
    let processIdentifier: Int32
    let windowID: String
    let cgWindowID: UInt32
    let satisfied: Bool
    let detail: String
}

struct ControlTabPressureMetricsRecorder {
    static let protocolVersion = 6
    static let schemaDigest =
        "06907e5b048ab5eff629e08944b734d3ed6ef798e3a9ea4cfde9af3313d29ad6"

    private enum Column {
        static let recordKind = 0
        static let started = 6
        static let completed = 7
        static let wall = 8
        static let cpuTime = 9
        static let cpuPercent = 10
        static let timingValid = 11
        static let proofKind = 27
        static let proofGeneration = 28
        static let proofPID = 29
        static let proofWindowID = 30
        static let proofCGWindowID = 31
        static let proofSatisfied = 32
        static let proofDetail = 33
        static let metricKind = 34
        static let metricName = 35
        static let metricMilliseconds = 36
        static let spanParent = 44
        static let spanStarted = 45
        static let spanCompleted = 46
        static let spanWall = 47
        static let spanCPUTime = 48
        static let spanCPUPercent = 49
        static let spanTimingValid = 50
        static let spanScope = 51
        static let spanOutcome = 52
        static let spanWorkUnits = 53
    }

    private static let headerColumns = [
        "record_kind", "lane", "scenario", "cycle", "sequence",
        "phase", "started_uptime_nanoseconds",
        "completed_uptime_nanoseconds", "wall_ms", "cpu_time_ms",
        "cpu_percent", "timing_valid", "satisfied",
        "panel_presented", "user_visible", "selected_app_id",
        "selected_window_id_before", "selected_window_id_after",
        "projected_app_count", "selected_window_count",
        "projection_generation", "activation_request_issued",
        "late_presentation_observed", "accessibility_trusted",
        "screen_capture_trusted", "partitions_reconciled",
        "watchdog_expired", "proof_kind", "proof_generation",
        "proof_pid", "proof_window_id", "proof_cg_window_id",
        "proof_satisfied", "proof_detail", "metric_kind",
        "metric_name", "metric_ms", "activation_verified",
        "activation_target_pid", "activation_target_window_id",
        "activation_target_cg_window_id",
        "required_components_present", "timeline_reconciled",
        "component_timing_valid", "span_parent",
        "span_started_uptime_nanoseconds",
        "span_completed_uptime_nanoseconds", "span_wall_ms",
        "span_cpu_time_ms", "span_cpu_percent", "span_timing_valid",
        "span_scope", "span_outcome", "span_work_units",
        "protocol_version", "schema_digest"
    ]
    private static let header = headerColumns.joined(separator: ",")

    private(set) var rows = [Self.header]
    let lane: String
    let scenario: String

    mutating func mark(_ name: String) {
        let timestamp = Self.monotonicNanoseconds()
        rows.append(
            baseRow(
                recordKind: "marker",
                cycle: 0,
                sequence: 0,
                phase: name,
                startedAtNanoseconds: timestamp,
                completedAtNanoseconds: timestamp
            ).joined(separator: ",")
        )
    }

    mutating func append(
        _ evidence: ControlTabPressureUITestEvidence,
        cycle: Int
    ) {
        let common = baseRow(
            recordKind: "event",
            cycle: cycle,
            sequence: evidence.sequence,
            phase: evidence.phase,
            startedAtNanoseconds: evidence.startedAtNanoseconds,
            completedAtNanoseconds: evidence.completedAtNanoseconds,
            evidence: evidence
        )
        rows.append(common.joined(separator: ","))
        appendMetrics(
            evidence.partitions,
            kind: "partition",
            common: common
        )
        appendMetrics(
            evidence.milestones,
            kind: "milestone",
            common: common
        )
        for span in evidence.spans.sorted(by: Self.spanOrder) {
            var row = common
            row[Column.recordKind] = "span"
            row[Column.started] = String(span.startedAtNanoseconds)
            row[Column.completed] = String(span.completedAtNanoseconds)
            row[Column.wall] = Self.decimal(span.wallMilliseconds)
            row[Column.cpuTime] = Self.decimal(span.cpuTimeMilliseconds)
            row[Column.cpuPercent] = Self.decimal(span.cpuPercent)
            row[Column.timingValid] = Self.flag(span.timingValid)
            row[Column.metricKind] = Self.escape(span.scope)
            row[Column.metricName] = Self.escape(span.name)
            row[Column.metricMilliseconds] =
                Self.decimal(span.wallMilliseconds)
            row[Column.spanParent] = Self.escape(span.parent)
            row[Column.spanStarted] = String(span.startedAtNanoseconds)
            row[Column.spanCompleted] = String(span.completedAtNanoseconds)
            row[Column.spanWall] = Self.decimal(span.wallMilliseconds)
            row[Column.spanCPUTime] =
                Self.decimal(span.cpuTimeMilliseconds)
            row[Column.spanCPUPercent] = Self.decimal(span.cpuPercent)
            row[Column.spanTimingValid] = Self.flag(span.timingValid)
            row[Column.spanScope] = Self.escape(span.scope)
            row[Column.spanOutcome] = Self.escape(span.outcome)
            row[Column.spanWorkUnits] = String(span.workUnits)
            rows.append(row.joined(separator: ","))
        }
    }

    mutating func appendProof(_ proof: ControlTabPressureProof) {
        let timestamp = Self.monotonicNanoseconds()
        var row = baseRow(
            recordKind: "proof",
            cycle: 0,
            sequence: 0,
            phase: proof.kind,
            startedAtNanoseconds: timestamp,
            completedAtNanoseconds: timestamp
        )
        row[Column.proofKind] = Self.escape(proof.kind)
        row[Column.proofGeneration] = String(proof.generation)
        row[Column.proofPID] = String(proof.processIdentifier)
        row[Column.proofWindowID] = Self.escape(proof.windowID)
        row[Column.proofCGWindowID] = String(proof.cgWindowID)
        row[Column.proofSatisfied] = Self.flag(proof.satisfied)
        row[Column.proofDetail] = Self.escape(proof.detail)
        rows.append(row.joined(separator: ","))
    }

    func write(to url: URL) throws {
        try rows.joined(separator: "\n")
            .appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private mutating func appendMetrics(
        _ metrics: [String: Double],
        kind: String,
        common: [String]
    ) {
        for metric in metrics.sorted(by: { $0.key < $1.key }) {
            var row = common
            row[Column.metricKind] = kind
            row[Column.metricName] = Self.escape(metric.key)
            row[Column.metricMilliseconds] = Self.decimal(metric.value)
            rows.append(row.joined(separator: ","))
        }
    }

    private func baseRow(
        recordKind: String,
        cycle: Int,
        sequence: UInt64,
        phase: String,
        startedAtNanoseconds: UInt64,
        completedAtNanoseconds: UInt64,
        evidence: ControlTabPressureUITestEvidence? = nil
    ) -> [String] {
        let row: [String] = [
            recordKind, lane, scenario, String(cycle), String(sequence),
            phase, String(startedAtNanoseconds),
            String(completedAtNanoseconds),
            Self.decimal(evidence?.wallMilliseconds ?? 0),
            Self.decimal(evidence?.cpuTimeMilliseconds ?? 0),
            Self.decimal(evidence?.cpuPercent ?? 0),
            Self.flag(evidence?.timingValid),
            Self.flag(evidence?.satisfied),
            Self.flag(evidence?.panelPresented),
            Self.flag(evidence?.userVisible),
            Self.escape(evidence?.selectedAppID ?? "none"),
            Self.escape(evidence?.selectedWindowIDBefore ?? "none"),
            Self.escape(evidence?.selectedWindowIDAfter ?? "none"),
            String(evidence?.projectedAppCount ?? 0),
            String(evidence?.selectedWindowCount ?? 0),
            String(evidence?.projectionGeneration ?? 0),
            Self.flag(evidence?.activationRequestIssued),
            Self.flag(evidence?.latePresentationObserved),
            Self.flag(evidence?.accessibilityTrusted),
            Self.flag(evidence?.screenCaptureTrusted),
            Self.flag(evidence?.partitionsReconciled),
            Self.flag(evidence?.watchdogExpired),
            "none", "0", "0", "none", "0", "0", "none",
            "event", "none", "0",
            Self.flag(evidence?.activationVerified),
            String(evidence?.activationTargetPID ?? 0),
            Self.escape(evidence?.activationTargetWindowID ?? "none"),
            String(evidence?.activationTargetCGWindowID ?? 0),
            Self.flag(evidence?.requiredComponentsPresent),
            Self.flag(evidence?.timelineReconciled),
            Self.flag(evidence?.componentTimingValid),
            "none", "0", "0", "0", "0", "0", "0", "none",
            "none", "0", String(Self.protocolVersion), Self.schemaDigest
        ]
        precondition(row.count == Self.headerColumns.count)
        return row
    }

    private static func spanOrder(
        _ lhs: ControlTabPressureUITestSpan,
        _ rhs: ControlTabPressureUITestSpan
    ) -> Bool {
        if lhs.startedAtNanoseconds != rhs.startedAtNanoseconds {
            return lhs.startedAtNanoseconds < rhs.startedAtNanoseconds
        }
        if lhs.scope != rhs.scope { return lhs.scope < rhs.scope }
        return lhs.name < rhs.name
    }

    private static func monotonicNanoseconds() -> UInt64 {
        var value = timespec()
        precondition(clock_gettime(CLOCK_MONOTONIC, &value) == 0)
        return UInt64(value.tv_sec) * 1_000_000_000
            + UInt64(value.tv_nsec)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func flag(_ value: Bool?) -> String {
        value == true ? "1" : "0"
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") else {
            return value
        }
        return "\""
            + value.replacingOccurrences(of: "\"", with: "\"\"")
            + "\""
    }
}
