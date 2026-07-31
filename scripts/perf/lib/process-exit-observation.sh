#!/usr/bin/env bash

FLOWTAB_PERF_PROCESS_EXIT_CONDITION=""
FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION=""
FLOWTAB_PERF_PROCESS_EXIT_NOW_NS=0
FLOWTAB_PERF_PROCESS_EXIT_MONOTONIC_CLOCK_PATH="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
)/monotonic-clock.sh"

flowtab_perf_process_start_identity() {
  local pid="$1"
  local started_at

  started_at="$(
    LC_ALL=C /bin/ps -p "${pid}" -o lstart= 2>/dev/null \
      | LC_ALL=C /usr/bin/awk '{$1=$1; print}'
  )"
  [[ -n "${started_at}" ]] || return 1
  printf '%s' "${started_at}"
}

flowtab_perf_process_exit_readback() {
  local pid="$1"
  local expected_start_identity="$2"
  local process_record
  local process_state
  local process_start_identity
  local ps_status

  if process_record="$(
    LC_ALL=C /bin/ps \
      -p "${pid}" \
      -o pid=,ppid=,state=,lstart=,command= \
      2>&1
  )"; then
    ps_status=0
  else
    ps_status=$?
  fi
  process_record="$(
    printf '%s\n' "${process_record}" \
      | LC_ALL=C /usr/bin/awk '{$1=$1; print}'
  )"

  if [[ "${ps_status}" -ne 0 || -z "${process_record}" ]]; then
    if /bin/kill -0 "${pid}" 2>/dev/null; then
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="readback_error"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="pid=${pid} "
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION+="readbackError=ps "
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION+="status=${ps_status} "
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION+="output=${process_record}"
    else
      FLOWTAB_PERF_PROCESS_EXIT_CONDITION="exited"
      FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="pid=${pid} state=absent"
    fi
    return
  fi

  process_state="$(
    printf '%s\n' "${process_record}" | LC_ALL=C /usr/bin/awk '{print $3}'
  )"
  process_start_identity="$(
    printf '%s\n' "${process_record}" \
      | LC_ALL=C /usr/bin/awk '{print $4, $5, $6, $7, $8}'
  )"
  FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="${process_record}"

  if [[ "${process_state}" == Z* ]]; then
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="exited"
  elif [[ -n "${expected_start_identity}" ]] \
    && [[ "${process_start_identity}" != "${expected_start_identity}" ]]; then
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="identity_changed"
  else
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="running"
  fi
}

flowtab_perf_process_exit_read_clock() {
  local now_ns

  if ! now_ns="$("${FLOWTAB_PERF_PROCESS_EXIT_MONOTONIC_CLOCK_PATH}")" \
    || [[ ! "${now_ns}" =~ ^[0-9]+$ ]]; then
    FLOWTAB_PERF_PROCESS_EXIT_CONDITION="clock_error"
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION="monotonicClockError="
    FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION+="${FLOWTAB_PERF_PROCESS_EXIT_MONOTONIC_CLOCK_PATH}"
    return 1
  fi
  FLOWTAB_PERF_PROCESS_EXIT_NOW_NS="${now_ns}"
}

flowtab_perf_process_exit_sleep() {
  /bin/sleep "$1"
}

flowtab_perf_report_process_exit_failure() {
  local pid="$1"
  local expected_start_identity="$2"
  local watchdog_milliseconds="$3"
  local reason="${4:-watchdog}"

  case "${reason}" in
    identity_changed)
      echo "Child process identity changed while waiting for exit." >&2
      echo "unmetCondition=processIdentityStable pid=${pid}" >&2
      ;;
    observation_error)
      echo "Child process exit observation failed." >&2
      echo "unmetCondition=processExited pid=${pid}" >&2
      ;;
    *)
      echo "Timed out waiting for child process exit." >&2
      echo "unmetCondition=processExited pid=${pid}" >&2
      ;;
  esac
  echo "expectedStartIdentity=${expected_start_identity:-unavailable}" >&2
  echo "watchdogMilliseconds=${watchdog_milliseconds}" >&2
  echo "lastCondition=${FLOWTAB_PERF_PROCESS_EXIT_CONDITION}" >&2
  echo "lastObservation:" >&2
  echo "${FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION}" >&2
}

flowtab_perf_wait_for_process_exit() {
  local pid="$1"
  local expected_start_identity="$2"
  local watchdog_milliseconds="$3"
  local poll_interval_seconds="$4"
  local deadline_ns
  local started_at_ns

  if [[ ! "${pid}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Process-exit observation requires a positive PID." >&2
    return 2
  fi
  if [[ ! "${watchdog_milliseconds}" =~ ^[0-9]+$ ]]; then
    echo "Process-exit watchdog must be non-negative milliseconds." >&2
    return 2
  fi
  if [[ ! "${poll_interval_seconds}" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || [[ "${poll_interval_seconds}" =~ ^0+([.]0+)?$ ]]; then
    echo "Process-exit polling interval must be positive." >&2
    return 2
  fi

  flowtab_perf_process_exit_readback "${pid}" "${expected_start_identity}"
  case "${FLOWTAB_PERF_PROCESS_EXIT_CONDITION}" in
    exited)
      return 0
      ;;
    identity_changed)
      flowtab_perf_report_process_exit_failure \
        "${pid}" \
        "${expected_start_identity}" \
        "${watchdog_milliseconds}" \
        "identity_changed"
      return 2
      ;;
  esac

  if ! flowtab_perf_process_exit_read_clock; then
    flowtab_perf_report_process_exit_failure \
      "${pid}" \
      "${expected_start_identity}" \
      "${watchdog_milliseconds}" \
      "observation_error"
    return 2
  fi
  started_at_ns="${FLOWTAB_PERF_PROCESS_EXIT_NOW_NS}"
  deadline_ns=$((started_at_ns + watchdog_milliseconds * 1000000))

  while true; do
    if ! flowtab_perf_process_exit_read_clock; then
      flowtab_perf_report_process_exit_failure \
        "${pid}" \
        "${expected_start_identity}" \
        "${watchdog_milliseconds}" \
        "observation_error"
      return 2
    fi
    if ((FLOWTAB_PERF_PROCESS_EXIT_NOW_NS >= deadline_ns)); then
      flowtab_perf_process_exit_readback "${pid}" "${expected_start_identity}"
      if [[ "${FLOWTAB_PERF_PROCESS_EXIT_CONDITION}" == "exited" ]]; then
        return 0
      fi
      flowtab_perf_report_process_exit_failure \
        "${pid}" \
        "${expected_start_identity}" \
        "${watchdog_milliseconds}"
      return 1
    fi

    if ! flowtab_perf_process_exit_sleep "${poll_interval_seconds}"; then
      echo "Process-exit observation was cancelled." >&2
      echo "lastObservation:" >&2
      echo "${FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION}" >&2
      return 130
    fi
    flowtab_perf_process_exit_readback "${pid}" "${expected_start_identity}"
    case "${FLOWTAB_PERF_PROCESS_EXIT_CONDITION}" in
      exited)
        return 0
        ;;
      identity_changed)
        flowtab_perf_report_process_exit_failure \
          "${pid}" \
          "${expected_start_identity}" \
          "${watchdog_milliseconds}" \
          "identity_changed"
        return 2
        ;;
    esac
  done
}
