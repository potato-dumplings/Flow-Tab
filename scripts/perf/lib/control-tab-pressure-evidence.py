#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any

from control_tab_pressure_contract import (
    compatible_identity,
    evaluate_attempt,
    median_attempts,
)
from control_tab_pressure_baseline import baseline_candidate, regression_map
from control_tab_pressure_spans import root_cause_rankings


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def write_attempt_summary(path: Path, result: dict[str, Any]) -> None:
    lines = [
        f"overall_verdict={result['overall_verdict']}",
        f"lane={result['identity']['lane']}",
        f"scenario={result['identity']['scenario']}",
        f"events={result['event_count']}",
        f"app_count={result.get('scale', {}).get('app_count', 0)}",
        f"window_count={result.get('scale', {}).get('window_count', 0)}",
        "observed_app_counts="
        + ",".join(
            str(value)
            for value in result.get("scale", {}).get(
                "observed_app_counts", []
            )
        ),
        "observed_window_counts="
        + ",".join(
            str(value)
            for value in result.get("scale", {}).get(
                "observed_window_counts", []
            )
        ),
        f"throughput_per_second={result['throughput_per_second']:.6f}",
    ]
    for phase, metrics in result["phases"].items():
        for statistic in ("p50", "p95", "max"):
            lines.append(
                f"phase.{phase}.wall_ms.{statistic}="
                f"{metrics['wall_ms'][statistic]:.6f}"
            )
            lines.append(
                f"phase.{phase}.cpu_time_ms.{statistic}="
                f"{metrics['cpu_time_ms'][statistic]:.6f}"
            )
        lines.append(
            f"phase.{phase}.cpu_percent={metrics['cpu_percent']:.6f}"
        )
        if "activation_request_ms" in metrics:
            for statistic in ("p50", "p95", "max"):
                lines.append(
                    f"phase.{phase}.activation_request_ms.{statistic}="
                    f"{metrics['activation_request_ms'][statistic]:.6f}"
                )
    for phase, kinds in result.get("paths", {}).items():
        for kind, metrics in kinds.items():
            for name, values in metrics.items():
                for statistic in ("p50", "p95", "max"):
                    lines.append(
                        f"path.{phase}.{kind}.{name}.{statistic}="
                        f"{values[statistic]:.6f}"
                    )
    for phase, scopes in result.get("spans", {}).items():
        for scope, components in scopes.items():
            for name, values in components.items():
                for metric in ("wall_ms", "cpu_time_ms"):
                    for statistic in ("p50", "p95", "max"):
                        lines.append(
                            f"span.{phase}.{scope}.{name}.{metric}."
                            f"{statistic}={values[metric][statistic]:.6f}"
                        )
                lines.append(
                    f"span.{phase}.{scope}.{name}.cpu_percent="
                    f"{values['cpu_percent']:.6f}"
                )
                lines.append(
                    f"span.{phase}.{scope}.{name}.count={values['count']}"
                )
                lines.append(
                    f"span.{phase}.{scope}.{name}.overlap="
                    f"{int(values['overlap'])}"
                )
                lines.append(
                    f"span.{phase}.{scope}.{name}.outcomes="
                    + ",".join(
                        f"{outcome}:{count}"
                        for outcome, count in values["outcomes"].items()
                    )
                )
    for phase, values in result.get("component_coverage", {}).items():
        for metric in (
            "union_wall_ms",
            "inclusive_wall_ms",
            "overlap_wall_ms",
            "union_coverage",
        ):
            lines.append(
                f"component_coverage.{phase}.{metric}="
                f"{values[metric]:.6f}"
            )
    for phase, rankings in result.get("root_causes", {}).items():
        for dimension, entries in rankings.items():
            for index, entry in enumerate(entries[:3], start=1):
                lines.append(
                    f"root_cause.{phase}.{dimension}.{index}="
                    f"{entry['name']};cpu_time_p95_ms="
                    f"{entry['cpu_time_p95_ms']:.6f};cpu_percent="
                    f"{entry['cpu_percent']:.6f};wall_p95_ms="
                    f"{entry['wall_p95_ms']:.6f};overlap="
                    f"{int(entry['overlap'])}"
                )
    for breakdown in result.get("breakdowns", []):
        prefix = (
            f"breakdown.{breakdown['phase']}.apps-"
            f"{breakdown['app_count']}.windows-{breakdown['window_count']}"
        )
        if breakdown.get("projection_generation") is not None:
            prefix += f".generation-{breakdown['projection_generation']}"
        if breakdown.get("target_window_id") is not None:
            prefix += (
                f".target-{breakdown['target_pid']}-"
                f"{breakdown['target_window_id']}-"
                f"{breakdown['target_cg_window_id']}"
            )
        for metric in ("wall_ms", "cpu_time_ms"):
            for statistic in ("p50", "p95", "max"):
                lines.append(
                    f"{prefix}.{metric}.{statistic}="
                    f"{breakdown[metric][statistic]:.6f}"
                )
        lines.append(
            f"{prefix}.cpu_percent={breakdown['cpu_percent']:.6f}"
        )
        lines.append(f"{prefix}.count={breakdown['event_count']}")
        for name, values in breakdown.get("components", {}).items():
            component = f"{prefix}.component.{name}"
            lines.append(
                f"{component}.wall_ms.p95={values['wall_ms']['p95']:.6f}"
            )
            lines.append(
                f"{component}.cpu_time_ms.p95="
                f"{values['cpu_time_ms']['p95']:.6f}"
            )
            lines.append(
                f"{component}.cpu_percent={values['cpu_percent']:.6f}"
            )
            lines.append(f"{component}.count={values['count']}")
            lines.append(
                f"{component}.outcomes="
                + ",".join(
                    f"{outcome}:{count}"
                    for outcome, count in values["outcomes"].items()
                )
            )
    for item in result.get("mutation_generations", []):
        lines.append(
            f"mutation_generation.{item['generation']}="
            f"pid:{item['pid']};{item['detail']}"
        )
    for index, item in enumerate(
        result.get("topology_targets", []), start=1
    ):
        lines.append(
            f"topology_target.{index}=pid:{item['pid']};"
            f"window:{item['window_id']};cg:{item['cg_window_id']}"
        )
    if result["active_cpu"]:
        for key in ("avg", "p95", "max"):
            lines.append(f"active_cpu.{key}={result['active_cpu'][key]:.6f}")
    if result["cooldown_cpu"]:
        for key in ("avg", "p95", "max"):
            lines.append(f"cooldown_cpu.{key}={result['cooldown_cpu'][key]:.6f}")
    if result["rss"]:
        for key in ("avg", "p95", "max"):
            lines.append(f"rss_kb.{key}={result['rss'][key]:.6f}")
    lines.append(
        f"rss_plateau_growth_kb={result['rss_plateau_growth_kb']:.6f}"
    )
    for category, value in result["categories"].items():
        lines.append(f"category.{category}={value['verdict']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def failed_attempt(
    lane: str, scenario: str, message: str
) -> dict[str, Any]:
    categories = {
        name: {"verdict": "failed", "reason": message}
        for name in (
            "correctness",
            "latency",
            "cpu",
            "rss",
            "evidence",
            "cleanup",
            "product_slo",
        )
    }
    return {
        "schema_version": 1,
        "identity": {"lane": lane, "scenario": scenario},
        "overall_verdict": "failed",
        "permission_blocked": False,
        "categories": categories,
        "phases": {},
        "paths": {},
        "active_cpu": None,
        "cooldown_cpu": None,
        "rss": None,
        "rss_plateau_growth_kb": 0,
        "throughput_per_second": 0,
        "event_count": 0,
        "breakdowns": [],
        "mutation_generations": [],
        "topology_targets": [],
    }


def evaluate_command(args: argparse.Namespace) -> int:
    try:
        result = evaluate_attempt(
            Path(args.metrics),
            Path(args.samples),
            Path(args.runtime_status),
            args.lane,
            args.scenario,
            args.expected_app_count,
            args.expected_window_count,
            Path(args.attachment_manifest)
            if args.attachment_manifest
            else None,
            Path(args.identity_manifest),
            Path(args.target_launch_receipt),
            Path(args.cleanup_evidence),
            Path(args.sampler_readiness),
            Path(args.result_bundle),
        )
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        AttributeError,
        IndexError,
        csv.Error,
        json.JSONDecodeError,
    ) as error:
        result = failed_attempt(args.lane, args.scenario, str(error))
    write_json(Path(args.output), result)
    write_attempt_summary(Path(args.summary), result)
    print(Path(args.summary).read_text(encoding="utf-8"), end="")
    return 0 if result["overall_verdict"] == "passed" else 1


def aggregate_command(args: argparse.Namespace) -> int:
    attempts = [
        json.loads(Path(path).read_text(encoding="utf-8"))
        for path in args.attempt_summary
    ]
    identity = attempts[0]["identity"] if attempts else {}
    compatible_attempts = all(
        compatible_identity(item["identity"], identity) for item in attempts
    )
    attempts_green = bool(attempts) and all(
        item["overall_verdict"] == "passed" for item in attempts
    )
    aggregatable_attempts = [
        item
        for item in attempts
        if (
            isinstance(item.get("active_cpu"), dict)
            and isinstance(item.get("cooldown_cpu"), dict)
            and isinstance(item.get("rss"), dict)
            and isinstance(item.get("rss_plateau_growth_kb"), (int, float))
            and all(
                phase in item.get("phases", {})
                for phase in (
                    "open",
                    "forward",
                    "reverse",
                    "commit",
                    "cancel",
                    "cooldown",
                )
            )
        )
    ]
    attempts_aggregatable = bool(attempts) and (
        len(aggregatable_attempts) == len(attempts)
    )
    aggregatable_identity = (
        aggregatable_attempts[0]["identity"] if aggregatable_attempts else {}
    )
    aggregatable_attempts_compatible = bool(aggregatable_attempts) and all(
        compatible_identity(item["identity"], aggregatable_identity)
        for item in aggregatable_attempts
    )
    baseline_eligible = (
        compatible_attempts
        and attempts_aggregatable
        and attempts_green
        and len(attempts) == 3
    )
    medians = (
        median_attempts(aggregatable_attempts)
        if aggregatable_attempts_compatible
        else {}
    )
    baseline = None
    baseline_verdict = (
        "recorded_new_baseline"
        if baseline_eligible
        else (
            "not_recorded_attempt_count"
            if attempts_green
            else "not_recorded_non_green"
        )
    )
    regressions: dict[str, Any] = {}
    if args.baseline_summary and baseline_eligible:
        try:
            baseline = baseline_candidate(Path(args.baseline_summary), identity)
        except (OSError, KeyError, json.JSONDecodeError):
            baseline = None
        if baseline is not None:
            baseline_verdict = "compared"
            regressions = regression_map(medians, baseline["medians"])

    category_names = (
        "correctness",
        "latency",
        "cpu",
        "rss",
        "evidence",
        "cleanup",
        "product_slo",
    )
    categories = {
        name: {
            "verdict": (
                "passed"
                if attempts
                and all(
                    item["categories"][name]["verdict"] == "passed"
                    for item in attempts
                )
                else "failed"
            )
        }
        for name in category_names
    }
    overall = (
        "passed"
        if compatible_attempts and attempts_green and not regressions
        else (
            "blocked"
            if any(item["overall_verdict"] == "blocked" for item in attempts)
            else "failed"
        )
    )
    result = {
        "schema_version": 1,
        "identity": identity,
        "overall_verdict": overall,
        "attempt_count": len(attempts),
        "aggregated_attempt_count": len(aggregatable_attempts),
        "attempts_compatible": compatible_attempts,
        "attempts_aggregatable": attempts_aggregatable,
        "aggregatable_attempts_compatible": aggregatable_attempts_compatible,
        "baseline_eligible": baseline_eligible,
        "categories": categories,
        "medians": medians,
        "root_causes": root_cause_rankings(
            medians.get("spans", {})
        ),
        "attempt_breakdowns": [
            {
                "attempt": index,
                "groups": item.get("breakdowns", []),
            }
            for index, item in enumerate(attempts, start=1)
        ],
        "mutation_generations": [
            {
                "attempt": index,
                "evidence": item.get("mutation_generations", []),
            }
            for index, item in enumerate(attempts, start=1)
            if item.get("mutation_generations")
        ],
        "topology_targets": [
            {
                "attempt": index,
                "targets": item.get("topology_targets", []),
            }
            for index, item in enumerate(attempts, start=1)
            if item.get("topology_targets")
        ],
        "baseline": {
            "verdict": baseline_verdict,
            "path": args.baseline_summary,
            "regressions": regressions,
        },
        "attempt_verdicts": [item["overall_verdict"] for item in attempts],
    }
    write_json(Path(args.output), result)
    lines = [
        f"overall_verdict={overall}",
        f"attempt_count={len(attempts)}",
        f"baseline_verdict={baseline_verdict}",
        f"regression_count={len(regressions)}",
    ]
    for key, value in medians.items():
        if key not in {"phases", "paths", "spans"}:
            lines.append(f"median.{key}={value:.6f}")
    for phase, values in medians.get("phases", {}).items():
        for key, value in values.items():
            lines.append(f"median.phase.{phase}.{key}={value:.6f}")
    for phase, kinds in medians.get("paths", {}).items():
        for kind, metrics in kinds.items():
            for name, values in metrics.items():
                for statistic, value in values.items():
                    lines.append(
                        f"median.path.{phase}.{kind}.{name}."
                        f"{statistic}={value:.6f}"
                    )
    for phase, scopes in medians.get("spans", {}).items():
        for scope, components in scopes.items():
            for name, values in components.items():
                for metric in ("wall_ms", "cpu_time_ms"):
                    for statistic, value in values[metric].items():
                        lines.append(
                            f"median.span.{phase}.{scope}.{name}."
                            f"{metric}.{statistic}={value:.6f}"
                        )
                lines.append(
                    f"median.span.{phase}.{scope}.{name}.cpu_percent="
                    f"{values['cpu_percent']:.6f}"
                )
    for phase, rankings in result.get("root_causes", {}).items():
        for dimension, entries in rankings.items():
            for index, entry in enumerate(entries[:3], start=1):
                lines.append(
                    f"root_cause.{phase}.{dimension}.{index}="
                    f"{entry['name']};cpu_time_p95_ms="
                    f"{entry['cpu_time_p95_ms']:.6f};cpu_percent="
                    f"{entry['cpu_percent']:.6f};wall_p95_ms="
                    f"{entry['wall_p95_ms']:.6f};overlap="
                    f"{int(entry['overlap'])}"
                )
    for attempt in result.get("mutation_generations", []):
        for item in attempt["evidence"]:
            lines.append(
                f"attempt.{attempt['attempt']}.mutation_generation."
                f"{item['generation']}=pid:{item['pid']};{item['detail']}"
            )
    for attempt in result.get("topology_targets", []):
        for index, item in enumerate(attempt["targets"], start=1):
            lines.append(
                f"attempt.{attempt['attempt']}.topology_target.{index}="
                f"pid:{item['pid']};window:{item['window_id']};"
                f"cg:{item['cg_window_id']}"
            )
    Path(args.summary).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(Path(args.summary).read_text(encoding="utf-8"), end="")
    return 0 if overall == "passed" else 1


def matrix_command(args: argparse.Namespace) -> int:
    scenarios = [
        json.loads(Path(path).read_text(encoding="utf-8"))
        for path in args.scenario_summary
    ]
    scenario_map = {
        f"{item['identity']['lane']}/{item['identity']['scenario']}": item
        for item in scenarios
    }
    overall = (
        "passed"
        if scenarios and all(item["overall_verdict"] == "passed" for item in scenarios)
        else (
            "blocked"
            if any(item["overall_verdict"] == "blocked" for item in scenarios)
            else "failed"
        )
    )
    result = {
        "schema_version": 1,
        "runner_kind": "control_tab_pressure",
        "overall_verdict": overall,
        "scenarios": scenario_map,
        "scenario_summaries": scenarios,
    }
    write_json(Path(args.output), result)
    Path(args.summary).write_text(
        "\n".join(
            [f"overall_verdict={overall}"]
            + [f"{key}={value['overall_verdict']}" for key, value in scenario_map.items()]
        )
        + "\n",
        encoding="utf-8",
    )
    print(Path(args.summary).read_text(encoding="utf-8"), end="")
    return 0 if overall == "passed" else 1


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    evaluate = commands.add_parser("evaluate")
    evaluate.add_argument("--metrics", required=True)
    evaluate.add_argument("--samples", required=True)
    evaluate.add_argument("--runtime-status", required=True)
    evaluate.add_argument("--lane", required=True)
    evaluate.add_argument("--scenario", required=True)
    evaluate.add_argument("--expected-app-count", type=int, required=True)
    evaluate.add_argument("--expected-window-count", type=int, required=True)
    evaluate.add_argument("--attachment-manifest")
    evaluate.add_argument("--identity-manifest", required=True)
    evaluate.add_argument("--target-launch-receipt", required=True)
    evaluate.add_argument("--cleanup-evidence", required=True)
    evaluate.add_argument("--sampler-readiness", required=True)
    evaluate.add_argument("--result-bundle", required=True)
    evaluate.add_argument("--output", required=True)
    evaluate.add_argument("--summary", required=True)
    evaluate.set_defaults(handler=evaluate_command)

    aggregate = commands.add_parser("aggregate")
    aggregate.add_argument("--attempt-summary", action="append", required=True)
    aggregate.add_argument("--baseline-summary")
    aggregate.add_argument("--output", required=True)
    aggregate.add_argument("--summary", required=True)
    aggregate.set_defaults(handler=aggregate_command)

    matrix = commands.add_parser("matrix")
    matrix.add_argument("--scenario-summary", action="append", required=True)
    matrix.add_argument("--output", required=True)
    matrix.add_argument("--summary", required=True)
    matrix.set_defaults(handler=matrix_command)
    return root


def main() -> int:
    args = parser().parse_args()
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main())
