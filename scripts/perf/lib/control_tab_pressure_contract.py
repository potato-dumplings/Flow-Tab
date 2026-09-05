#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from statistics import median
from typing import Any

from control_tab_pressure_metrics import (
    coverage,
    load_samples,
    median_paths,
    metric_reconciliation_failures,
    path_summary,
    percentile,
    phase_summary,
    samples_in_window,
    stats,
)

from control_tab_pressure_proofs import (
    exact_activation_coverage,
    validate_proofs,
)
from control_tab_pressure_breakdown import (
    event_breakdowns,
    mutation_generation_evidence,
    topology_target_evidence,
)
from control_tab_pressure_contract_schema import (
    CANCEL_MILESTONES,
    COMMIT_MILESTONES,
    COMMAND_PATH_MILESTONES,
    COMMAND_PATH_PARTITIONS,
    LATENCY_LIMITS_MS,
    LIFECYCLE_PHASES,
    OPEN_MILESTONES,
    OPEN_PARTITIONS,
    compatible_identity,
    environment_identity,
    load_phase_metrics,
)
from control_tab_pressure_spans import (
    PHASE_CPU_LIMIT_PERCENT,
    component_phase_coverage,
    median_span_summaries,
    root_cause_rankings,
    span_summary,
    validate_spans,
)


def _product_slo_category(
    *,
    lane: str,
    measured_events: list[dict[str, str]],
    metric_index: dict[tuple[str, str], dict[str, float]],
    phase_metrics: dict[str, dict[str, Any]],
    path_metrics: dict[str, Any],
    active_cpu: dict[str, float] | None,
    cooldown_cpu: dict[str, float] | None,
) -> dict[str, Any]:
    limits: dict[str, float] = {}
    measurements: dict[str, float | None] = {}
    failures: dict[str, dict[str, float]] = {}
    missing: list[str] = []

    def check(name: str, observed: float | None, limit: float) -> None:
        limits[name] = limit
        measurements[name] = observed
        if observed is None:
            missing.append(name)
        elif observed > limit:
            failures[name] = {
                "observed": observed,
                "limit": limit,
            }

    def phase_stat(
        phase: str, metric: str, statistic: str
    ) -> float | None:
        value = phase_metrics.get(phase, {}).get(metric, {}).get(
            statistic
        )
        return float(value) if value is not None else None

    def path_stat(
        phase: str,
        kind: str,
        name: str,
        statistic: str,
    ) -> float | None:
        value = (
            path_metrics.get(phase, {})
            .get(kind, {})
            .get(name, {})
            .get(statistic)
        )
        return float(value) if value is not None else None

    open_events = [
        row for row in measured_events if row["phase"] == "open"
    ]
    observed_window_counts = [
        int(row["selected_window_count"]) for row in open_events
    ]
    maximum_window_count = max(observed_window_counts, default=0)
    small_stable_topology = (
        lane in {"ready", "mutation"}
        and 1 <= maximum_window_count <= 5
    )

    cached_pairs: list[tuple[float, float]] = []
    for row in open_events:
        milestones = metric_index.get(
            (row["sequence"], "milestone"), {}
        )
        wall = milestones.get("cached_first_frame_ms")
        cpu = milestones.get("cached_first_frame_cpu_time_ms")
        if wall is not None and cpu is not None:
            cached_pairs.append((wall, cpu))
    cached_weighted_cpu = (
        100.0 * sum(cpu for _, cpu in cached_pairs)
        / sum(wall for wall, _ in cached_pairs)
        if cached_pairs and sum(wall for wall, _ in cached_pairs) > 0
        else None
    )

    check(
        "cached_first_frame_wall_p95_ms",
        path_stat(
            "open", "milestones", "cached_first_frame_ms", "p95"
        ),
        16.7,
    )
    check(
        "cached_first_frame_cpu_time_p95_ms",
        path_stat(
            "open",
            "milestones",
            "cached_first_frame_cpu_time_ms",
            "p95",
        ),
        3.0,
    )
    check(
        "cached_first_frame_weighted_cpu_percent",
        cached_weighted_cpu,
        30.0,
    )

    fresh_wall_p95 = path_stat(
        "open",
        "milestones",
        "fresh_visible_previews_complete_ms",
        "p95",
    )
    fresh_wall_p99 = path_stat(
        "open",
        "milestones",
        "fresh_visible_previews_complete_ms",
        "p99",
    )
    check(
        "fresh_visible_previews_wall_p95_ms",
        fresh_wall_p95,
        30.0 if small_stable_topology else 100.0,
    )
    if small_stable_topology:
        check(
            "fresh_visible_previews_wall_p99_ms",
            fresh_wall_p99,
            50.0,
        )
    else:
        timeout_rate = (
            sum(row.get("watchdog_expired") == "1" for row in open_events)
            / len(open_events)
            if open_events
            else None
        )
        check("fresh_visible_previews_timeout_rate", timeout_rate, 0.01)

    fresh_cpu_limit = (
        15.0 if maximum_window_count <= 3
        else 25.0 if maximum_window_count <= 5
        else None
    )
    if fresh_cpu_limit is not None:
        check(
            "fresh_visible_previews_cpu_time_p95_ms",
            path_stat(
                "open",
                "milestones",
                "fresh_visible_previews_complete_cpu_time_ms",
                "p95",
            ),
            fresh_cpu_limit,
        )

    for phase in ("forward", "reverse"):
        check(
            f"{phase}_wall_p95_ms",
            phase_stat(phase, "wall_ms", "p95"),
            8.3,
        )
        check(
            f"{phase}_wall_p99_ms",
            phase_stat(phase, "wall_ms", "p99"),
            16.7,
        )
        check(
            f"{phase}_cpu_time_p95_ms",
            phase_stat(phase, "cpu_time_ms", "p95"),
            2.0,
        )
        check(
            f"{phase}_weighted_cpu_percent",
            phase_metrics.get(phase, {}).get("cpu_percent"),
            25.0,
        )

    check(
        "activation_request_wall_p95_ms",
        path_stat(
            "commit", "milestones", "activation_request_ms", "p95"
        ),
        8.0,
    )
    check(
        "commit_panel_hidden_wall_p95_ms",
        path_stat(
            "commit", "milestones", "panel_hidden_ms", "p95"
        ),
        16.7,
    )
    check(
        "focus_and_cleanup_wall_p95_ms",
        path_stat(
            "commit",
            "derived",
            "focus_and_cleanup_complete_ms",
            "p95",
        ),
        250.0 if lane == "topology" else 100.0,
    )
    check(
        "commit_cpu_time_p95_ms",
        phase_stat("commit", "cpu_time_ms", "p95"),
        10.0,
    )
    check(
        "cancel_panel_hidden_wall_p95_ms",
        path_stat(
            "cancel", "milestones", "panel_hidden_ms", "p95"
        ),
        16.7,
    )
    check(
        "cancel_wall_p95_ms",
        phase_stat("cancel", "wall_ms", "p95"),
        25.0,
    )
    check(
        "cancel_cpu_time_p95_ms",
        phase_stat("cancel", "cpu_time_ms", "p95"),
        5.0,
    )
    check(
        "cancel_weighted_cpu_percent",
        phase_metrics.get("cancel", {}).get("cpu_percent"),
        30.0,
    )
    check(
        "active_cpu_avg_percent",
        active_cpu.get("avg") if active_cpu else None,
        20.0,
    )
    check(
        "active_cpu_p95_percent",
        active_cpu.get("p95") if active_cpu else None,
        30.0,
    )
    check(
        "cooldown_cpu_p95_percent",
        cooldown_cpu.get("p95") if cooldown_cpu else None,
        2.0,
    )
    return {
        "verdict": "passed" if not failures and not missing else "failed",
        "scenario_class": (
            "hot_stable_1_to_5"
            if small_stable_topology
            else "cold_noisy_or_wide"
        ),
        "maximum_observed_window_count": maximum_window_count,
        "limits": limits,
        "measurements": measurements,
        "failures": failures,
        "missing_measurements": sorted(missing),
    }


def evaluate_attempt(
    metrics_path: Path,
    samples_path: Path,
    runtime_status_path: Path,
    lane: str,
    scenario: str,
    expected_app_count: int,
    expected_window_count: int,
    attachment_manifest_path: Path | None = None,
    identity_manifest_path: Path | None = None,
    target_launch_receipt_path: Path | None = None,
    cleanup_evidence_path: Path | None = None,
    sampler_readiness_path: Path | None = None,
    result_bundle_path: Path | None = None,
) -> dict[str, Any]:
    (
        events,
        markers,
        metric_index,
        proofs,
        spans,
        protocol_schema_failures,
    ) = load_phase_metrics(metrics_path)
    samples = load_samples(samples_path)
    phase_metrics = phase_summary(events)
    path_metrics = path_summary(events, metric_index)
    component_metrics = span_summary(events, spans)
    component_coverage = component_phase_coverage(events, spans)
    span_validation = validate_spans(events, spans)
    root_causes = root_cause_rankings(component_metrics)
    required_phases = set(LIFECYCLE_PHASES)
    measured_events = [row for row in events if int(row["cycle"]) > 0]
    missing_phases = sorted(required_phases - set(phase_metrics))
    unsatisfied = [row["sequence"] for row in events if row["satisfied"] != "1"]
    invalid_timing = [
        row["sequence"] for row in events if row.get("timing_valid") != "1"
    ]
    late_presentations = [
        row["sequence"]
        for row in events
        if row.get("late_presentation_observed") == "1"
    ]
    if lane == "ready":
        wrong_scale = [
            row["sequence"]
            for row in measured_events
            if int(row["projected_app_count"]) != expected_app_count
            or int(row["selected_window_count"]) != expected_window_count
        ]
    elif lane == "mutation":
        wrong_scale = [
            row["sequence"]
            for row in measured_events
            if int(row["projected_app_count"]) < 1
            or int(row["selected_window_count"]) not in {2, 3}
        ]
    else:
        wrong_scale = [
            row["sequence"]
            for row in measured_events
            if int(row["projected_app_count"]) < 1
            or int(row["selected_window_count"]) != expected_window_count
        ]
    required_proofs = {
        "ready": {"physical_shortcut", "sampler_readiness"},
        "mutation": {
            "physical_shortcut",
            "sampler_readiness",
            "mutation_generation",
            "dirty_projection_gate",
            "first_session",
            "option_tab_history",
            "early_control_release",
        },
        "topology": {
            "physical_shortcut",
            "sampler_readiness",
            "topology_scope",
            "exact_activation",
        },
    }.get(lane, set())
    satisfied_proof_kinds, failed_proofs, exact_activation_proof_invalid = (
        validate_proofs(proofs)
    )
    topology_activation_coverage = (
        exact_activation_coverage(proofs, expected_window_count)
        if lane == "topology"
        else None
    )
    topology_activation_coverage_failed = (
        topology_activation_coverage is not None
        and topology_activation_coverage["verdict"] != "passed"
    )
    missing_proofs = sorted(required_proofs - satisfied_proof_kinds)
    permission_missing = any(
        row["accessibility_trusted"] != "1" or row["screen_capture_trusted"] != "1"
        for row in measured_events
    ) or any(
        row.get("proof_kind") == "permission"
        and row.get("proof_satisfied") != "1"
        for row in proofs
    )
    sequences = [int(row["sequence"]) for row in events]
    sequence_counts = Counter(sequences)
    duplicate_sequences = sorted(
        sequence
        for sequence, count in sequence_counts.items()
        if count > 1
    )
    open_events = [row for row in events if row["phase"] == "open"]
    partition_gaps: list[str] = []
    path_metric_gaps: list[str] = []
    for row in open_events:
        sequence = row["sequence"]
        missing_partitions = OPEN_PARTITIONS - set(
            metric_index.get((sequence, "partition"), {})
        )
        missing_milestones = OPEN_MILESTONES - set(
            metric_index.get((sequence, "milestone"), {})
        )
        if missing_partitions or missing_milestones or row["partitions_reconciled"] != "1":
            partition_gaps.append(sequence)
            path_metric_gaps.append(sequence)

    for row in events:
        if row["phase"] == "open":
            continue
        sequence = row["sequence"]
        missing_partitions = COMMAND_PATH_PARTITIONS - set(
            metric_index.get((sequence, "partition"), {})
        )
        required_milestones = set(COMMAND_PATH_MILESTONES)
        if row["phase"] == "commit":
            required_milestones.update(COMMIT_MILESTONES)
        elif row["phase"] == "cancel":
            required_milestones.update(CANCEL_MILESTONES)
        missing_milestones = required_milestones - set(
            metric_index.get((sequence, "milestone"), {})
        )
        if missing_partitions or missing_milestones:
            path_metric_gaps.append(sequence)

    path_metric_gaps = sorted(set(path_metric_gaps), key=int)
    reconciliation_failures = metric_reconciliation_failures(
        events,
        metric_index,
    )

    commit_events = [row for row in events if row["phase"] == "commit"]
    commit_metric_gaps = [
        row["sequence"]
        for row in commit_events
        if "activation_request_ms"
        not in metric_index.get((row["sequence"], "milestone"), {})
    ]
    measured_commit_request_ms = [
        metric_index[(row["sequence"], "milestone")]["activation_request_ms"]
        for row in measured_events
        if row["phase"] == "commit"
        and "activation_request_ms"
        in metric_index.get((row["sequence"], "milestone"), {})
    ]
    commit_request_stats = (
        stats(measured_commit_request_ms)
        if measured_commit_request_ms
        else None
    )
    if commit_request_stats is not None:
        phase_metrics["commit"]["activation_request_ms"] = (
            commit_request_stats
        )

    latency_measurements = {
        "forward": phase_metrics.get("forward", {}).get("wall_ms", {}).get("p95"),
        "reverse": phase_metrics.get("reverse", {}).get("wall_ms", {}).get("p95"),
        "cancel": phase_metrics.get("cancel", {}).get("wall_ms", {}).get("p95"),
        "commit_activation_request": (
            commit_request_stats["p95"]
            if commit_request_stats is not None
            else None
        ),
    }
    if lane == "ready":
        latency_measurements["ready_open"] = (
            phase_metrics.get("open", {}).get("wall_ms", {}).get("p95")
        )
    latency_failures = {
        name: observed
        for name, observed in latency_measurements.items()
        if observed is not None
        and observed > LATENCY_LIMITS_MS[name]
    }
    activation_missing = any(
        row["activation_request_issued"] != "1"
        for row in events
        if row["phase"] == "commit"
    )
    activation_verification_missing = any(
        row.get("activation_verified") != "1"
        for row in events
        if row["phase"] == "commit"
    )
    phase_cpu_failures = {
        phase: metrics["cpu_percent"]
        for phase, metrics in phase_metrics.items()
        if phase in {"open", "forward", "reverse", "commit", "cancel"}
        and metrics["cpu_percent"] > PHASE_CPU_LIMIT_PERCENT
    }
    active_start = markers.get("measurement_start", 0)
    cooldown_start = markers.get("cooldown_start", 0)
    cooldown_end = markers.get("cooldown_end", 0)
    active_samples = samples_in_window(samples, active_start, cooldown_start)
    cooldown_samples = samples_in_window(samples, cooldown_start, cooldown_end)
    active_coverage = coverage(samples, active_start, cooldown_start)
    active_cpu = stats(row["cpu"] for row in active_samples) if active_samples else None
    cooldown_cpu = stats(row["cpu"] for row in cooldown_samples) if cooldown_samples else None
    active_rss = stats(row["rss_kb"] for row in active_samples) if active_samples else None

    mid_start = active_start + int((cooldown_start - active_start) * 0.40)
    mid_end = active_start + int((cooldown_start - active_start) * 0.60)
    late_start = active_start + int((cooldown_start - active_start) * 0.80)
    mid_rss = samples_in_window(samples, mid_start, mid_end)
    late_rss = samples_in_window(samples, late_start, cooldown_start)
    mid_p95 = percentile((row["rss_kb"] for row in mid_rss), 0.95) if mid_rss else 0.0
    late_p95 = percentile((row["rss_kb"] for row in late_rss), 0.95) if late_rss else 0.0
    rss_growth_kb = late_p95 - mid_p95
    rss_limit_kb = max(16 * 1024, mid_p95 * 0.10)
    rss_passed = bool(mid_rss and late_rss and rss_growth_kb <= rss_limit_kb)
    cooldown_limit = max(5.0, (active_cpu or {"avg": 0.0})["avg"] * 0.25)
    cpu_passed = bool(cooldown_cpu and cooldown_cpu["p95"] <= cooldown_limit)
    cpu_passed = cpu_passed and not phase_cpu_failures
    elapsed_seconds = max(0.0, (cooldown_start - active_start) / 1_000_000_000)
    completions = sum(1 for row in measured_events if row["phase"] in {"commit", "cancel"})
    throughput = completions / elapsed_seconds if elapsed_seconds > 0 else 0.0

    runtime_status = json.loads(runtime_status_path.read_text(encoding="utf-8"))
    cleanup_passed = (
        runtime_status.get("application_cleanup_exit_code") == 0
        and runtime_status.get("application_cleanup_evidence_present") is True
        and runtime_status.get("target_termination_verdict") in {"identity_match_lost", "sample_unavailable", "not_observed"}
    )
    evidence_passed = (
        not missing_phases
        and not path_metric_gaps
        and not reconciliation_failures
        and not commit_metric_gaps
        and not invalid_timing
        and not protocol_schema_failures
        and not span_validation["missing"]
        and not span_validation["invalid_timing"]
        and not span_validation["stale_generation"]
        and not span_validation["invalid_outcome"]
        and not span_validation["reconciliation"]
        and active_coverage >= 0.90
        and bool(active_samples)
        and bool(cooldown_samples)
        and runtime_status.get("identity_verdict") == "matched"
        and runtime_status.get("target_launch_receipt_present") is True
        and runtime_status.get("ui_result_bundle_valid") is True
        and runtime_status.get("final_exit_code") == 0
        and runtime_status.get("ui_wrapper_exit_code") == 0
        and runtime_status.get("sampling_failed") is False
        and runtime_status.get("sampling_readiness_present") is True
        and runtime_status.get("termination_timed_out") is False
        and identity_manifest_path is not None
        and identity_manifest_path.is_file()
        and target_launch_receipt_path is not None
        and target_launch_receipt_path.is_file()
        and cleanup_evidence_path is not None
        and cleanup_evidence_path.is_file()
        and sampler_readiness_path is not None
        and sampler_readiness_path.is_file()
        and result_bundle_path is not None
        and result_bundle_path.is_dir()
        and (
            attachment_manifest_path is None
            or attachment_manifest_path.is_file()
        )
    )
    product_slo = _product_slo_category(
        lane=lane,
        measured_events=measured_events,
        metric_index=metric_index,
        phase_metrics=phase_metrics,
        path_metrics=path_metrics,
        active_cpu=active_cpu,
        cooldown_cpu=cooldown_cpu,
    )
    categories = {
        "correctness": {"verdict": "passed" if not (unsatisfied or wrong_scale or activation_missing or activation_verification_missing or missing_proofs or failed_proofs or duplicate_sequences or exact_activation_proof_invalid or topology_activation_coverage_failed or late_presentations) else "failed", "unsatisfied_sequences": unsatisfied, "wrong_scale_sequences": wrong_scale, "activation_request_missing": activation_missing, "activation_verification_missing": activation_verification_missing, "missing_proofs": missing_proofs, "failed_proofs": failed_proofs, "duplicate_sequences": duplicate_sequences, "exact_activation_proof_invalid": exact_activation_proof_invalid, "topology_activation_coverage": topology_activation_coverage, "late_presentation_sequences": late_presentations},
        "latency": {"verdict": "passed" if not latency_failures and not missing_phases and not commit_metric_gaps else "failed", "limits_ms": LATENCY_LIMITS_MS, "measurements_ms": latency_measurements, "failures": latency_failures, "commit_metric_gap_sequences": commit_metric_gaps},
        "cpu": {"verdict": "passed" if cpu_passed else "failed", "active": active_cpu, "cooldown": cooldown_cpu, "cooldown_p95_limit": cooldown_limit, "phase_cpu_limit_percent": PHASE_CPU_LIMIT_PERCENT, "phase_cpu_failures": phase_cpu_failures},
        "rss": {"verdict": "passed" if rss_passed else "failed", "active": active_rss, "mid_p95_kb": mid_p95, "late_p95_kb": late_p95, "growth_kb": rss_growth_kb, "growth_limit_kb": rss_limit_kb},
        "evidence": {"verdict": "passed" if evidence_passed else "failed", "active_coverage": active_coverage, "missing_phases": missing_phases, "partition_gap_sequences": partition_gaps, "path_metric_gap_sequences": path_metric_gaps, "path_reconciliation_failure_sequences": reconciliation_failures, "commit_metric_gap_sequences": commit_metric_gaps, "invalid_timing_sequences": invalid_timing, "protocol_schema_failures": protocol_schema_failures, "missing_span_sequences": span_validation["missing"], "span_timing_failure_sequences": span_validation["invalid_timing"], "stale_generation_sequences": span_validation["stale_generation"], "invalid_span_outcome_sequences": span_validation["invalid_outcome"], "timeline_reconciliation_failure_sequences": span_validation["reconciliation"], "identity_manifest_present": identity_manifest_path is not None and identity_manifest_path.is_file(), "target_launch_receipt_present": target_launch_receipt_path is not None and target_launch_receipt_path.is_file(), "cleanup_evidence_present": cleanup_evidence_path is not None and cleanup_evidence_path.is_file(), "sampler_readiness_present": sampler_readiness_path is not None and sampler_readiness_path.is_file(), "result_bundle_present": result_bundle_path is not None and result_bundle_path.is_dir(), "first_frame_attachment_present": attachment_manifest_path is None or attachment_manifest_path.is_file()},
        "cleanup": {"verdict": "passed" if cleanup_passed else "failed"},
        "product_slo": product_slo,
    }
    overall = "blocked" if permission_missing else (
        "passed" if all(item["verdict"] == "passed" for item in categories.values()) else "failed"
    )
    return {
        "schema_version": 2,
        "identity": environment_identity(lane, scenario),
        "overall_verdict": overall,
        "permission_blocked": permission_missing,
        "scale": {
            "app_count": expected_app_count,
            "window_count": expected_window_count,
            "observed_app_counts": sorted(
                {int(row["projected_app_count"]) for row in measured_events}
            ),
            "observed_window_counts": sorted(
                {int(row["selected_window_count"]) for row in measured_events}
            ),
        },
        "categories": categories,
        "phases": phase_metrics,
        "paths": path_metrics,
        "spans": component_metrics,
        "component_coverage": component_coverage,
        "root_causes": root_causes,
        "breakdowns": event_breakdowns(events, spans, lane),
        "mutation_generations": (
            mutation_generation_evidence(proofs)
            if lane == "mutation"
            else []
        ),
        "topology_targets": (
            topology_target_evidence(events)
            if lane == "topology"
            else []
        ),
        "active_cpu": active_cpu,
        "cooldown_cpu": cooldown_cpu,
        "rss": active_rss,
        "rss_plateau_growth_kb": rss_growth_kb,
        "throughput_per_second": throughput,
        "event_count": len(measured_events),
    }


def median_attempts(attempts: list[dict[str, Any]]) -> dict[str, Any]:
    phases: dict[str, Any] = {}
    for phase in LIFECYCLE_PHASES:
        phases[phase] = {
            **{
                f"{statistic}_wall_ms": median(
                    item["phases"][phase]["wall_ms"][statistic]
                    for item in attempts
                )
                for statistic in ("p50", "p95", "max")
            },
            **{
                f"{statistic}_cpu_time_ms": median(
                    item["phases"][phase]["cpu_time_ms"][statistic]
                    for item in attempts
                )
                for statistic in ("p50", "p95", "max")
            },
            "cpu_percent": median(
                item["phases"][phase]["cpu_percent"] for item in attempts
            ),
        }
    return {
        "phases": phases,
        "paths": median_paths(attempts),
        "spans": median_span_summaries(attempts),
        "active_cpu_avg": median(item["active_cpu"]["avg"] for item in attempts),
        "active_cpu_p95": median(item["active_cpu"]["p95"] for item in attempts),
        "active_cpu_max": median(item["active_cpu"]["max"] for item in attempts),
        "cooldown_cpu_avg": median(item["cooldown_cpu"]["avg"] for item in attempts),
        "cooldown_cpu_p95": median(item["cooldown_cpu"]["p95"] for item in attempts),
        "cooldown_cpu_max": median(item["cooldown_cpu"]["max"] for item in attempts),
        "rss_p95_kb": median(item["rss"]["p95"] for item in attempts),
        "rss_plateau_growth_kb": median(
            item["rss_plateau_growth_kb"] for item in attempts
        ),
        "throughput_per_second": median(item["throughput_per_second"] for item in attempts),
    }
