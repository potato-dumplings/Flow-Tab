#!/usr/bin/env python3
from __future__ import annotations


def _detail_value(detail: str, key: str) -> str:
    prefix = f"{key}="
    for token in detail.split(";"):
        if token.startswith(prefix):
            return token[len(prefix):]
    return ""

def _integer(row: dict[str, str], key: str) -> int:
    try:
        return int(row.get(key, "0"))
    except (TypeError, ValueError):
        return 0


def _valid_proof(row: dict[str, str]) -> bool:
    kind = row.get("proof_kind", "")
    detail = row.get("proof_detail", "")
    generation = _integer(row, "proof_generation")
    process_identifier = _integer(row, "proof_pid")
    cg_window_id = _integer(row, "proof_cg_window_id")
    window_id = row.get("proof_window_id", "")
    if kind == "sampler_readiness":
        return (
            process_identifier > 0
            and "stable-pid" in detail
            and "monotonic-ns=" in detail
        )
    if kind == "physical_shortcut":
        return all(
            token in detail
            for token in ("control-tab", "control-shift-tab", "hold-release")
        )
    if kind == "mutation_generation":
        return (
            generation > 0
            and process_identifier > 0
            and cg_window_id > 0
            and window_id not in {"", "none"}
            and "action=" in detail
            and "windows=" in detail
        )
    if kind in {"first_session", "dirty_projection_gate", "early_control_release"}:
        return generation > 0 and process_identifier > 0 and cg_window_id > 0
    if kind == "option_tab_history":
        return (
            generation > 0
            and process_identifier > 0
            and window_id not in {"", "none"}
            and "cleanup=released" in detail
            and "focused-reentry=ready" in detail
        )
    if kind == "topology_scope":
        return (
            process_identifier > 0
            and "off-space=covered" in detail
            and "noisy-cg=filtered" in detail
        )
    if kind == "exact_activation":
        return (
            process_identifier > 0
            and window_id not in {"", "none"}
            and cg_window_id > 0
            and bool(_detail_value(detail, "title"))
            and "verified-focus-readback" in detail
        )
    return True


def validate_proofs(
    proofs: list[dict[str, str]],
) -> tuple[set[str], list[str], bool]:
    valid_kinds: set[str] = set()
    invalid: list[str] = []
    mutation_generations: list[int] = []
    for row in proofs:
        kind = row.get("proof_kind", "") or "unknown"
        if row.get("proof_satisfied") != "1" or not _valid_proof(row):
            invalid.append(kind)
            continue
        valid_kinds.add(kind)
        if kind == "mutation_generation":
            mutation_generations.append(_integer(row, "proof_generation"))
    if any(
        current >= following
        for current, following in zip(
            mutation_generations,
            mutation_generations[1:],
        )
    ):
        valid_kinds.discard("mutation_generation")
        invalid.append("mutation_generation_order")
    return valid_kinds, invalid, "exact_activation" in invalid


def exact_activation_coverage(
    proofs: list[dict[str, str]], expected_window_count: int
) -> dict[str, object]:
    rows = [
        row
        for row in proofs
        if row.get("proof_kind") == "exact_activation"
        and row.get("proof_satisfied") == "1"
        and _valid_proof(row)
    ]
    process_identifiers = {
        _integer(row, "proof_pid") for row in rows
    }
    window_ids = {row.get("proof_window_id", "") for row in rows}
    cg_window_ids = {
        _integer(row, "proof_cg_window_id") for row in rows
    }
    titles = {
        _detail_value(row.get("proof_detail", ""), "title")
        for row in rows
    }
    titles.discard("")
    passed = (
        expected_window_count > 0
        and len(process_identifiers) == 1
        and len(window_ids) == expected_window_count
        and len(cg_window_ids) == expected_window_count
        and len(titles) == expected_window_count
    )
    return {
        "verdict": "passed" if passed else "failed",
        "expected_window_count": expected_window_count,
        "process_identifiers": sorted(process_identifiers),
        "window_ids": sorted(window_ids),
        "cg_window_ids": sorted(cg_window_ids),
        "titles": sorted(titles),
    }
