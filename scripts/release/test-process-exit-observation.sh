#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROCESS_EXIT_OBSERVATION_PATH="${ROOT_DIR}/scripts/release/lib/process-exit-observation.sh"
RELEASE_INSTALL_PATH="${ROOT_DIR}/scripts/release/release-install.sh"

# shellcheck source=scripts/release/lib/process-exit-observation.sh
source "${PROCESS_EXIT_OBSERVATION_PATH}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test_initial_readback_can_resolve_without_polling() (
  local readback_count=0
  local clock_count=0
  local sleep_count=0

  flowtab_process_exit_readback() {
    readback_count=$((readback_count + 1))
    FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION=""
  }
  flowtab_process_exit_read_clock() {
    clock_count=$((clock_count + 1))
    FLOWTAB_PROCESS_EXIT_NOW_SECONDS=0
  }
  flowtab_process_exit_sleep() {
    sleep_count=$((sleep_count + 1))
  }

  flowtab_wait_for_process_exit "FlowTab" 10 0.1

  [[ "${readback_count}" -eq 1 ]] \
    || fail "expected one immediate readback"
  [[ "${clock_count}" -eq 0 ]] \
    || fail "clock should not run after immediate satisfaction"
  [[ "${sleep_count}" -eq 0 ]] \
    || fail "polling should not start after immediate satisfaction"
)

test_polling_resolves_only_from_absence_readback() (
  local readback_count=0
  local sleep_count=0
  local observed_intervals=""

  flowtab_process_exit_readback() {
    readback_count=$((readback_count + 1))
    if [[ "${readback_count}" -lt 3 ]]; then
      FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION="${readback_count} 1 S "
      FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION+="Thu Jul 31 20:00:00 2026 "
      FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION+="/Applications/Flow Tab.app/FlowTab"
    else
      FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION=""
    fi
  }
  flowtab_process_exit_read_clock() {
    FLOWTAB_PROCESS_EXIT_NOW_SECONDS=4
  }
  flowtab_process_exit_sleep() {
    sleep_count=$((sleep_count + 1))
    observed_intervals+="${1},"
  }

  flowtab_wait_for_process_exit "FlowTab" 10 0.125

  [[ "${readback_count}" -eq 3 ]] \
    || fail "expected two pending readbacks and one absence readback"
  [[ "${sleep_count}" -eq 2 ]] \
    || fail "expected one named poll between each pending readback"
  [[ "${observed_intervals}" == "0.125,0.125," ]] \
    || fail "unexpected polling intervals: ${observed_intervals}"
)

test_watchdog_reports_last_observed_process() (
  local readback_count=0
  local clock_count=0
  local sleep_count=0
  local diagnostics
  local diagnostics_file

  diagnostics_file="$(mktemp -t flowtab-process-exit-diagnostics)"
  trap 'rm -f "${diagnostics_file}"' EXIT

  flowtab_process_exit_readback() {
    readback_count=$((readback_count + 1))
    FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION="${readback_count} 1 S "
    FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION+="Thu Jul 31 20:00:00 2026 "
    FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION+="/Applications/Flow Tab.app/FlowTab"
  }
  flowtab_process_exit_read_clock() {
    clock_count=$((clock_count + 1))
    if [[ "${clock_count}" -eq 1 ]]; then
      FLOWTAB_PROCESS_EXIT_NOW_SECONDS=7
    else
      FLOWTAB_PROCESS_EXIT_NOW_SECONDS=17
    fi
  }
  flowtab_process_exit_sleep() {
    sleep_count=$((sleep_count + 1))
  }

  if flowtab_wait_for_process_exit \
    "FlowTab" \
    10 \
    0.1 \
    2>"${diagnostics_file}"; then
    fail "watchdog should fail while the process remains present"
  fi
  diagnostics="$(<"${diagnostics_file}")"

  [[ "${readback_count}" -eq 1 ]] \
    || fail "watchdog should report the latest initial readback"
  [[ "${sleep_count}" -eq 0 ]] \
    || fail "expired watchdog should not schedule another poll"
  [[ "${diagnostics}" == *"unmetCondition=processAbsent"* ]] \
    || fail "missing unmet-condition diagnostic"
  [[ "${diagnostics}" == *"processName=FlowTab"* ]] \
    || fail "missing exact process-name diagnostic"
  [[ "${diagnostics}" == *"/Applications/Flow Tab.app/FlowTab"* ]] \
    || fail "missing last process identity readback"
)

test_readback_error_remains_unmet_evidence() (
  local clock_count=0
  local diagnostics
  local diagnostics_file
  local sleep_count=0

  diagnostics_file="$(mktemp -t flowtab-process-exit-readback-error)"
  trap 'rm -f "${diagnostics_file}"' EXIT

  flowtab_process_exit_pgrep() {
    echo "synthetic process-list failure" >&2
    return 3
  }
  flowtab_process_exit_read_clock() {
    clock_count=$((clock_count + 1))
    if [[ "${clock_count}" -eq 1 ]]; then
      FLOWTAB_PROCESS_EXIT_NOW_SECONDS=21
    else
      FLOWTAB_PROCESS_EXIT_NOW_SECONDS=31
    fi
  }
  flowtab_process_exit_sleep() {
    sleep_count=$((sleep_count + 1))
  }

  if flowtab_wait_for_process_exit \
    "FlowTab" \
    10 \
    0.1 \
    2>"${diagnostics_file}"; then
    fail "a process-list readback error must not establish process absence"
  fi
  diagnostics="$(<"${diagnostics_file}")"

  [[ "${sleep_count}" -eq 0 ]] \
    || fail "expired readback-error watchdog should not schedule a poll"
  [[ "${diagnostics}" == *"readbackError=pgrep status=3"* ]] \
    || fail "missing process-list readback status"
  [[ "${diagnostics}" == *"synthetic process-list failure"* ]] \
    || fail "missing process-list readback output"
)

test_zero_polling_interval_is_rejected() (
  local readback_count=0

  flowtab_process_exit_readback() {
    readback_count=$((readback_count + 1))
  }

  if flowtab_wait_for_process_exit "FlowTab" 10 0.00 2>/dev/null; then
    fail "a zero polling interval must be rejected"
  fi
  [[ "${readback_count}" -eq 0 ]] \
    || fail "invalid policy must fail before process readback"
)

test_real_readback_accepts_exact_absence() (
  flowtab_process_exit_readback "FlowTabAbsentProcess$$"

  [[ -z "${FLOWTAB_PROCESS_EXIT_LAST_OBSERVATION}" ]] \
    || fail "unexpected process matched the exact absent-process readback"
)

test_release_install_wires_both_process_boundaries() (
  local wait_call_count

  wait_call_count="$(
    /usr/bin/grep -c \
      "flowtab_wait_for_process_exit" \
      "${RELEASE_INSTALL_PATH}"
  )"
  [[ "${wait_call_count}" -eq 2 ]] \
    || fail "release install must observe exit after termination and before removal"

  /usr/bin/awk '
    /pkill -x/ {
      termination = NR
    }
    /flowtab_wait_for_process_exit/ {
      if (first_wait == 0) {
        first_wait = NR
      } else {
        second_wait = NR
      }
    }
    /rm -rf "\$\{INSTALL_PATH\}"/ {
      removal = NR
    }
    END {
      valid = termination > 0
      valid = valid && termination < first_wait
      valid = valid && first_wait < second_wait
      valid = valid && second_wait < removal
      if (valid) {
        exit 0
      }
      exit 1
    }
  ' "${RELEASE_INSTALL_PATH}" \
    || fail "process-exit evidence must precede installed-app removal"

  if /usr/bin/grep -E -q \
    '^[[:space:]]*sleep[[:space:]]+1([[:space:]]|$)' \
    "${RELEASE_INSTALL_PATH}"; then
    fail "release install still contains the fixed one-second exit inference"
  fi
)

test_release_install_reissues_exit_request_before_removal() (
  local request_call_count

  request_call_count="$(
    /usr/bin/grep -E -c \
      '^[[:space:]]*request_flowtab_process_exit[[:space:]]*$' \
      "${RELEASE_INSTALL_PATH}" \
      || true
  )"
  [[ "${request_call_count}" -eq 2 ]] \
    || fail "release install must request exit before both process-absence waits"

  /usr/bin/awk '
    /^[[:space:]]*request_flowtab_process_exit[[:space:]]*$/ {
      if (first_request == 0) {
        first_request = NR
      } else {
        second_request = NR
      }
    }
    /flowtab_wait_for_process_exit/ {
      if (first_wait == 0) {
        first_wait = NR
      } else {
        second_wait = NR
      }
    }
    /rm -rf "\$\{INSTALL_PATH\}"/ {
      removal = NR
    }
    END {
      valid = first_request > 0
      valid = valid && first_request < first_wait
      valid = valid && first_wait < second_request
      valid = valid && second_request < second_wait
      valid = valid && second_wait < removal
      exit valid ? 0 : 1
    }
  ' "${RELEASE_INSTALL_PATH}" \
    || fail "each exit request and absence readback must precede app removal"
)

test_initial_readback_can_resolve_without_polling
test_polling_resolves_only_from_absence_readback
test_watchdog_reports_last_observed_process
test_readback_error_remains_unmet_evidence
test_zero_polling_interval_is_rejected
test_real_readback_accepts_exact_absence
test_release_install_wires_both_process_boundaries
test_release_install_reissues_exit_request_before_removal

echo "Release process-exit observation checks immediate, conditional, and watchdog evidence."
