#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EVIDENCE_LIBRARY_PATH="${ROOT_DIR}/scripts/perf/lib/runtime-log-volume-evidence.sh"
RUNNER_PATH="${ROOT_DIR}/scripts/perf/tab-switch-stress.sh"
FIXTURE_ROOT="$(mktemp -d -t flowtab-runtime-log-volume)"

# shellcheck source=scripts/perf/lib/runtime-log-volume-evidence.sh
source "$EVIDENCE_LIBRARY_PATH"

cleanup() {
  /bin/rm -f "${FIXTURE_ROOT}/measured/"*.log
  /bin/rm -f "${FIXTURE_ROOT}/saturated/"*.log
  /bin/rmdir "${FIXTURE_ROOT}/broken/broken.log" 2>/dev/null || true
  /bin/rmdir "${FIXTURE_ROOT}/empty" 2>/dev/null || true
  /bin/rmdir "${FIXTURE_ROOT}/measured" 2>/dev/null || true
  /bin/rmdir "${FIXTURE_ROOT}/saturated" 2>/dev/null || true
  /bin/rmdir "${FIXTURE_ROOT}/broken" 2>/dev/null || true
  /bin/rmdir "$FIXTURE_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

flowtab_runtime_log_is_positive_decimal 2.0 \
  || fail "positive decimal budget was rejected"
if flowtab_runtime_log_is_positive_decimal 0; then
  fail "zero budget was accepted"
fi
if flowtab_runtime_log_is_positive_decimal invalid; then
  fail "nonnumeric budget was accepted"
fi
[[ "$(flowtab_runtime_log_normalize_decimal 0002.00)" == 2.00 ]] \
  || fail "positive decimal budget was not normalized for JSON evidence"

flowtab_runtime_log_measure_volume \
  "${FIXTURE_ROOT}/missing" 60 100 20 0.25 \
  || fail "missing log directory was not treated as zero"
[[ "$FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION" == zero ]] \
  || fail "missing log directory did not retain the zero condition"
[[ "$FLOWTAB_RUNTIME_LOG_FILE_COUNT" == 0 ]] \
  || fail "missing log directory reported files"
[[ "$FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED" == true ]] \
  || fail "zero volume did not satisfy the explicit budget"

/bin/mkdir "${FIXTURE_ROOT}/empty"
flowtab_runtime_log_measure_volume \
  "${FIXTURE_ROOT}/empty" 60 1000 20 2.0 \
  || fail "existing empty log directory was rejected"
[[ "$FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION" == zero ]] \
  || fail "existing empty log directory was not measured as zero"
[[ "$FLOWTAB_RUNTIME_LOG_FILE_COUNT" == 0 ]] \
  || fail "existing empty log directory reported log files"

/bin/mkdir "${FIXTURE_ROOT}/measured"
printf 'one\n' >"${FIXTURE_ROOT}/measured/first.log"
printf 'two\nthree\n' >"${FIXTURE_ROOT}/measured/second.log"
flowtab_runtime_log_measure_volume \
  "${FIXTURE_ROOT}/measured" 7 2 20 0.001 \
  || fail "measurable logs were rejected"
[[ "$FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION" == measured ]] \
  || fail "measured logs did not retain the measured condition"
[[ "$FLOWTAB_RUNTIME_LOG_FILE_COUNT" == 2 ]] \
  || fail "log file count was not measured"
[[ "$FLOWTAB_RUNTIME_LOG_LINE_COUNT" == 3 ]] \
  || fail "log line count was not measured"
[[ "$FLOWTAB_RUNTIME_LOG_RETAINED_BYTES" == 14 ]] \
  || fail "retained bytes were not measured"
[[ "$FLOWTAB_RUNTIME_LOG_BYTES_PER_SECOND" == 2.000000 ]] \
  || fail "bytes per second were not derived"
[[ "$FLOWTAB_RUNTIME_LOG_MEGABYTES_PER_MINUTE" == 0.000120 ]] \
  || fail "megabytes per minute were not derived"
[[ "$FLOWTAB_RUNTIME_LOG_BYTES_PER_COMPLETED_SWITCH" == 7.000 ]] \
  || fail "bytes per completed switch were not derived"
[[ "$FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED" == true ]] \
  || fail "within-budget volume was rejected"

if flowtab_runtime_log_measure_volume \
  "${FIXTURE_ROOT}/measured" 7 2 20 0.0001; then
  fail "over-budget volume was accepted"
fi
[[ "$FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION" == measured ]] \
  || fail "over-budget volume lost its valid measurement"
[[ "$FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED" == false ]] \
  || fail "over-budget result was not retained"

/bin/mkdir "${FIXTURE_ROOT}/saturated"
for index in $(seq 1 20); do
  : >"${FIXTURE_ROOT}/saturated/${index}.log"
done
if flowtab_runtime_log_measure_volume \
  "${FIXTURE_ROOT}/saturated" 60 1000 20 2.0; then
  fail "capacity-saturated logs were accepted"
fi
[[ "$FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION" == capacity_saturated ]] \
  || fail "capacity saturation was not retained"

/bin/mkdir -p "${FIXTURE_ROOT}/broken/broken.log"
if flowtab_runtime_log_measure_volume \
  "${FIXTURE_ROOT}/broken" 60 1000 20 ""; then
  fail "unreadable log entry was accepted"
fi
[[ "$FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION" == measurement_failed ]] \
  || fail "measurement failure was not retained"

if "$RUNNER_PATH" --max-runtime-log-mb-per-minute 0 >/dev/null 2>&1; then
  fail "runner accepted a zero runtime-log budget"
fi
/usr/bin/grep -F -q -- '--max-runtime-log-mb-per-minute <positive-decimal>' "$RUNNER_PATH" \
  || fail "runner help omits the runtime-log volume budget"
/usr/bin/grep -F -q -- '"schema_version": 3' "$RUNNER_PATH" \
  || fail "runner status schema is not version 3"
/usr/bin/grep -F -q -- 'flowtab_runtime_log_normalize_decimal "$MAX_RUNTIME_LOG_MB_PER_MINUTE"' "$RUNNER_PATH" \
  || fail "runner does not normalize the budget before writing JSON evidence"

echo "Runtime-log volume evidence validates zero, measured, saturated, failed, and over-budget outcomes."
