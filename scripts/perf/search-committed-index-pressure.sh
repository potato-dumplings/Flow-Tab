#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLE_INTERVAL_SECONDS="${1:-0.5}"
RESULTS_ROOT="${ROOT_DIR}/.build-local/search-committed-index-pressure"
RESULTS_DIR="${RESULTS_ROOT}/results-$(date +%Y%m%d-%H%M%S)"
SAMPLES_FILE="${RESULTS_DIR}/process-samples.csv"
SUMMARY_FILE="${RESULTS_DIR}/summary.txt"
BUILD_LOG_FILE="${RESULTS_DIR}/build-for-testing.log"
TEST_LOG_FILE="${RESULTS_DIR}/flowtabtests.log"

declare -a TEST_FILTERS=(
  "-only-testing:FlowTabTests/FlowTabTests/testSearchPerformanceWindowScope"
  "-only-testing:FlowTabTests/FlowTabTests/testSearchPressureWindowScopeUnified"
  "-only-testing:FlowTabTests/FlowTabTests/testLiveSwitcherModelSearchPressureReadsCommittedGenerationValidatedIndexWithoutSampling"
)

mkdir -p "${RESULTS_DIR}"

echo "sample,timestamp,pids,cpu_percent,rss_kb" >"${SAMPLES_FILE}"

sample_count=0

descendant_pids() {
  local root_pid="$1"
  local all_pids=("${root_pid}")
  local index=0

  while [[ "${index}" -lt "${#all_pids[@]}" ]]; do
    local parent="${all_pids[${index}]}"
    local children
    children="$(pgrep -P "${parent}" || true)"
    if [[ -n "${children}" ]]; then
      while IFS= read -r child; do
        [[ -n "${child}" ]] || continue
        all_pids+=("${child}")
      done <<<"${children}"
    fi
    index=$((index + 1))
  done

  printf "%s\n" "${all_pids[@]}"
}

sample_process_tree() {
  local root_pid="$1"
  local cpu_sum="0"
  local rss_sum="0"
  local joined_pids=""
  local sampled_any=false

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    local line
    line="$(ps -p "${pid}" -o %cpu= -o rss= | awk '{$1=$1; print}')"
    [[ -n "${line}" ]] || continue

    local cpu
    local rss
    cpu="$(awk '{print $1}' <<<"${line}")"
    rss="$(awk '{print $2}' <<<"${line}")"
    cpu_sum="$(awk -v a="${cpu_sum}" -v b="${cpu}" 'BEGIN { printf "%.2f", a + b }')"
    rss_sum="$(awk -v a="${rss_sum}" -v b="${rss}" 'BEGIN { printf "%.0f", a + b }')"
    if [[ -z "${joined_pids}" ]]; then
      joined_pids="${pid}"
    else
      joined_pids="${joined_pids};${pid}"
    fi
    sampled_any=true
  done < <(descendant_pids "${root_pid}")

  if [[ "${sampled_any}" != true ]]; then
    return
  fi

  sample_count=$((sample_count + 1))
  echo "${sample_count},$(date +%s),${joined_pids},${cpu_sum},${rss_sum}" >>"${SAMPLES_FILE}"
}

echo "[1/4] Building FlowTabTests for committed-index Search pressure..."
echo "Results: ${RESULTS_DIR}"
"${ROOT_DIR}/scripts/testing/run-flowtabtests-local.sh" build-for-testing >"${BUILD_LOG_FILE}" 2>&1

echo "[2/4] Starting committed-index Search pressure tests..."
"${ROOT_DIR}/scripts/testing/run-flowtabtests-local.sh" test-without-building "${TEST_FILTERS[@]}" >"${TEST_LOG_FILE}" 2>&1 &
TEST_PID=$!

echo "[3/4] Sampling xcodebuild/test runner CPU/RSS every ${SAMPLE_INTERVAL_SECONDS}s..."
while kill -0 "${TEST_PID}" 2>/dev/null; do
  sample_process_tree "${TEST_PID}"
  sleep "${SAMPLE_INTERVAL_SECONDS}"
done

TEST_STATUS=0
wait "${TEST_PID}" || TEST_STATUS=$?

echo "[4/4] Aggregating samples..."
/usr/bin/python3 - "${SAMPLES_FILE}" "${SUMMARY_FILE}" "${SAMPLE_INTERVAL_SECONDS}" "${TEST_STATUS}" "${TEST_LOG_FILE}" <<'PY'
import csv
import math
import re
import sys

samples_path, summary_path, sample_interval, test_status, test_log_path = sys.argv[1:6]

with open(samples_path, newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))

if not rows:
    raise SystemExit("No process samples collected.")

cpu_values = [float(row["cpu_percent"]) for row in rows]
rss_kb_values = [float(row["rss_kb"]) for row in rows]

def percentile(values, pct):
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = math.ceil((pct / 100.0) * len(ordered)) - 1
    index = max(0, min(index, len(ordered) - 1))
    return ordered[index]

search_metrics = []
metric_pattern = re.compile(r"\[(SearchPerformanceWindowScope|SearchPressureUnified)\].*")
with open(test_log_path, encoding="utf-8", errors="replace") as handle:
    for line in handle:
        match = metric_pattern.search(line)
        if match:
            search_metrics.append(match.group(0).strip())

summary = [
    "Committed-index Search pressure summary",
    f"testStatus={test_status}",
    f"sampleIntervalSeconds={sample_interval}",
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

with open(summary_path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(summary))
    handle.write("\n")

print("\n".join(summary))
PY

echo "Samples: ${SAMPLES_FILE}"
echo "Summary: ${SUMMARY_FILE}"

if [[ "${TEST_STATUS}" -ne 0 ]]; then
  echo "Committed-index Search pressure tests failed; tailing ${TEST_LOG_FILE}" >&2
  tail -n 80 "${TEST_LOG_FILE}" >&2
  exit "${TEST_STATUS}"
fi
