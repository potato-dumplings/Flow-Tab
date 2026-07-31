#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROCESS_EXIT_OBSERVATION_PATH="${ROOT_DIR}/scripts/perf/lib/process-exit-observation.sh"
TAB_SWITCH_STRESS_PATH="${ROOT_DIR}/scripts/perf/tab-switch-stress.sh"
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

test_initial_exit_avoids_clock_and_poll
test_delayed_exit_uses_named_polling
test_satisfied_readback_wins_after_slow_schedule
test_watchdog_reports_final_readback
test_identity_change_is_terminal
test_readback_error_cannot_establish_exit
test_poll_cancellation_is_owned
test_real_child_exit_readback
test_tab_switch_owner_uses_observation_contract

echo "Perf process-exit observation checks immediate, delayed, cancelled, watchdog, identity, and real child evidence."
