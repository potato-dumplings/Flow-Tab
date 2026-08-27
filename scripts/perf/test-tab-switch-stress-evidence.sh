#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EVIDENCE_LIBRARY_PATH="${ROOT_DIR}/scripts/perf/lib/tab-switch-stress-evidence.sh"
RUNNER_PATH="${ROOT_DIR}/scripts/perf/tab-switch-stress.sh"
FIXTURE_ROOT="$(mktemp -d -t flowtab-tab-switch-evidence)"

# shellcheck source=scripts/perf/lib/tab-switch-stress-evidence.sh
source "$EVIDENCE_LIBRARY_PATH"

cleanup() {
  /bin/rm -f "${FIXTURE_ROOT}"/*.log
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
  "FlowTabTabSwitchStressEvidence phase=completed requiredSwitches=1000 switches=1000 elapsedNanoseconds=62500000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=DEBUG"
flowtab_tab_switch_parse_completion_evidence "$VALID_LOG" DEBUG \
  || fail "valid completion evidence was rejected"
[[ "$FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION" == valid ]] \
  || fail "valid evidence condition was not retained"
[[ "$FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT" == 1000 ]] \
  || fail "planned switch count was not parsed"
[[ "$FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT" == 1000 ]] \
  || fail "completed switch count was not parsed"
[[ "$FLOWTAB_TAB_SWITCH_ACTUAL_ELAPSED_SECONDS" == 62.500000 ]] \
  || fail "actual elapsed time was not derived"
[[ "$FLOWTAB_TAB_SWITCH_THROUGHPUT" == 16.000000 ]] \
  || fail "throughput was not derived"
[[ "$FLOWTAB_TAB_SWITCH_RUNTIME_LOG_LEVEL" == DEBUG ]] \
  || fail "runtime log level was not parsed"

MISSING_LOG="${FIXTURE_ROOT}/missing.log"
write_fixture "$MISSING_LOG" \
  "FlowTabTabSwitchStressEvidence phase=started requiredSwitches=1000 switches=0 elapsedNanoseconds=0 durationSatisfied=false workloadSatisfied=false runtimeLogLevel=DEBUG"
if flowtab_tab_switch_parse_completion_evidence "$MISSING_LOG" DEBUG; then
  fail "missing completion evidence was accepted"
fi
[[ "$FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION" == missing ]] \
  || fail "missing evidence condition was not retained"

CONFLICT_LOG="${FIXTURE_ROOT}/conflict.log"
write_fixture "$CONFLICT_LOG" \
  "FlowTabTabSwitchStressEvidence phase=completed requiredSwitches=1000 switches=999 elapsedNanoseconds=62500000000 durationSatisfied=true workloadSatisfied=false runtimeLogLevel=DEBUG"
if flowtab_tab_switch_parse_completion_evidence "$CONFLICT_LOG" DEBUG; then
  fail "conflicting completion evidence was accepted"
fi
[[ "$FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION" == conflicting ]] \
  || fail "conflicting evidence condition was not retained"

DUPLICATE_LOG="${FIXTURE_ROOT}/duplicate.log"
write_fixture "$DUPLICATE_LOG" \
  $'FlowTabTabSwitchStressEvidence phase=completed requiredSwitches=10 switches=10 elapsedNanoseconds=1000000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=ERROR\nFlowTabTabSwitchStressEvidence phase=completed requiredSwitches=10 switches=10 elapsedNanoseconds=1000000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=ERROR'
if flowtab_tab_switch_parse_completion_evidence "$DUPLICATE_LOG" ERROR; then
  fail "duplicate completion evidence was accepted"
fi

LEVEL_CONFLICT_LOG="${FIXTURE_ROOT}/level-conflict.log"
write_fixture "$LEVEL_CONFLICT_LOG" \
  "FlowTabTabSwitchStressEvidence phase=completed requiredSwitches=10 switches=10 elapsedNanoseconds=1000000000 durationSatisfied=true workloadSatisfied=true runtimeLogLevel=INFO"
if flowtab_tab_switch_parse_completion_evidence \
  "$LEVEL_CONFLICT_LOG" DEBUG; then
  fail "conflicting runtime log level evidence was accepted"
fi

/usr/bin/grep -F -q -- '--runtime-log-level <DEBUG|INFO|WARN|ERROR>' "$RUNNER_PATH" \
  || fail "runner help omits the runtime log level contract"
/usr/bin/grep -F -q -- '--flowtab-tab-stress-runtime-log-level "$RUNTIME_LOG_LEVEL"' "$RUNNER_PATH" \
  || fail "runner omits the TestingSupport runtime log level argument"
/usr/bin/grep -F -q -- 'CFFIXED_USER_HOME="$APP_HOME"' "$RUNNER_PATH" \
  || fail "runner does not isolate the stress App home inside evidence"
/usr/bin/grep -F -q -- '"schema_version": 2' "$RUNNER_PATH" \
  || fail "runner status schema is not version 2"

echo "Tab-switch stress evidence validates exact completion, elapsed time, throughput, and runtime log level wiring."
