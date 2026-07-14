#!/usr/bin/env python3
import csv
import math
import re
import sys


def percentile(values: list[float], percentile_value: int) -> float:
    ordered = sorted(values)
    index = math.ceil((percentile_value / 100.0) * len(ordered)) - 1
    return ordered[max(0, min(index, len(ordered) - 1))]


def main() -> int:
    (
        samples_path,
        summary_path,
        sample_interval,
        minimum_sample_seconds,
        scenario,
        test_status,
        test_log_path,
        summary_facts_path,
        rhythm_contract_id,
    ) = sys.argv[1:10]
    sample_interval_value = float(sample_interval)
    minimum_duration = float(minimum_sample_seconds)
    cadence_tolerance_seconds = sample_interval_value * 2.5

    with open(samples_path, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise SystemExit("No process samples collected.")

    cpu_values = [float(row["cpu_percent"]) for row in rows]
    rss_kb_values = [float(row["rss_kb"]) for row in rows]
    valid_rows = [
        row
        for row in rows
        if row["scenario"] == scenario
        and row["workload_live"] == "true"
        and row["rhythm_conformance"] == "conformant"
        and row["rhythm_contract_id"] == rhythm_contract_id
    ]
    valid_sample_count = len(valid_rows)
    active_sampling_seconds = 0.0
    cadence_gap_count = 0
    for previous, current in zip(rows, rows[1:]):
        pair_is_valid = all(
            row["scenario"] == scenario
            and row["workload_live"] == "true"
            and row["rhythm_conformance"] == "conformant"
            and row["rhythm_contract_id"] == rhythm_contract_id
            for row in (previous, current)
        )
        if not pair_is_valid:
            continue
        delta_seconds = (
            int(current["monotonic_ns"]) - int(previous["monotonic_ns"])
        ) / 1_000_000_000.0
        if 0 < delta_seconds <= cadence_tolerance_seconds:
            active_sampling_seconds += delta_seconds
        else:
            cadence_gap_count += 1

    minimum_sample_count = math.ceil(minimum_duration / cadence_tolerance_seconds) + 1
    search_metrics: list[str] = []
    metric_families: set[str] = set()
    batch_count = 0
    metric_pattern = re.compile(
        r"\[(SearchPerformanceWindowScope|SearchPressureUnified|SearchPressureSegmented|SearchPressureWorkloadMatrix|CommittedSearchIndexPressure)\].*"
    )
    batch_pattern = re.compile(
        r"\[SearchCommittedIndexPressureBatch\].*wrapperStatus=0.*logStatus=0"
    )
    with open(test_log_path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = metric_pattern.search(line)
            if match:
                metric_families.add(match.group(1))
                search_metrics.append(match.group(0).strip())
            if batch_pattern.search(line):
                batch_count += 1

    required_metric_families = {
        "realistic": {"SearchPerformanceWindowScope", "CommittedSearchIndexPressure"},
        "stress": {
            "SearchPressureUnified",
            "SearchPressureSegmented",
            "SearchPressureWorkloadMatrix",
            "CommittedSearchIndexPressure",
        },
    }[scenario]
    missing_metric_families = sorted(required_metric_families - metric_families)
    active_sampling_verdict = (
        "passed"
        if active_sampling_seconds >= minimum_duration
        and valid_sample_count >= minimum_sample_count
        else "failed"
    )
    rhythm_conformance_verdict = (
        "conformant"
        if not missing_metric_families and valid_sample_count > 0
        else "nonconformant"
    )

    summary = [
        "Committed-index Search pressure summary",
        f"scenario={scenario}",
        f"rhythmContractID={rhythm_contract_id}",
        f"rhythmConformanceVerdict={rhythm_conformance_verdict}",
        f"lastTestWrapperStatus={test_status}",
        f"sampleIntervalSeconds={sample_interval}",
        f"cadenceToleranceSeconds={cadence_tolerance_seconds:.3f}",
        f"minSampleSeconds={minimum_sample_seconds}",
        f"activeSamplingSeconds={active_sampling_seconds:.3f}",
        f"activeSamplingVerdict={active_sampling_verdict}",
        f"validSamples={valid_sample_count}",
        f"minimumSamples={minimum_sample_count}",
        f"cadenceGaps={cadence_gap_count}",
        f"successfulTestBatches={batch_count}",
        f"samples={len(rows)}",
        f"cpuAvg={sum(cpu_values) / len(cpu_values):.2f}",
        f"cpuP95={percentile(cpu_values, 95):.2f}",
        f"cpuMax={max(cpu_values):.2f}",
        f"rssAvgMB={(sum(rss_kb_values) / len(rss_kb_values)) / 1024.0:.2f}",
        f"rssP95MB={percentile(rss_kb_values, 95) / 1024.0:.2f}",
        f"rssMaxMB={max(rss_kb_values) / 1024.0:.2f}",
    ]
    if search_metrics:
        summary.append("searchMetrics:")
        summary.extend(search_metrics)
    if missing_metric_families:
        summary.append("missingMetricFamilies=" + ",".join(missing_metric_families))

    with open(summary_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(summary))
        handle.write("\n")
    with open(summary_facts_path, "w", encoding="utf-8") as handle:
        handle.write(f"active_sampling_seconds={active_sampling_seconds:.3f}\n")
        handle.write(f"valid_sample_count={valid_sample_count}\n")
        handle.write(f"minimum_sample_count={minimum_sample_count}\n")
        handle.write(f"cadence_gap_count={cadence_gap_count}\n")
        handle.write(f"active_sampling_verdict={active_sampling_verdict}\n")
        handle.write(f"rhythm_conformance_verdict={rhythm_conformance_verdict}\n")
    print("\n".join(summary))

    errors = []
    if active_sampling_verdict != "passed":
        errors.append("active sampling duration or minimum sample count was not satisfied")
    if rhythm_conformance_verdict != "conformant":
        errors.append("scenario rhythm evidence was incomplete")
    if batch_count < 1:
        errors.append("no successful test batch was recorded")
    if errors:
        raise SystemExit("; ".join(errors))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
