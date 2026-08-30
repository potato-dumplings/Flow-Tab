import csv
import math
import os
import re


LOG_CAPACITY = 20
RSS_ABSOLUTE_GROWTH_ALLOWANCE_KB = 32 * 1024
RSS_RELATIVE_GROWTH_ALLOWANCE = 0.15
ACTIVE_RESOURCE_COVERAGE_MINIMUM = 0.90
TAB_SWITCH_WARMUP_MARKER = (
    "FlowTabTabSwitchStressEvidence phase=started"
)
TAB_SWITCH_COMPLETION_MARKER = (
    "FlowTabTabSwitchStressEvidence phase=completed"
)
RUNTIME_LOG_LINE_PATTERN = re.compile(
    r"^\[[^\]]+\] \[[^\]]+\] \[([^\]]+)\] ?(.*)$"
)


def percentile(values, value):
    ordered = sorted(values)
    if not ordered:
        return None
    index = math.ceil(len(ordered) * value / 100.0) - 1
    return ordered[max(0, min(index, len(ordered) - 1))]


def load_samples(path):
    with open(path, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    samples = []
    for row in rows:
        interval_started = row.get(
            "interval_started_uptime_nanoseconds", ""
        )
        interval_completed = row.get(
            "interval_completed_uptime_nanoseconds", ""
        )
        samples.append(
            {
                "cpu": float(row["cpu_percent"]),
                "rss_kb": float(row["rss_kb"]),
                "interval_started_uptime_nanoseconds": (
                    int(interval_started) if interval_started else None
                ),
                "interval_completed_uptime_nanoseconds": (
                    int(interval_completed) if interval_completed else None
                ),
            }
        )
    return samples


def load_samples_or_empty(path):
    return load_samples(path) if os.path.isfile(path) else []


def runtime_log_paths(runtime_home):
    directory = os.path.join(
        runtime_home,
        "Library",
        "Application Support",
        "FlowTab",
        "logs",
    )
    if not os.path.isdir(directory):
        return []
    return [
        os.path.join(directory, name)
        for name in sorted(os.listdir(directory))
        if name.endswith(".log")
    ]


def log_volume(runtime_home, elapsed_seconds, completed_switches):
    paths = runtime_log_paths(runtime_home)
    retained_bytes = sum(os.path.getsize(path) for path in paths)
    line_count = 0
    for path in paths:
        with open(path, "rb") as handle:
            line_count += sum(1 for _ in handle)
    seconds = max(elapsed_seconds, 0.000001)
    switches = max(completed_switches, 1)
    return {
        "file_count": len(paths),
        "line_count": line_count,
        "retained_bytes": retained_bytes,
        "bytes_per_second": retained_bytes / seconds,
        "megabytes_per_minute": (
            retained_bytes * 60 / seconds / 1_000_000
        ),
        "bytes_per_completed_switch": retained_bytes / switches,
        "capacity_saturated": len(paths) >= LOG_CAPACITY,
    }


def ranked_log_usage(usage, name_key):
    return [
        {
            name_key: name,
            "line_count": values["line_count"],
            "bytes": values["bytes"],
        }
        for name, values in sorted(
            usage.items(),
            key=lambda item: (-item[1]["bytes"], item[0]),
        )[:10]
    ]


def active_log_volume(
    runtime_home,
    elapsed_seconds,
    completed_switches,
):
    paths = runtime_log_paths(runtime_home)
    active = False
    started_count = 0
    completed_count = 0
    retained_bytes = 0
    line_count = 0
    active_paths = set()
    categories = {}
    events = {}

    for path in paths:
        with open(path, "rb") as handle:
            for raw_line in handle:
                line = raw_line.decode("utf-8", errors="replace")
                if TAB_SWITCH_WARMUP_MARKER in line:
                    started_count += 1
                    active = True
                if active:
                    retained_bytes += len(raw_line)
                    line_count += 1
                    active_paths.add(path)
                    match = RUNTIME_LOG_LINE_PATTERN.match(
                        line.rstrip("\r\n")
                    )
                    if match:
                        category = match.group(1)
                        message = match.group(2)
                        event = (
                            message.split(maxsplit=1)[0]
                            if message
                            else "empty"
                        )
                        for usage, name in (
                            (categories, category),
                            (events, event),
                        ):
                            values = usage.setdefault(
                                name,
                                {"line_count": 0, "bytes": 0},
                            )
                            values["line_count"] += 1
                            values["bytes"] += len(raw_line)
                if active and TAB_SWITCH_COMPLETION_MARKER in line:
                    completed_count += 1
                    active = False

    seconds = max(elapsed_seconds, 0.000001)
    switches = max(completed_switches, 1)
    return {
        "file_count": len(active_paths),
        "line_count": line_count,
        "retained_bytes": retained_bytes,
        "bytes_per_second": retained_bytes / seconds,
        "megabytes_per_minute": (
            retained_bytes * 60 / seconds / 1_000_000
        ),
        "bytes_per_completed_switch": retained_bytes / switches,
        "capacity_saturated": len(paths) >= LOG_CAPACITY,
        "started_marker_count": started_count,
        "completed_marker_count": completed_count,
        "window_satisfied": started_count == 1 and completed_count == 1,
        "dominant_categories": ranked_log_usage(categories, "category"),
        "dominant_events": ranked_log_usage(events, "event"),
    }


def sample_interval_duration_nanoseconds(sample):
    started = sample.get("interval_started_uptime_nanoseconds")
    completed = sample.get("interval_completed_uptime_nanoseconds")
    if started is None or completed is None or completed <= started:
        return None
    return completed - started


def select_resource_windows(samples, started, completed):
    if started <= 0 or completed <= started:
        return {"preflight": [], "active": [], "postflight": []}
    preflight = []
    active = []
    postflight = []
    for sample in samples:
        interval_started = sample.get(
            "interval_started_uptime_nanoseconds"
        )
        interval_completed = sample.get(
            "interval_completed_uptime_nanoseconds"
        )
        if interval_started is None or interval_completed is None:
            continue
        if interval_completed <= started:
            preflight.append(sample)
        elif interval_started >= started and interval_completed <= completed:
            active.append(sample)
        elif interval_started >= completed:
            postflight.append(sample)
    return {
        "preflight": preflight,
        "active": active,
        "postflight": postflight,
    }


def summarize_resources(samples):
    cpu_values = [row["cpu"] for row in samples]
    rss_values = [row["rss_kb"] for row in samples]
    timed_rows = [
        (row, sample_interval_duration_nanoseconds(row))
        for row in samples
    ]
    timed_rows = [
        (row, duration)
        for row, duration in timed_rows
        if duration is not None
    ]
    covered_duration = sum(duration for _, duration in timed_rows)
    processor_time_milliseconds = sum(
        row["cpu"] * duration / 100 / 1_000_000
        for row, duration in timed_rows
    )
    average_cpu = (
        sum(row["cpu"] * duration for row, duration in timed_rows)
        / covered_duration
        if covered_duration > 0
        else (
            sum(cpu_values) / len(cpu_values)
            if cpu_values
            else None
        )
    )

    warmup_index = min(len(samples), math.ceil(len(samples) * 0.2))
    plateau = samples[warmup_index:]
    middle_start = math.floor(len(plateau) * 0.25)
    middle_end = max(middle_start + 1, math.ceil(len(plateau) * 0.5))
    late_start = math.floor(len(plateau) * 0.75)
    middle_rss = [
        row["rss_kb"] for row in plateau[middle_start:middle_end]
    ]
    late_rss = [row["rss_kb"] for row in plateau[late_start:]]
    middle_rss_p95 = percentile(middle_rss, 95)
    late_rss_p95 = percentile(late_rss, 95)
    rss_growth_kb = (
        late_rss_p95 - middle_rss_p95
        if middle_rss_p95 is not None and late_rss_p95 is not None
        else math.inf
    )
    rss_growth_limit_kb = (
        max(
            RSS_ABSOLUTE_GROWTH_ALLOWANCE_KB,
            middle_rss_p95 * RSS_RELATIVE_GROWTH_ALLOWANCE,
        )
        if middle_rss_p95 is not None
        else 0
    )
    return {
        "sample_count": len(samples),
        "covered_duration_nanoseconds": covered_duration,
        "processor_time_milliseconds": processor_time_milliseconds,
        "cpu_percent": {
            "average": average_cpu,
            "p95": percentile(cpu_values, 95),
            "max": max(cpu_values) if cpu_values else None,
        },
        "rss_mb": {
            "average": (
                sum(rss_values) / len(rss_values) / 1024
                if rss_values
                else None
            ),
            "p95": (
                percentile(rss_values, 95) / 1024
                if rss_values
                else None
            ),
            "max": max(rss_values) / 1024 if rss_values else None,
            "middle_p95": (
                middle_rss_p95 / 1024
                if middle_rss_p95 is not None
                else None
            ),
            "late_p95": (
                late_rss_p95 / 1024
                if late_rss_p95 is not None
                else None
            ),
            "plateau_growth": (
                rss_growth_kb / 1024
                if math.isfinite(rss_growth_kb)
                else None
            ),
            "plateau_growth_limit": rss_growth_limit_kb / 1024,
            "plateau_sample_count": len(plateau),
            "middle_sample_count": len(middle_rss),
            "late_sample_count": len(late_rss),
        },
    }
