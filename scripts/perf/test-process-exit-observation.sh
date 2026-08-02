#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROCESS_EXIT_OBSERVATION_PATH="${ROOT_DIR}/scripts/perf/lib/process-exit-observation.sh"
TAB_SWITCH_STRESS_PATH="${ROOT_DIR}/scripts/perf/tab-switch-stress.sh"
SEARCH_PRESSURE_PATH="${ROOT_DIR}/scripts/perf/search-committed-index-pressure.sh"
RUNTIME_TOPOLOGY_PRESSURE_PATH="${ROOT_DIR}/scripts/perf/runtime-topology-pressure.sh"
REAL_FIXTURE_MAX_LIFETIME_SECONDS=5

# shellcheck source=scripts/perf/lib/process-exit-observation.sh
source "${PROCESS_EXIT_OBSERVATION_PATH}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test_initial_exit_avoids_clock_and_poll() (
  local clock_count=0
  local readback_count=0
  local sleep_count=0

  flowtab_perf_process_exit_readback() {
    readback_count=$((readback_count + 1))
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="exited"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="pid=42 state=absent"
  }
  flowtab_perf_process_exit_read_clock() {
    clock_count=$((clock_count + 1))
  }
  flowtab_perf_process_exit_sleep() {
    sleep_count=$((sleep_count + 1))
  }

  flowtab_perf_wait_for_process_exit 42 "start" 2000 0.1

  [[ "${readback_count}" -eq 1 ]] || fail "expected one immediate readback"
  [[ "${clock_count}" -eq 0 ]] || fail "clock ran after initial satisfaction"
  [[ "${sleep_count}" -eq 0 ]] || fail "poll ran after initial satisfaction"
)

test_delayed_exit_uses_named_polling() (
  local readback_count=0
  local sleep_count=0
  local intervals=""

  flowtab_perf_process_exit_readback() {
    readback_count=$((readback_count + 1))
    if [[ "${readback_count}" -lt 3 ]]; then
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="42 1 S start fixture"
    else
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="exited"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="pid=42 state=absent"
    fi
  }
  flowtab_perf_process_exit_read_clock() {
    FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=100
  }
  flowtab_perf_process_exit_sleep() {
    sleep_count=$((sleep_count + 1))
    intervals+="${1},"
  }

  flowtab_perf_wait_for_process_exit 42 "start" 2000 0.125

  [[ "${readback_count}" -eq 3 ]] || fail "expected final absence readback"
  [[ "${sleep_count}" -eq 2 ]] || fail "unexpected conditional poll count"
  [[ "${intervals}" == "0.125,0.125," ]] \
    || fail "unexpected poll intervals: ${intervals}"
)

test_satisfied_readback_wins_after_slow_schedule() (
  local now_ns=10
  local process_is_running=true

  flowtab_perf_process_exit_readback() {
    if [[ "${process_is_running}" == true ]]; then
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="42 1 S start fixture"
    else
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="exited"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="pid=42 state=absent"
    fi
  }
  flowtab_perf_process_exit_read_clock() {
    FLOWTAB_PERF_PROCESS_EXIT_NOW_NS="${now_ns}"
  }
  flowtab_perf_process_exit_sleep() {
    now_ns=9000000000
    process_is_running=false
  }

  flowtab_perf_wait_for_process_exit 42 "start" 2000 0.1
)

test_watchdog_reports_final_readback() (
  local clock_count=0
  local diagnostics
  local diagnostics_file
  local readback_count=0

  diagnostics_file="$(mktemp -t flowtab-perf-process-exit-watchdog)"
  trap 'rm -f "${diagnostics_file}"' EXIT

  flowtab_perf_process_exit_readback() {
    readback_count=$((readback_count + 1))
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="record-${readback_count}"
  }
  flowtab_perf_process_exit_read_clock() {
    clock_count=$((clock_count + 1))
    if [[ "${clock_count}" -eq 1 ]]; then
      FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=100
    else
      FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=2000000100
    fi
  }
  flowtab_perf_process_exit_sleep() {
    fail "expired watchdog must not poll"
  }

  if flowtab_perf_wait_for_process_exit \
    42 \
    "start" \
    2000 \
    0.1 \
    2>"${diagnostics_file}"; then
    fail "watchdog should fail while the process remains running"
  fi
  diagnostics="$(<"${diagnostics_file}")"

  [[ "${readback_count}" -eq 2 ]] || fail "watchdog omitted final readback"
  [[ "${diagnostics}" == *"unmetCondition=processExited pid=42"* ]] \
    || fail "missing unmet-condition diagnostic"
  [[ "${diagnostics}" == *"lastCondition=running"* ]] \
    || fail "missing final condition"
  [[ "${diagnostics}" == *"record-2"* ]] \
    || fail "missing final observation"
)

test_identity_change_is_terminal() (
  local clock_count=0
  local diagnostics
  local diagnostics_file

  diagnostics_file="$(mktemp -t flowtab-perf-process-exit-identity)"
  trap 'rm -f "${diagnostics_file}"' EXIT

  flowtab_perf_process_exit_readback() {
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="identity_changed"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="42 1 S changed fixture"
  }
  flowtab_perf_process_exit_read_clock() {
    clock_count=$((clock_count + 1))
  }

  if flowtab_perf_wait_for_process_exit \
    42 \
    "start" \
    2000 \
    0.1 \
    2>"${diagnostics_file}"; then
    fail "identity change must not establish target exit"
  fi
  diagnostics="$(<"${diagnostics_file}")"
  [[ "${clock_count}" -eq 0 ]] || fail "identity change should fail immediately"
  [[ "${diagnostics}" == *"unmetCondition=processIdentityStable"* ]] \
    || fail "identity change diagnostic is missing"
)

test_readback_error_cannot_establish_exit() (
  local clock_count=0
  local diagnostics
  local diagnostics_file

  diagnostics_file="$(mktemp -t flowtab-perf-process-exit-readback)"
  trap 'rm -f "${diagnostics_file}"' EXIT

  flowtab_perf_process_exit_readback() {
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="readback_error"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="readbackError=synthetic"
  }
  flowtab_perf_process_exit_read_clock() {
    clock_count=$((clock_count + 1))
    if [[ "${clock_count}" -eq 1 ]]; then
      FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=100
    else
      FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=2000000100
    fi
  }
  flowtab_perf_process_exit_sleep() {
    fail "expired readback-error watchdog must not poll"
  }

  if flowtab_perf_wait_for_process_exit \
    42 \
    "start" \
    2000 \
    0.1 \
    2>"${diagnostics_file}"; then
    fail "readback error must not establish target exit"
  fi
  diagnostics="$(<"${diagnostics_file}")"
  [[ "${diagnostics}" == *"lastCondition=readback_error"* ]] \
    || fail "readback error condition is missing"
  [[ "${diagnostics}" == *"readbackError=synthetic"* ]] \
    || fail "readback error evidence is missing"
)

test_poll_cancellation_is_owned() (
  local readback_count=0

  flowtab_perf_process_exit_readback() {
    readback_count=$((readback_count + 1))
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="42 1 S start fixture"
  }
  flowtab_perf_process_exit_read_clock() {
    FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=100
  }
  flowtab_perf_process_exit_sleep() {
    return 1
  }

  local status=0
  flowtab_perf_wait_for_process_exit 42 "start" 2000 0.1 2>/dev/null \
    || status=$?
  [[ "${status}" -eq 130 ]] || fail "cancelled poll returned ${status}"
  [[ "${readback_count}" -eq 1 ]] || fail "cancelled poll performed extra readback"
)

test_process_tree_exact_identities_define_completion() (
  FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS=()
  flowtab_perf_remember_process_identity 42 old-start
  flowtab_perf_remember_process_identity 42 old-start
  [[ "${#FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[@]}" -eq 2 ]] \
    || fail "duplicate exact process identity was retained"

  flowtab_perf_process_exit_readback() {
    if [[ "$1" == "42" ]]; then
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="identity_changed"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="42 1 S replacement"
    else
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="exited"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="pid=$1 state=absent"
    fi
  }

  flowtab_perf_process_identities_exit_readback 42 old-start 43 child-start

  [[ "$FLOWTAB_PERF_PROCESS_EXIT_CONDITION" == "exited" ]] \
    || fail "inactive exact process identities did not satisfy tree exit"
)

test_process_tree_captures_and_signals_exact_active_identities() (
  local signals=""

  FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS=()
  flowtab_perf_process_start_identity() {
    return 1
  }
  flowtab_perf_process_exit_readback() {
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="$1 1 S recovered-start fixture"
    FLOWTAB_PERF_PROCESS_EXIT_OBSERVED_START_IDENTITY="recovered-start"
  }
  flowtab_perf_capture_process_identity 43
  [[ "${FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[*]}" == "43 recovered-start" ]] \
    || fail "process identity was not recovered from immediate readback"

  flowtab_perf_remember_process_identity 42 old-start
  flowtab_perf_process_exit_readback() {
    if [[ "$1" == "42" ]]; then
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="identity_changed"
    else
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
    fi
  }
  kill() {
    signals+="$*;"
  }
  flowtab_perf_signal_active_process_identities \
    TERM \
    42 old-start \
    43 recovered-start
  [[ "$signals" == "-TERM 43;" ]] \
    || fail "signal was not limited to the matching active identity: $signals"
)

test_process_identity_capture_error_is_unmet() (
  FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS=()
  flowtab_perf_process_start_identity() {
    return 1
  }
  flowtab_perf_process_exit_readback() {
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="readback_error"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="readbackError=synthetic"
    FLOWTAB_PERF_PROCESS_EXIT_OBSERVED_START_IDENTITY=""
  }

  if flowtab_perf_capture_process_identity 42; then
    fail "identity-capture readback error established evidence"
  fi
  [[ "${#FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[@]}" -eq 0 ]] \
    || fail "identity-capture error retained an inexact record"
)

test_process_tree_slow_schedule_only_changes_latency() (
  local now_ns=10
  local process_tree_is_running=true

  flowtab_perf_process_identities_exit_readback() {
    if [[ "$process_tree_is_running" == true ]]; then
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="pid=42 condition=running"
    else
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="exited"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="all exact process identities are inactive"
    fi
  }
  flowtab_perf_process_exit_read_clock() {
    FLOWTAB_PERF_PROCESS_EXIT_NOW_NS="$now_ns"
  }
  flowtab_perf_process_exit_sleep() {
    now_ns=9000000000
    process_tree_is_running=false
  }

  flowtab_perf_wait_for_process_identities_exit 2000 0.1 42 start
)

test_process_tree_poll_cancellation_is_owned() (
  local readback_count=0
  local status=0

  flowtab_perf_process_identities_exit_readback() {
    readback_count=$((readback_count + 1))
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="pid=42 condition=running"
  }
  flowtab_perf_process_exit_read_clock() {
    FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=100
  }
  flowtab_perf_process_exit_sleep() {
    return 1
  }

  flowtab_perf_wait_for_process_identities_exit 2000 0.1 42 start 2>/dev/null \
    || status=$?
  [[ "$status" -eq 130 ]] || fail "cancelled process-tree poll returned $status"
  [[ "$readback_count" -eq 1 ]] \
    || fail "cancelled process-tree poll performed extra readback"
)

test_process_tree_watchdog_reports_final_records() (
  local clock_count=0
  local diagnostics
  local diagnostics_file
  local readback_count=0

  diagnostics_file="$(mktemp -t flowtab-perf-process-tree-watchdog)"
  trap 'rm -f "${diagnostics_file}"' EXIT
  flowtab_perf_process_identities_exit_readback() {
    readback_count=$((readback_count + 1))
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="tree-record-${readback_count}"
  }
  flowtab_perf_process_exit_read_clock() {
    clock_count=$((clock_count + 1))
    if [[ "$clock_count" -eq 1 ]]; then
      FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=100
    else
      FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=2000000100
    fi
  }
  flowtab_perf_process_exit_sleep() {
    fail "expired process-tree watchdog must not poll"
  }

  if flowtab_perf_wait_for_process_identities_exit \
    2000 0.1 42 start 43 child-start 2>"$diagnostics_file"; then
    fail "process-tree watchdog should fail while a record remains active"
  fi
  diagnostics="$(<"$diagnostics_file")"

  [[ "$readback_count" -eq 2 ]] || fail "process-tree watchdog omitted final readback"
  [[ "$diagnostics" == *"unmetCondition=processTreeExited"* ]] \
    || fail "missing process-tree unmet-condition diagnostic"
  [[ "$diagnostics" == *"tree-record-2"* ]] \
    || fail "missing final process-tree observation"
)

test_real_child_exit_readback() (
  local fixture_pid=""
  local fixture_ready
  local fixture_ready_fifo
  local fixture_root
  local fixture_start_identity
  local wait_status=0

  fixture_root="$(mktemp -d -t flowtab-perf-process-exit-fixture)"
  fixture_ready_fifo="${fixture_root}/ready.fifo"
  /usr/bin/mkfifo "${fixture_ready_fifo}"
  trap '
    if [[ -n "${fixture_pid}" ]]; then
      /bin/kill -KILL "${fixture_pid}" 2>/dev/null || true
      wait "${fixture_pid}" 2>/dev/null || true
    fi
    /bin/rm -f "${fixture_ready_fifo}"
    /bin/rmdir "${fixture_root}" 2>/dev/null || true
  ' EXIT

  LC_ALL=C /usr/bin/perl \
    -e '$SIG{TERM} = sub { exit 0 }; $| = 1; print "ready\n"; sleep $ARGV[0]' \
    "${REAL_FIXTURE_MAX_LIFETIME_SECONDS}" \
    >"${fixture_ready_fifo}" &
  fixture_pid=$!
  IFS= read -r fixture_ready <"${fixture_ready_fifo}"
  [[ "${fixture_ready}" == "ready" ]] || fail "fixture did not publish readiness"
  fixture_start_identity="$(flowtab_perf_process_start_identity "${fixture_pid}")"
  /bin/kill -TERM "${fixture_pid}"

  flowtab_perf_wait_for_process_exit \
    "${fixture_pid}" \
    "${fixture_start_identity}" \
    2000 \
    0.1
  wait "${fixture_pid}" 2>/dev/null || wait_status=$?
  fixture_pid=""

  [[ "${wait_status}" -eq 0 ]] \
    || fail "unexpected terminated fixture wait status: ${wait_status}"
)

test_tab_switch_owner_uses_observation_contract() {
  /usr/bin/grep -F -q \
    'source "${PROCESS_EXIT_OBSERVATION_PATH}"' \
    "${TAB_SWITCH_STRESS_PATH}" \
    || fail "tab-switch runner does not source the process owner"
  /usr/bin/grep -F -q \
    'flowtab_perf_wait_for_process_exit' \
    "${TAB_SWITCH_STRESS_PATH}" \
    || fail "tab-switch runner does not wait from process evidence"
  if /usr/bin/grep -E -q \
    'wait_attempt|^[[:space:]]*sleep[[:space:]]+0[.]1([[:space:]]|$)' \
    "${TAB_SWITCH_STRESS_PATH}"; then
    fail "tab-switch cleanup still contains an unnamed attempt cadence"
  fi
}

test_search_pressure_owner_uses_observation_contract() {
  /usr/bin/grep -F -q \
    'source "${PROCESS_EXIT_OBSERVATION_PATH}"' \
    "${SEARCH_PRESSURE_PATH}" \
    || fail "search pressure runner does not source the process owner"
  /usr/bin/grep -F -q \
    'flowtab_perf_wait_for_process_identities_exit' \
    "${SEARCH_PRESSURE_PATH}" \
    || fail "search pressure runner does not wait for exact tree evidence"
  /usr/bin/grep -F -q \
    'flowtab_perf_process_start_identity "$TEST_PID"' \
    "${SEARCH_PRESSURE_PATH}" \
    || fail "search pressure runner does not capture child identity"
  if /usr/bin/grep -E -q \
    'wait_attempt|^[[:space:]]*sleep[[:space:]]+0[.]1([[:space:]]|$)' \
    "${SEARCH_PRESSURE_PATH}"; then
    fail "search pressure cleanup still contains an unnamed attempt cadence"
  fi
}

test_runtime_topology_pressure_owner_uses_observation_contract() {
  local cleanup_body
  local contract_step
  local remainder
  local target_exit_body

  /usr/bin/grep -F -q \
    'source "$PROCESS_EXIT_OBSERVATION_PATH"' \
    "$RUNTIME_TOPOLOGY_PRESSURE_PATH" \
    || fail "runtime-topology pressure runner does not source the process owner"
  /usr/bin/grep -F -q \
    'flowtab_perf_wait_for_process_identities_exit' \
    "$RUNTIME_TOPOLOGY_PRESSURE_PATH" \
    || fail "runtime-topology pressure runner does not wait for exact tree evidence"
  /usr/bin/grep -F -q \
    'flowtab_perf_process_start_identity "$TEST_PID"' \
    "$RUNTIME_TOPOLOGY_PRESSURE_PATH" \
    || fail "runtime-topology pressure runner does not capture child identity"
  cleanup_body="$(
    /usr/bin/sed -n \
      '/^terminate_test_process()/,/^handle_signal()/p' \
      "$RUNTIME_TOPOLOGY_PRESSURE_PATH"
  )"
  if /usr/bin/grep -E -q \
    'wait_attempt|^[[:space:]]*sleep[[:space:]]+0[.]1([[:space:]]|$)' \
    <<<"$cleanup_body"; then
    fail "runtime-topology cleanup still contains an unnamed attempt cadence"
  fi

  /usr/bin/grep -F -q \
    'TARGET_EXIT_COMPLETION_WATCHDOG_MILLISECONDS=30000' \
    "$RUNTIME_TOPOLOGY_PRESSURE_PATH" \
    || fail "runtime-topology target-exit watchdog is not named"
  /usr/bin/grep -F -q \
    'TARGET_EXIT_COMPLETION_POLL_INTERVAL_SECONDS=0.1' \
    "$RUNTIME_TOPOLOGY_PRESSURE_PATH" \
    || fail "runtime-topology target-exit cadence is not named"
  /usr/bin/grep -F -q \
    '&& observe_ui_process_tree_completion_after_target_exit' \
    "$RUNTIME_TOPOLOGY_PRESSURE_PATH" \
    || fail "runtime-topology sampling does not use exact target-exit evidence"
  if /usr/bin/grep -E -q \
    'TARGET_EXIT_GRACE_SECONDS|ui_process_finishes_within_target_exit_grace|elapsed_tenths|grace_tenths' \
    "$RUNTIME_TOPOLOGY_PRESSURE_PATH"; then
    fail "runtime-topology target-exit completion retains attempt-count logic"
  fi
  target_exit_body="$(
    /usr/bin/sed -n \
      '/^observe_ui_process_tree_completion_after_target_exit()/,/^run_ui_test()/p' \
      "$RUNTIME_TOPOLOGY_PRESSURE_PATH" \
      | /usr/bin/sed '$d'
  )"
  remainder="$target_exit_body"
  for contract_step in \
    'flowtab_perf_remember_process_identity "$TEST_PID" "$TEST_START_IDENTITY"' \
    'capture_test_process_tree_identities' \
    'flowtab_perf_wait_for_process_identities_exit' \
    'reap_test_process'; do
    [[ "$remainder" == *"$contract_step"* ]] \
      || fail "target-exit owner is missing or reorders: $contract_step"
    remainder="${remainder#*"$contract_step"}"
  done
  if /usr/bin/grep -E -q \
    'elapsed_tenths|grace_tenths|test_process_is_live|^[[:space:]]*sleep[[:space:]]' \
    <<<"$target_exit_body"; then
    fail "target-exit completion still depends on root liveness or elapsed attempts"
  fi
}

test_initial_exit_avoids_clock_and_poll
test_delayed_exit_uses_named_polling
test_satisfied_readback_wins_after_slow_schedule
test_watchdog_reports_final_readback
test_identity_change_is_terminal
test_readback_error_cannot_establish_exit
test_poll_cancellation_is_owned
test_process_tree_exact_identities_define_completion
test_process_tree_captures_and_signals_exact_active_identities
test_process_identity_capture_error_is_unmet
test_process_tree_slow_schedule_only_changes_latency
test_process_tree_poll_cancellation_is_owned
test_process_tree_watchdog_reports_final_records
test_real_child_exit_readback
test_tab_switch_owner_uses_observation_contract
test_search_pressure_owner_uses_observation_contract
test_runtime_topology_pressure_owner_uses_observation_contract

echo "Perf process and process-tree exit observation checks immediate, delayed, cancelled, watchdog, identity, and real child evidence."
