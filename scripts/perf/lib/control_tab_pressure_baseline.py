#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from control_tab_pressure_contract import compatible_identity


def regression_map(
    current: dict[str, Any], baseline: dict[str, Any]
) -> dict[str, dict[str, float]]:
    regressions: dict[str, dict[str, float]] = {}

    def compare(name: str, value: float, old: float, higher_is_better: bool = False) -> None:
        if old <= 0:
            return
        regression = (old - value) / old if higher_is_better else (value - old) / old
        if regression > 0.05:
            regressions[name] = {
                "current": value,
                "baseline": old,
                "regression_fraction": regression,
            }

    for phase, metrics in current["phases"].items():
        baseline_phase = baseline["phases"][phase]
        compare(
            f"phase.{phase}.p95_wall_ms",
            metrics["p95_wall_ms"],
            baseline_phase["p95_wall_ms"],
        )
        compare(
            f"phase.{phase}.p95_cpu_time_ms",
            metrics["p95_cpu_time_ms"],
            baseline_phase["p95_cpu_time_ms"],
        )
        compare(
            f"phase.{phase}.cpu_percent",
            metrics["cpu_percent"],
            baseline_phase["cpu_percent"],
        )
    for statistic in ("avg", "p95", "max"):
        key = f"active_cpu_{statistic}"
        if key in current and key in baseline:
            compare(key, current[key], baseline[key])
    for phase, scopes in current.get("spans", {}).items():
        baseline_scopes = baseline.get("spans", {}).get(phase, {})
        components = scopes.get("component_inclusive", {})
        baseline_components = baseline_scopes.get(
            "component_inclusive", {}
        )
        for name, metrics in components.items():
            if name not in baseline_components:
                continue
            old = baseline_components[name]
            compare(
                f"span.{phase}.{name}.wall_ms.p95",
                metrics["wall_ms"]["p95"],
                old["wall_ms"]["p95"],
            )
            compare(
                f"span.{phase}.{name}.cpu_time_ms.p95",
                metrics["cpu_time_ms"]["p95"],
                old["cpu_time_ms"]["p95"],
            )
            compare(
                f"span.{phase}.{name}.cpu_percent",
                metrics["cpu_percent"],
                old["cpu_percent"],
            )
    compare("rss_p95_kb", current["rss_p95_kb"], baseline["rss_p95_kb"])
    compare(
        "throughput_per_second",
        current["throughput_per_second"],
        baseline["throughput_per_second"],
        higher_is_better=True,
    )
    return regressions


def baseline_candidate(
    path: Path, identity: dict[str, Any]
) -> dict[str, Any] | None:
    document = json.loads(path.read_text(encoding="utf-8"))
    candidates = document.get("scenario_summaries", [document])
    for candidate in candidates:
        medians = candidate.get("medians")
        if (
            candidate.get("overall_verdict") == "passed"
            and candidate.get("attempt_count") == 3
            and compatible_identity(candidate.get("identity", {}), identity)
            and isinstance(medians, dict)
            and medians.get("phases")
            and medians.get("spans")
            and all(
                phase in medians["phases"]
                and "p95_wall_ms" in medians["phases"][phase]
                and "p95_cpu_time_ms" in medians["phases"][phase]
                and "cpu_percent" in medians["phases"][phase]
                for phase in (
                    "open", "forward", "reverse", "commit", "cancel", "cooldown"
                )
            )
        ):
            return candidate
    return None
