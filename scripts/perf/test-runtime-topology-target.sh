#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET_PATH="${ROOT_DIR}/scripts/perf/lib/runtime-topology-target.sh"
START_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
START_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

source "$TARGET_PATH"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

setup_launch_test() {
  TARGET_LAUNCH_WATCHDOG_MILLISECONDS=1000
  TARGET_LAUNCH_POLL_INTERVAL_SECONDS=0.125
  TARGET_STABILITY_WINDOW_MILLISECONDS=500
  LAUNCH_REQUEST_MONOTONIC_NS=10
  LAUNCH_REQUEST_EPOCH_SECONDS=100
  PREEXISTING_TARGET_IDENTITIES="9:${START_A}:90"
  TARGET_PID=""
  TARGET_START_IDENTITY=""
  TARGET_START_EPOCH_SECONDS=""
  TARGET_FIRST_OBSERVED_MONOTONIC_NS=""
  TARGET_QUALIFIED_MONOTONIC_NS=""
  TARGET_OBSERVATION_COUNT=0
  REJECTED_TRANSIENT_IDENTITY_COUNT=0
  IDENTITY_VERDICT="not_evaluated"
  TARGET_LAUNCH_ROWS=()
  TARGET_LAUNCH_READBACK_ERROR=""
  TARGET_LAUNCH_LAST_OBSERVATION="none"
  TARGET_LAUNCH_NOW_NS=0
  CLOCK_INDEX=0
  CLOCK_VALUES=(100 500000100)
  READBACK_COUNT=0
  SLEEP_COUNT=0
  PUBLISH_COUNT=0
  EVENTS=""
  TEST_PROCESS_LIVE=true

  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    EVENTS+="readback;"
    TARGET_LAUNCH_ROWS=("42:${START_A}:100")
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=1 candidates=${TARGET_LAUNCH_ROWS[*]}"
  }
  target_launch_read_clock() {
    [[ "$CLOCK_INDEX" -lt "${#CLOCK_VALUES[@]}" ]] \
      || fail "clock fixture exhausted"
    TARGET_LAUNCH_NOW_NS="${CLOCK_VALUES[$CLOCK_INDEX]}"
    CLOCK_INDEX=$((CLOCK_INDEX + 1))
    EVENTS+="clock;"
  }
  target_launch_sleep() {
    [[ "$1" == "$TARGET_LAUNCH_POLL_INTERVAL_SECONDS" ]] \
      || fail "unexpected target-launch cadence: $1"
    SLEEP_COUNT=$((SLEEP_COUNT + 1))
    EVENTS+="sleep;"
  }
  test_process_is_live() {
    [[ "$TEST_PROCESS_LIVE" == true ]]
  }
  publish_launch_receipt() {
    PUBLISH_COUNT=$((PUBLISH_COUNT + 1))
    EVENTS+="publish;"
  }
}

test_immediate_readback_precedes_poll_and_qualifies() (
  setup_launch_test

  await_target_launch

  [[ "$READBACK_COUNT" -eq 2 ]] || fail "unexpected immediate readback count"
  [[ "$SLEEP_COUNT" -eq 1 ]] || fail "unexpected immediate-path poll count"
  [[ "$EVENTS" == "readback;clock;sleep;readback;clock;publish;" ]] \
    || fail "target launch was not read before polling: $EVENTS"
  [[ "$TARGET_PID" == 42 && "$TARGET_START_IDENTITY" == "$START_A" ]] \
    || fail "qualified identity was not published"
  [[ "$TARGET_FIRST_OBSERVED_MONOTONIC_NS" == 100 ]] \
    || fail "first observation timestamp is incorrect"
  [[ "$TARGET_QUALIFIED_MONOTONIC_NS" == 500000100 ]] \
    || fail "qualification timestamp is incorrect"
  [[ "$PUBLISH_COUNT" -eq 1 && "$IDENTITY_VERDICT" == matched ]] \
    || fail "launch receipt was not published exactly once"
)

test_delayed_candidate_qualifies_from_observation_time() (
  setup_launch_test
  CLOCK_VALUES=(100 100000100 600000100)
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    EVENTS+="readback;"
    TARGET_LAUNCH_ROWS=()
    if [[ "$READBACK_COUNT" -gt 1 ]]; then
      TARGET_LAUNCH_ROWS=("42:${START_A}:100")
    fi
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=${#TARGET_LAUNCH_ROWS[@]}"
  }

  await_target_launch

  [[ "$READBACK_COUNT" -eq 3 && "$SLEEP_COUNT" -eq 2 ]] \
    || fail "delayed candidate did not use conditional observation"
  [[ "$TARGET_FIRST_OBSERVED_MONOTONIC_NS" == 100000100 ]] \
    || fail "stability began before the candidate was observed"
)

test_slow_schedule_only_changes_completion_latency() (
  setup_launch_test
  CLOCK_VALUES=(100 5000000100)

  await_target_launch

  [[ "$IDENTITY_VERDICT" == matched ]] \
    || fail "scheduler overshoot changed a satisfied result"
)

test_final_discovery_readback_gets_stability_observation() (
  setup_launch_test
  CLOCK_VALUES=(100 2000000100 2500000100)
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    EVENTS+="readback;"
    TARGET_LAUNCH_ROWS=()
    if [[ "$READBACK_COUNT" -gt 1 ]]; then
      TARGET_LAUNCH_ROWS=("42:${START_A}:100")
    fi
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=${#TARGET_LAUNCH_ROWS[@]}"
  }

  await_target_launch

  [[ "$READBACK_COUNT" -eq 3 && "$IDENTITY_VERDICT" == matched ]] \
    || fail "final discovery was rejected because scheduling crossed the watchdog"
)

test_ambiguous_and_reused_pid_reset_stability() (
  setup_launch_test
  CLOCK_VALUES=(100 100000100 200000100 700000100)
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    EVENTS+="readback;"
    case "$READBACK_COUNT" in
      1) TARGET_LAUNCH_ROWS=("42:${START_A}:100") ;;
      2) TARGET_LAUNCH_ROWS=("42:${START_A}:100" "43:${START_B}:100") ;;
      *) TARGET_LAUNCH_ROWS=("42:${START_B}:100") ;;
    esac
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=${#TARGET_LAUNCH_ROWS[@]} candidates=${TARGET_LAUNCH_ROWS[*]}"
  }

  await_target_launch

  [[ "$TARGET_PID" == 42 && "$TARGET_START_IDENTITY" == "$START_B" ]] \
    || fail "reused PID identity was not qualified exactly"
  [[ "$REJECTED_TRANSIENT_IDENTITY_COUNT" -eq 1 ]] \
    || fail "ambiguous transition did not reject the prior generation"
  [[ "$TARGET_OBSERVATION_COUNT" -eq 2 ]] \
    || fail "stability count crossed an ambiguous readback"
)

test_transient_readback_error_resets_candidate() (
  setup_launch_test
  CLOCK_VALUES=(100 100000100 200000100 700000100)
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    EVENTS+="readback;"
    TARGET_LAUNCH_ROWS=()
    if [[ "$READBACK_COUNT" -eq 2 ]]; then
      TARGET_LAUNCH_READBACK_ERROR="readbackError=synthetic"
      TARGET_LAUNCH_LAST_OBSERVATION="$TARGET_LAUNCH_READBACK_ERROR"
      return 2
    fi
    TARGET_LAUNCH_ROWS=("42:${START_A}:100")
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=1 candidates=${TARGET_LAUNCH_ROWS[*]}"
  }

  await_target_launch

  [[ "$REJECTED_TRANSIENT_IDENTITY_COUNT" -eq 1 ]] \
    || fail "readback error did not reject the interrupted generation"
  [[ "$TARGET_OBSERVATION_COUNT" -eq 2 && "$IDENTITY_VERDICT" == matched ]] \
    || fail "target did not recover from a transient readback error"
)

test_watchdog_reports_final_empty_readback() (
  setup_launch_test
  CLOCK_VALUES=(100 1000000100)
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    EVENTS+="readback;"
    TARGET_LAUNCH_ROWS=()
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=0 readback=${READBACK_COUNT}"
  }
  local diagnostics_file
  local diagnostics
  local status=0
  diagnostics_file="$(mktemp -t flowtab-target-launch-watchdog)"
  trap 'rm -f "$diagnostics_file"' EXIT

  await_target_launch 2>"$diagnostics_file" || status=$?
  diagnostics="$(<"$diagnostics_file")"

  [[ "$status" -eq 1 && "$READBACK_COUNT" -eq 2 ]] \
    || fail "watchdog omitted its final readback"
  [[ "$IDENTITY_VERDICT" == launch_identity_not_observed ]] \
    || fail "empty watchdog verdict is incorrect"
  [[ "$diagnostics" == *"unmetCondition=stableUniquePostRequestIdentity"* ]] \
    || fail "watchdog unmet condition is missing"
  [[ "$diagnostics" == *"candidateCount=0 readback=2"* ]] \
    || fail "watchdog final observation is missing"
  [[ "$diagnostics" == *"baselineIdentities=9:${START_A}:90"* ]] \
    || fail "watchdog baseline evidence is missing"
)

test_final_readback_error_is_unmet_evidence() (
  setup_launch_test
  CLOCK_VALUES=(100 1000000100)
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    EVENTS+="readback;"
    TARGET_LAUNCH_ROWS=()
    TARGET_LAUNCH_READBACK_ERROR="readbackError=synthetic-${READBACK_COUNT}"
    TARGET_LAUNCH_LAST_OBSERVATION="$TARGET_LAUNCH_READBACK_ERROR"
    return 2
  }
  local diagnostics_file
  local diagnostics
  local status=0
  diagnostics_file="$(mktemp -t flowtab-target-launch-readback)"
  trap 'rm -f "$diagnostics_file"' EXIT

  await_target_launch 2>"$diagnostics_file" || status=$?
  diagnostics="$(<"$diagnostics_file")"

  [[ "$status" -eq 2 && "$IDENTITY_VERDICT" == launch_identity_readback_error ]] \
    || fail "final readback error established launch readiness"
  [[ "$diagnostics" == *"readbackError=synthetic-2"* ]] \
    || fail "final readback error diagnostic is missing"
)

test_poll_cancellation_is_owned() (
  setup_launch_test
  CLOCK_VALUES=(100)
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    EVENTS+="readback;"
    TARGET_LAUNCH_ROWS=()
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=0"
  }
  target_launch_sleep() {
    SLEEP_COUNT=$((SLEEP_COUNT + 1))
    return 1
  }
  local status=0

  await_target_launch 2>/dev/null || status=$?

  [[ "$status" -eq 130 && "$READBACK_COUNT" -eq 1 ]] \
    || fail "cancelled launch observation performed extra work"
  [[ "$IDENTITY_VERDICT" == launch_observation_cancelled ]] \
    || fail "cancelled launch observation verdict is incorrect"
)

test_runner_exit_is_terminal_without_poll() (
  setup_launch_test
  CLOCK_VALUES=(100)
  TEST_PROCESS_LIVE=false
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    TARGET_LAUNCH_ROWS=()
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=0"
  }
  local status=0

  await_target_launch 2>/dev/null || status=$?

  [[ "$status" -eq 1 && "$SLEEP_COUNT" -eq 0 ]] \
    || fail "runner exit waited on a cadence"
  [[ "$IDENTITY_VERDICT" == launch_runner_exited ]] \
    || fail "runner-exit verdict is incorrect"
)

test_pre_request_start_is_rejected() (
  setup_launch_test
  CLOCK_VALUES=(100)
  read_post_request_target_identities() {
    READBACK_COUNT=$((READBACK_COUNT + 1))
    TARGET_LAUNCH_ROWS=("42:${START_A}:99")
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="candidateCount=1 candidates=${TARGET_LAUNCH_ROWS[*]}"
  }
  local status=0

  await_target_launch 2>/dev/null || status=$?

  [[ "$status" -eq 1 && "$IDENTITY_VERDICT" == launch_started_before_request ]] \
    || fail "pre-request process was accepted"
  [[ "$SLEEP_COUNT" -eq 0 ]] || fail "pre-request process triggered polling"
)

test_clock_failure_is_unmet_evidence() (
  setup_launch_test
  target_launch_read_clock() {
    TARGET_LAUNCH_READBACK_ERROR="monotonicClockError=synthetic"
    TARGET_LAUNCH_LAST_OBSERVATION="$TARGET_LAUNCH_READBACK_ERROR"
    return 1
  }
  local status=0

  await_target_launch 2>/dev/null || status=$?

  [[ "$status" -eq 2 && "$IDENTITY_VERDICT" == launch_clock_error ]] \
    || fail "clock failure established launch readiness"
)

test_receipt_failure_is_unmet_evidence() (
  setup_launch_test
  publish_launch_receipt() {
    return 1
  }
  local status=0

  await_target_launch 2>/dev/null || status=$?

  [[ "$status" -eq 2 && "$IDENTITY_VERDICT" == launch_receipt_write_failed ]] \
    || fail "receipt failure established launch readiness"
)

test_cpu_time_parser_supports_ps_formats() (
  [[ "$(flowtab_perf_cpu_time_centiseconds '0:00.01')" == 1 ]] \
    || fail "subsecond CPU time was parsed incorrectly"
  [[ "$(flowtab_perf_cpu_time_centiseconds '1:02.34')" == 6234 ]] \
    || fail "minute CPU time was parsed incorrectly"
  [[ "$(flowtab_perf_cpu_time_centiseconds '2:03:04.56')" == 738456 ]] \
    || fail "hour CPU time was parsed incorrectly"
  [[ "$(flowtab_perf_cpu_time_centiseconds '1-02:03:04.56')" == 9378456 ]] \
    || fail "day CPU time was parsed incorrectly"
)

test_interval_cpu_uses_cumulative_process_time_delta() (
  local observed

  observed="$(flowtab_perf_interval_cpu_percent 125 100 500000000)"
  [[ "$observed" == 50.000 ]] \
    || fail "interval CPU percent was not derived from elapsed process time: $observed"
)

test_cpu_interval_failure_distinguishes_live_and_exited_targets() (
  target_process_is_active() {
    [[ "$1" == 41 ]]
  }

  [[ "$(flowtab_perf_cpu_interval_failure_verdict 41)" == cpu_interval_error ]] \
    || fail "live target CPU interval failure was treated as process exit"
  [[ "$(flowtab_perf_cpu_interval_failure_verdict 42)" == sample_unavailable ]] \
    || fail "exited target CPU interval failure was not treated as terminal sampling loss"
)

test_immediate_readback_precedes_poll_and_qualifies
test_delayed_candidate_qualifies_from_observation_time
test_slow_schedule_only_changes_completion_latency
test_final_discovery_readback_gets_stability_observation
test_ambiguous_and_reused_pid_reset_stability
test_transient_readback_error_resets_candidate
test_watchdog_reports_final_empty_readback
test_final_readback_error_is_unmet_evidence
test_poll_cancellation_is_owned
test_runner_exit_is_terminal_without_poll
test_pre_request_start_is_rejected
test_clock_failure_is_unmet_evidence
test_receipt_failure_is_unmet_evidence
test_cpu_time_parser_supports_ps_formats
test_interval_cpu_uses_cumulative_process_time_delta
test_cpu_interval_failure_distinguishes_live_and_exited_targets

echo "Runtime-topology target checks launch identity and interval CPU evidence."
