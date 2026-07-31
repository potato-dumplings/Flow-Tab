#!/usr/bin/env bash

FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION=""
FLOWTAB_PROCESS_EXIT_NOW_SECONDS=0

flowtab_process_exit_pgrep() {
  /usr/bin/pgrep -x "$1"
}

flowtab_process_exit_ps() {
  /bin/ps -p "$1" -o pid=,ppid=,state=,lstart=,command=
}

flowtab_process_exit_readback() {
  local process_name="$1"
  local pids
  local pgrep_status
  local observation=""
  local process_record

  if pids="$(flowtab_process_exit_pgrep "${process_name}" 2>&1)"; then
    pgrep_status=0
  else
    pgrep_status=$?
  fi
  if [[ "${pgrep_status}" -eq 1 ]]; then
    FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION=""
    return
  fi
  if [[ "${pgrep_status}" -ne 0 ]]; then
    FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION="readbackError=pgrep "
    FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION+="status=${pgrep_status} "
    FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION+="output=${pids}"
    return
  fi

  while IFS= read -r pid; do
    if [[ -z "${pid}" ]]; then
      continue
    fi
    process_record="$(flowtab_process_exit_ps "${pid}" 2>/dev/null || true)"
    if [[ -z "${process_record}" ]]; then
      process_record="${pid} identity=unavailable"
    fi
    if [[ -n "${observation}" ]]; then
      observation+=$'\n'
    fi
    observation+="${process_record}"
  done <<< "${pids}"

  FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION="${observation}"
}

flowtab_process_exit_read_clock() {
  FLOWTAB_PROCESS_EXIT_NOW_SECONDS="${SECONDS}"
}

flowtab_process_exit_sleep() {
  /bin/sleep "$1"
}

flowtab_wait_for_process_exit() {
  local process_name="$1"
  local watchdog_seconds="$2"
  local poll_interval_seconds="$3"
  local started_at_seconds

  if [[ -z "${process_name}" ]]; then
    echo "Process-exit observation requires a process name." >&2
    return 2
  fi
  if [[ ! "${watchdog_seconds}" =~ ^[0-9]+$ ]]; then
    echo "Process-exit watchdog must be a non-negative integer." >&2
    return 2
  fi
  if [[ ! "${poll_interval_seconds}" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || [[ "${poll_interval_seconds}" =~ ^0+([.]0+)?$ ]]; then
    echo "Process-exit polling interval must be positive." >&2
    return 2
  fi

  flowtab_process_exit_readback "${process_name}"
  if [[ -z "${FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION}" ]]; then
    return 0
  fi

  flowtab_process_exit_read_clock
  started_at_seconds="${FLOWTAB_PROCESS_EXIT_NOW_SECONDS}"

  while true; do
    flowtab_process_exit_read_clock
    if ((
      FLOWTAB_PROCESS_EXIT_NOW_SECONDS - started_at_seconds
        >= watchdog_seconds
    )); then
      echo "Timed out waiting for process absence." >&2
      echo "unmetCondition=processAbsent processName=${process_name}" >&2
      echo "watchdogSeconds=${watchdog_seconds}" >&2
      echo "lastObservation:" >&2
      echo "${FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION}" >&2
      return 1
    fi

    flowtab_process_exit_sleep "${poll_interval_seconds}"
    flowtab_process_exit_readback "${process_name}"
    if [[ -z "${FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION}" ]]; then
      return 0
    fi
  done
}
