#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EVIDENCE_LIBRARY_PATH="${ROOT_DIR}/scripts/perf/lib/tab-switch-stress-evidence.sh"
RUNNER_PATH="${ROOT_DIR}/scripts/perf/tab-switch-stress.sh"
EVIDENCE_TOOL_PATH="${ROOT_DIR}/scripts/perf/lib/tab-switch-isolated-pressure-evidence.py"
FIXTURE_ROOT="$(mktemp -d -t flowtab-tab-switch-evidence)"

# shellcheck source=scripts/perf/lib/tab-switch-stress-evidence.sh
source "$EVIDENCE_LIBRARY_PATH"

cleanup() {
  /bin/rm -f \
    "${FIXTURE_ROOT}"/*.log \
    "${FIXTURE_ROOT}"/*.json \
    "${FIXTURE_ROOT}"/*.csv \
    "${FIXTURE_ROOT}"/*.txt
  /bin/rmdir "$FIXTURE_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

write_fixture() {
  local fixture_path="$1"
  local fixture_text="$2"
  printf '%s\n' "$fixture_text" >"$fixture_path"
}

VALID_LOG="${FIXTURE_ROOT}/valid.log"
write_fixture "$VALID_LOG" \
  $'FlowTabTabSwitchStressEvidence phase=started requiredSwitches=1000 switches=0 homeSwitches=0 logsSwitches=0 settingsSwitches=0 startedAtUptimeNanoseconds=100000000000 observedAtUptimeNanoseconds=100000000000 elapsedNanoseconds=0 durationSatisfied=false workloadSatisfied=false runtimeLogLevel=DEBUG\nFlowTabTabSwitchStressEvidence phase=completed requiredSwitches=1000 switches=1000 homeSwitches=334 logsSwitches=333 settingsSwitches=333 startedAtUptimeNanoseconds=100000000000 observedAtUptimeNanoseconds=162500000000 elapsedNanoseconds=62500000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=DEBUG'
flowtab_tab_switch_parse_completion_evidence "$VALID_LOG" DEBUG \
  || fail "valid completion evidence was rejected"
[[ "$FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION" == valid ]] \
  || fail "valid evidence condition was not retained"
[[ "$FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT" == 1000 ]] \
  || fail "planned switch count was not parsed"
[[ "$FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT" == 1000 ]] \
  || fail "completed switch count was not parsed"
[[ "$FLOWTAB_TAB_SWITCH_HOME_SWITCH_COUNT" == 334 \
  && "$FLOWTAB_TAB_SWITCH_LOGS_SWITCH_COUNT" == 333 \
  && "$FLOWTAB_TAB_SWITCH_SETTINGS_SWITCH_COUNT" == 333 ]] \
  || fail "per-tab switch counts were not parsed"
[[ "$FLOWTAB_TAB_SWITCH_ACTUAL_ELAPSED_SECONDS" == 62.500000 ]] \
  || fail "actual elapsed time was not derived"
[[ "$FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS" == 100000000000 \
  && "$FLOWTAB_TAB_SWITCH_COMPLETED_UPTIME_NANOSECONDS" == 162500000000 ]] \
  || fail "active monotonic bounds were not parsed"
[[ "$FLOWTAB_TAB_SWITCH_THROUGHPUT" == 16.000000 ]] \
  || fail "throughput was not derived"
[[ "$FLOWTAB_TAB_SWITCH_RUNTIME_LOG_LEVEL" == DEBUG ]] \
  || fail "runtime log level was not parsed"

MISSING_LOG="${FIXTURE_ROOT}/missing.log"
write_fixture "$MISSING_LOG" \
  "FlowTabTabSwitchStressEvidence phase=started requiredSwitches=1000 switches=0 homeSwitches=0 logsSwitches=0 settingsSwitches=0 startedAtUptimeNanoseconds=100000000000 observedAtUptimeNanoseconds=100000000000 elapsedNanoseconds=0 durationSatisfied=false workloadSatisfied=false runtimeLogLevel=DEBUG"
if flowtab_tab_switch_parse_completion_evidence "$MISSING_LOG" DEBUG; then
  fail "missing completion evidence was accepted"
fi
[[ "$FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION" == missing ]] \
  || fail "missing evidence condition was not retained"

CONFLICT_LOG="${FIXTURE_ROOT}/conflict.log"
write_fixture "$CONFLICT_LOG" \
  $'FlowTabTabSwitchStressEvidence phase=started requiredSwitches=1000 switches=0 homeSwitches=0 logsSwitches=0 settingsSwitches=0 startedAtUptimeNanoseconds=100000000000 observedAtUptimeNanoseconds=100000000000 elapsedNanoseconds=0 durationSatisfied=false workloadSatisfied=false runtimeLogLevel=DEBUG\nFlowTabTabSwitchStressEvidence phase=completed requiredSwitches=1000 switches=999 homeSwitches=333 logsSwitches=333 settingsSwitches=333 startedAtUptimeNanoseconds=100000000000 observedAtUptimeNanoseconds=162500000000 elapsedNanoseconds=62500000000 durationSatisfied=true workloadSatisfied=false runtimeLogLevel=DEBUG'
if flowtab_tab_switch_parse_completion_evidence "$CONFLICT_LOG" DEBUG; then
  fail "conflicting completion evidence was accepted"
fi
[[ "$FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION" == conflicting ]] \
  || fail "conflicting evidence condition was not retained"

TIMING_CONFLICT_LOG="${FIXTURE_ROOT}/timing-conflict.log"
write_fixture "$TIMING_CONFLICT_LOG" \
  $'FlowTabTabSwitchStressEvidence phase=started requiredSwitches=10 switches=0 homeSwitches=0 logsSwitches=0 settingsSwitches=0 startedAtUptimeNanoseconds=1000000000 observedAtUptimeNanoseconds=1000000000 elapsedNanoseconds=0 durationSatisfied=false workloadSatisfied=false runtimeLogLevel=ERROR\nFlowTabTabSwitchStressEvidence phase=completed requiredSwitches=10 switches=10 homeSwitches=4 logsSwitches=3 settingsSwitches=3 startedAtUptimeNanoseconds=1000000000 observedAtUptimeNanoseconds=2000000001 elapsedNanoseconds=1000000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=ERROR'
if flowtab_tab_switch_parse_completion_evidence \
  "$TIMING_CONFLICT_LOG" ERROR; then
  fail "conflicting monotonic duration evidence was accepted"
fi

DUPLICATE_LOG="${FIXTURE_ROOT}/duplicate.log"
write_fixture "$DUPLICATE_LOG" \
  $'FlowTabTabSwitchStressEvidence phase=started requiredSwitches=10 switches=0 homeSwitches=0 logsSwitches=0 settingsSwitches=0 startedAtUptimeNanoseconds=1000000000 observedAtUptimeNanoseconds=1000000000 elapsedNanoseconds=0 durationSatisfied=false workloadSatisfied=false runtimeLogLevel=ERROR\nFlowTabTabSwitchStressEvidence phase=completed requiredSwitches=10 switches=10 homeSwitches=4 logsSwitches=3 settingsSwitches=3 startedAtUptimeNanoseconds=1000000000 observedAtUptimeNanoseconds=2000000000 elapsedNanoseconds=1000000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=ERROR\nFlowTabTabSwitchStressEvidence phase=completed requiredSwitches=10 switches=10 homeSwitches=4 logsSwitches=3 settingsSwitches=3 startedAtUptimeNanoseconds=1000000000 observedAtUptimeNanoseconds=2000000000 elapsedNanoseconds=1000000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=ERROR'
if flowtab_tab_switch_parse_completion_evidence "$DUPLICATE_LOG" ERROR; then
  fail "duplicate completion evidence was accepted"
fi

LEVEL_CONFLICT_LOG="${FIXTURE_ROOT}/level-conflict.log"
write_fixture "$LEVEL_CONFLICT_LOG" \
  $'FlowTabTabSwitchStressEvidence phase=started requiredSwitches=10 switches=0 homeSwitches=0 logsSwitches=0 settingsSwitches=0 startedAtUptimeNanoseconds=1000000000 observedAtUptimeNanoseconds=1000000000 elapsedNanoseconds=0 durationSatisfied=false workloadSatisfied=false runtimeLogLevel=INFO\nFlowTabTabSwitchStressEvidence phase=completed requiredSwitches=10 switches=10 homeSwitches=4 logsSwitches=3 settingsSwitches=3 startedAtUptimeNanoseconds=1000000000 observedAtUptimeNanoseconds=2000000000 elapsedNanoseconds=1000000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=INFO'
if flowtab_tab_switch_parse_completion_evidence \
  "$LEVEL_CONFLICT_LOG" DEBUG; then
  fail "conflicting runtime log level evidence was accepted"
fi

/usr/bin/grep -F -q -- '--runtime-log-level <DEBUG|INFO|WARN|ERROR>' "$RUNNER_PATH" \
  || fail "runner help omits the runtime log level contract"
/usr/bin/grep -F -q -- '--max-runtime-log-mb-per-minute <positive-decimal>' "$RUNNER_PATH" \
  || fail "runner help omits the runtime log volume budget"
/usr/bin/grep -F -q -- '--flowtab-tab-stress-runtime-log-level "$RUNTIME_LOG_LEVEL"' "$RUNNER_PATH" \
  || fail "runner omits the TestingSupport runtime log level argument"
/usr/bin/grep -F -q -- '--flowtab-ui-runtime-log-level "$RUNTIME_LOG_LEVEL"' "$RUNNER_PATH" \
  || fail "runner omits the shared UI-test runtime log level argument"
/usr/bin/grep -F -q -- '--flowtab-tab-stress-prewarm-tabs' "$RUNNER_PATH" \
  || fail "runner does not prewarm the three retained tab hosts"
/usr/bin/grep -F -q -- 'FLOWTAB_UI_TESTING=1' "$RUNNER_PATH" \
  || fail "runner does not use the shared TestingSupport log format"
/usr/bin/grep -F -q -- 'CFFIXED_USER_HOME="$APP_HOME"' "$RUNNER_PATH" \
  || fail "runner does not isolate the stress App home inside evidence"
/usr/bin/grep -F -q -- 'SCHEMA_VERSION = 5' "$EVIDENCE_TOOL_PATH" \
  || fail "runner status schema is not version 5"
/usr/bin/grep -F -q -- \
  'sample,timestamp,pid,interval_started_uptime_nanoseconds,interval_completed_uptime_nanoseconds,cpu_percent,rss_kb' \
  "$RUNNER_PATH" \
  || fail "runner samples do not use the shared interval schema"
/usr/bin/grep -F -q -- 'flowtab_perf_interval_cpu_percent' "$RUNNER_PATH" \
  || fail "runner does not use interval CPU evidence"
if /usr/bin/grep -F -q -- '-o %cpu=' "$RUNNER_PATH"; then
  fail "runner still uses point-in-time CPU snapshots"
fi
/usr/bin/grep -F -q -- '"lane": "isolated_state_log"' \
  "$EVIDENCE_TOOL_PATH" \
  || fail "runner status omits the isolated attribution lane"

EARLY_RUNNER_STATUS="${FIXTURE_ROOT}/early-runner.json"
EARLY_SAMPLES="${FIXTURE_ROOT}/early-samples.csv"
EARLY_STATUS="${FIXTURE_ROOT}/early-status.json"
EARLY_SUMMARY="${FIXTURE_ROOT}/early-summary.txt"
write_fixture "$EARLY_RUNNER_STATUS" \
  '{"stage":"build_failed","runtime_log_level":"ERROR","final_exit_code":65,"xcodebuild_exit_code":65,"build_log_exit_code":0,"sampling_failed":false}'
write_fixture "$EARLY_SAMPLES" \
  'sample,timestamp,pid,interval_started_uptime_nanoseconds,interval_completed_uptime_nanoseconds,cpu_percent,rss_kb'
if /usr/bin/python3 "$EVIDENCE_TOOL_PATH" evaluate \
  --runner-status "$EARLY_RUNNER_STATUS" \
  --samples "$EARLY_SAMPLES" \
  --runtime-home "$FIXTURE_ROOT" \
  --output "$EARLY_STATUS" \
  --summary "$EARLY_SUMMARY"; then
  fail "early runner failure produced a passing verdict"
fi
/usr/bin/python3 -c '
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
assert value["schema_version"] == 5
assert value["verdict"] == "failed"
assert value["measurement_window"] == "active_tab_switch"
assert value["sample_count"] == 0
assert all(key in value for key in (
    "active_resource_coverage", "cpu_percent", "rss_mb",
    "runtime_logs", "diagnostic_resource_windows", "gates",
))
' "$EARLY_STATUS" \
  || fail "early failure status is not a complete schema-v5 document"

echo "Tab-switch stress evidence validates unique markers, monotonic bounds, per-tab counts, elapsed time, throughput, and runtime log level wiring."
