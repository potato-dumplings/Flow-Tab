#!/usr/bin/env python3
from __future__ import annotations

import csv
import importlib.util
import json
from pathlib import Path

from control_tab_pressure_contract import (
    OPEN_PARTITIONS,
    evaluate_attempt,
)
from control_tab_pressure_spans import (
    PROTOCOL_VERSION,
    REQUIRED_COMPONENTS,
    SCHEMA_DIGEST,
)


ROOT = Path(__file__).resolve().parent
CLI_PATH = ROOT / "control-tab-pressure-evidence.py"


def load_cli_module():
    spec = importlib.util.spec_from_file_location("control_tab_pressure_cli", CLI_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ControlTabPressureFixture:
    def write_fixture(self, root: Path, *, slow_open: bool = False, samples: bool = True):
        metrics = root / "phase-metrics.csv"
        sample_path = root / "process-samples.csv"
        runtime_status = root / "runtime-status.json"
        identity_manifest = root / "ui-app-identity.json"
        launch_receipt = root / "target-launch-receipt.json"
        cleanup_evidence = root / "application-cleanup.json"
        sampler_readiness = root / "sampling-ready.json"
        result_bundle = root / "FlowTabUITests.xcresult"
        header = [
            "record_kind", "lane", "scenario", "cycle", "sequence", "phase",
            "started_uptime_nanoseconds", "completed_uptime_nanoseconds",
            "wall_ms", "cpu_time_ms", "cpu_percent", "timing_valid", "satisfied",
            "panel_presented", "user_visible", "selected_app_id",
            "selected_window_id_before", "selected_window_id_after",
            "projected_app_count", "selected_window_count", "projection_generation",
            "activation_request_issued", "late_presentation_observed",
            "accessibility_trusted",
            "screen_capture_trusted", "partitions_reconciled", "watchdog_expired",
            "proof_kind", "proof_generation", "proof_pid", "proof_window_id",
            "proof_cg_window_id", "proof_satisfied", "proof_detail",
            "metric_kind", "metric_name", "metric_ms",
            "activation_verified", "activation_target_pid",
            "activation_target_window_id", "activation_target_cg_window_id",
            "required_components_present", "timeline_reconciled",
            "component_timing_valid", "span_parent",
            "span_started_uptime_nanoseconds",
            "span_completed_uptime_nanoseconds", "span_wall_ms",
            "span_cpu_time_ms", "span_cpu_percent", "span_timing_valid",
            "span_scope", "span_outcome", "span_work_units",
            "protocol_version", "schema_digest",
        ]
        rows: list[dict[str, str]] = []

        def blank() -> dict[str, str]:
            row = {key: "0" for key in header}
            row["protocol_version"] = str(PROTOCOL_VERSION)
            row["schema_digest"] = SCHEMA_DIGEST
            return row

        def marker(name: str, timestamp: int):
            row = blank()
            row.update(record_kind="marker", lane="ready", scenario="realistic", phase=name)
            row["started_uptime_nanoseconds"] = str(timestamp)
            row["completed_uptime_nanoseconds"] = str(timestamp)
            rows.append(row)

        marker("measurement_start", 1_000_000_000)
        proof = blank()
        proof.update(
            record_kind="proof", lane="ready", scenario="realistic",
            phase="physical_shortcut", proof_kind="physical_shortcut",
            proof_satisfied="1",
            proof_detail="control-tab,control-shift-tab,hold-release",
            metric_kind="event", metric_name="none",
        )
        rows.append(proof)
        sampler_proof = blank()
        sampler_proof.update(
            record_kind="proof", lane="ready", scenario="realistic",
            phase="sampler_readiness", proof_kind="sampler_readiness",
            proof_pid="42", proof_satisfied="1",
            proof_detail="stable-pid;monotonic-ns=1000000000",
            metric_kind="event", metric_name="none",
        )
        rows.append(sampler_proof)
        sequence = 0
        for cycle in range(1, 11):
            phases = ("open", "forward", "reverse", "commit" if cycle % 2 == 0 else "cancel")
            for phase in phases:
                sequence += 1
                if slow_open and phase == "open":
                    wall = 60.0
                elif phase in {"forward", "reverse"}:
                    wall = 8.0
                else:
                    wall = 10.0
                row = blank()
                started = 1_000_000_000 + sequence * 100_000_000
                completed = started + int(wall * 1_000_000)
                row.update(
                    record_kind="event", lane="ready", scenario="realistic",
                    cycle=str(cycle), sequence=str(sequence), phase=phase,
                    started_uptime_nanoseconds=str(started),
                    completed_uptime_nanoseconds=str(completed),
                    wall_ms=str(wall), cpu_time_ms="2", cpu_percent="20",
                    timing_valid="1", satisfied="1",
                    panel_presented="1" if phase not in {"commit", "cancel"} else "0",
                    user_visible="1" if phase not in {"commit", "cancel"} else "0",
                    selected_app_id="com.flowtab.pressure.app.0001",
                    selected_window_id_before="window-1", selected_window_id_after="window-2",
                    projected_app_count="24", selected_window_count="5",
                    projection_generation="1",
                    activation_request_issued="1" if phase == "commit" else "0",
                    activation_verified="1" if phase == "commit" else "0",
                    activation_target_pid="42" if phase == "commit" else "0",
                    activation_target_window_id="window-2",
                    activation_target_cg_window_id="102",
                    late_presentation_observed="0",
                    accessibility_trusted="1", screen_capture_trusted="1",
                    partitions_reconciled="1", watchdog_expired="0",
                    required_components_present="1", timeline_reconciled="1",
                    component_timing_valid="1",
                    metric_kind="event", metric_name="none", metric_ms="0",
                )
                rows.append(row)
                self._append_spans(
                    rows,
                    row,
                    phase,
                    started,
                    completed,
                    wall,
                )
                if phase == "open":
                    partition_values = {
                        name: 1.0 if name == "unattributed_ms" else 0.0
                        for name in OPEN_PARTITIONS
                    }
                    milestone_values = {
                        "session_ready_ms": 0.5,
                        "panel_presented_ms": 1.0,
                        "first_window_content_draw_ms": 2.0,
                        "visibility_readback_ms": 3.0,
                        "first_visible_frame_ms": 3.0,
                        "cached_first_frame_ms": 3.0,
                        "cached_first_frame_cpu_time_ms": 0.5,
                        "fresh_visible_previews_complete_ms": 6.0,
                        "fresh_visible_previews_complete_cpu_time_ms": 1.5,
                        "command_return_ms": 8.0,
                    }
                    for kind, values in (
                        ("partition", partition_values),
                        ("milestone", milestone_values),
                    ):
                        for name, value in values.items():
                            metric = dict(row)
                            metric["metric_kind"] = kind
                            metric["metric_name"] = name
                            metric["metric_ms"] = str(value)
                            rows.append(metric)
                else:
                    metric = dict(row)
                    metric["metric_kind"] = "partition"
                    metric["metric_name"] = "command_execution_ms"
                    metric["metric_ms"] = "6"
                    rows.append(metric)
                    metric = dict(row)
                    metric["metric_kind"] = "milestone"
                    metric["metric_name"] = "command_return_ms"
                    metric["metric_ms"] = "6"
                    rows.append(metric)
                    if phase == "commit":
                        for name, value in {
                            "activation_request_ms": 4,
                            "panel_hidden_ms": 5,
                            "focus_verified_ms": 7,
                            "cleanup_complete_ms": 8,
                        }.items():
                            metric = dict(row)
                            metric["metric_kind"] = "milestone"
                            metric["metric_name"] = name
                            metric["metric_ms"] = str(value)
                            rows.append(metric)
                    elif phase == "cancel":
                        for name, value in {
                            "panel_hidden_ms": 4,
                            "cleanup_complete_ms": 7,
                        }.items():
                            metric = dict(row)
                            metric["metric_kind"] = "milestone"
                            metric["metric_name"] = name
                            metric["metric_ms"] = str(value)
                            rows.append(metric)
        marker("cooldown_start", 11_000_000_000)
        cooldown = blank()
        cooldown.update(
            record_kind="event", lane="ready", scenario="realistic", cycle="0",
            sequence=str(sequence + 1), phase="cooldown",
            started_uptime_nanoseconds="11000000000",
            completed_uptime_nanoseconds="13000000000", wall_ms="2000",
            cpu_time_ms="20", cpu_percent="1", timing_valid="1", satisfied="1",
            selected_app_id="none", projected_app_count="24", selected_window_count="0",
            accessibility_trusted="1", screen_capture_trusted="1",
            partitions_reconciled="1", watchdog_expired="0",
            required_components_present="1", timeline_reconciled="1",
            component_timing_valid="1",
            late_presentation_observed="0",
            metric_kind="event", metric_name="none", metric_ms="0",
        )
        rows.append(cooldown)
        self._append_spans(
            rows,
            cooldown,
            "cooldown",
            11_000_000_000,
            13_000_000_000,
            2000.0,
            cpu_time_ms=20.0,
        )
        cooldown_partition = dict(cooldown)
        cooldown_partition["metric_kind"] = "partition"
        cooldown_partition["metric_name"] = "command_execution_ms"
        cooldown_partition["metric_ms"] = "2000"
        rows.append(cooldown_partition)
        cooldown_milestone = dict(cooldown)
        cooldown_milestone["metric_kind"] = "milestone"
        cooldown_milestone["metric_name"] = "command_return_ms"
        cooldown_milestone["metric_ms"] = "2000"
        rows.append(cooldown_milestone)
        marker("cooldown_end", 13_000_000_000)
        with metrics.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=header)
            writer.writeheader()
            writer.writerows(rows)

        with sample_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow([
                "sample", "timestamp", "pid", "interval_started_uptime_nanoseconds",
                "interval_completed_uptime_nanoseconds", "cpu_percent", "rss_kb",
            ])
            if samples:
                sample = 0
                for start in range(1_000_000_000, 13_000_000_000, 500_000_000):
                    sample += 1
                    cpu = 20 if start < 11_000_000_000 else 1
                    writer.writerow([sample, "now", 42, start, start + 500_000_000, cpu, 100_000])
        runtime_status.write_text(
            json.dumps({
                "application_cleanup_exit_code": 0,
                "application_cleanup_evidence_present": True,
                "target_termination_verdict": "not_observed",
                "identity_verdict": "matched",
                "target_launch_receipt_present": True,
                "ui_result_bundle_valid": True,
                "final_exit_code": 0,
                "ui_wrapper_exit_code": 0,
                "sampling_failed": False,
                "sampling_readiness_present": True,
                "termination_timed_out": False,
            }),
            encoding="utf-8",
        )
        identity_manifest.write_text("{}\n", encoding="utf-8")
        launch_receipt.write_text("{}\n", encoding="utf-8")
        cleanup_evidence.write_text("{}\n", encoding="utf-8")
        sampler_readiness.write_text("{}\n", encoding="utf-8")
        result_bundle.mkdir()
        return metrics, sample_path, runtime_status

    @staticmethod
    def _append_spans(
        rows: list[dict[str, str]],
        event: dict[str, str],
        phase: str,
        started: int,
        completed: int,
        wall_ms: float,
        cpu_time_ms: float = 2.0,
    ) -> None:
        for name in sorted(REQUIRED_COMPONENTS[phase]):
            span = dict(event)
            span.update(
                record_kind="span",
                metric_kind="component_inclusive",
                metric_name=name,
                metric_ms="0",
                span_parent="none",
                span_started_uptime_nanoseconds=str(started),
                span_completed_uptime_nanoseconds=str(started),
                span_wall_ms="0",
                span_cpu_time_ms="0",
                span_cpu_percent="0",
                span_timing_valid="1",
                span_scope="component_inclusive",
                span_outcome="completed",
                span_work_units="1",
            )
            rows.append(span)
        timeline = dict(event)
        timeline.update(
            record_kind="span",
            metric_kind="timeline_exclusive",
            metric_name="unattributed",
            metric_ms=str(wall_ms),
            span_parent="none",
            span_started_uptime_nanoseconds=str(started),
            span_completed_uptime_nanoseconds=str(completed),
            span_wall_ms=str(wall_ms),
            span_cpu_time_ms=str(cpu_time_ms),
            span_cpu_percent=str(100.0 * cpu_time_ms / wall_ms),
            span_timing_valid="1",
            span_scope="timeline_exclusive",
            span_outcome="completed",
            span_work_units="0",
        )
        rows.append(timeline)

    def evaluate(self, root: Path, **kwargs):
        paths = self.write_fixture(root, **kwargs)
        return self.evaluate_paths(root, paths)

    def evaluate_paths(self, root: Path, paths):
        return evaluate_attempt(
            *paths,
            "ready",
            "realistic",
            24,
            5,
            identity_manifest_path=root / "ui-app-identity.json",
            target_launch_receipt_path=root / "target-launch-receipt.json",
            cleanup_evidence_path=root / "application-cleanup.json",
            sampler_readiness_path=root / "sampling-ready.json",
            result_bundle_path=root / "FlowTabUITests.xcresult",
        )

    def rewrite_metrics(self, path: Path, transform):
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            header = reader.fieldnames
            assert header
            rows = transform(list(reader))
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=header)
            writer.writeheader()
            writer.writerows(rows)
