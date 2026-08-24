#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LIFECYCLE_PATH="${ROOT_DIR}/scripts/release/lib/dmg-mount-lifecycle.sh"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/release/verify-release-distribution.sh"

if [[ ! -f "${LIFECYCLE_PATH}" ]]; then
  echo "Missing DMG mount lifecycle helper: ${LIFECYCLE_PATH}" >&2
  exit 1
fi

# shellcheck source=scripts/release/lib/dmg-mount-lifecycle.sh
source "${LIFECYCLE_PATH}"

mkdir -p "${ROOT_DIR}/.build-local"
TEST_ROOT="$(/usr/bin/mktemp -d "${ROOT_DIR}/.build-local/dmg-mount-lifecycle-test.XXXXXX")"

cleanup() {
  flowtab_dmg_mount_clear_traps
  /bin/rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_mount_root() {
  local name="$1"
  local mount_root="${TEST_ROOT}/${name}"

  /bin/mkdir -p "${mount_root}"
  printf '%s' "${mount_root}"
}

test_device_is_resolved_from_the_exact_mount_root() (
  local mount_root
  local attach_output
  local resolved_device

  mount_root="$(make_mount_root "parse mount root")"
  attach_output=$'Expected CRC32 $12345678\n'
  attach_output+=$'/dev/disk4          \tGUID_partition_scheme          \t\n'
  attach_output+=$'/dev/disk4s1        \tApple_APFS                     \t\n'
  attach_output+=$'/dev/disk5          \tEF57347C-0000-11AA-AA11-0030654\t\n'
  attach_output+="/dev/disk5s1        "
  attach_output+=$'\t41504653-0000-11AA-AA11-0030654\t'
  attach_output+="${mount_root}"

  resolved_device="$(
    flowtab_dmg_device_for_mount_root \
      "${attach_output}" \
      "${mount_root}"
  )"

  [[ "${resolved_device}" == "/dev/disk5s1" ]] \
    || fail "expected the mounted APFS device, got '${resolved_device}'"
)

test_success_requires_absence_readback_and_removes_mount_root() (
  local mount_root
  local detach_target=""

  mount_root="$(make_mount_root "successful cleanup")"
  flowtab_dmg_detach_device() {
    detach_target="$1"
  }
  flowtab_dmg_mount_table() {
    return 0
  }

  flowtab_dmg_mount_prepare "${mount_root}"
  FLOWTAB_DMG_MOUNT_ATTACHED="true"
  FLOWTAB_DMG_MOUNT_DEVICE="/dev/disk5s1"
  flowtab_dmg_mount_finish

  [[ "${detach_target}" == "/dev/disk5s1" ]] \
    || fail "cleanup did not target the stable mounted device"
  [[ ! -e "${mount_root}" ]] \
    || fail "mount root remained after confirmed device absence"
)

test_detach_failure_is_reported_and_preserves_mount_root() (
  local mount_root
  local moved_mount_root
  local diagnostics_file
  local diagnostics

  mount_root="$(make_mount_root "detach failure")"
  moved_mount_root="${TEST_ROOT}/Trash/community-attempt/baseline-mount"
  diagnostics_file="${TEST_ROOT}/detach-failure.log"
  flowtab_dmg_detach_device() {
    echo "synthetic resource busy" >&2
    return 16
  }
  flowtab_dmg_mount_table() {
    echo "/dev/disk5s1 on ${moved_mount_root} (apfs, local, read-only, nobrowse)"
  }

  flowtab_dmg_mount_prepare "${mount_root}"
  FLOWTAB_DMG_MOUNT_ATTACHED="true"
  FLOWTAB_DMG_MOUNT_DEVICE="/dev/disk5s1"
  if flowtab_dmg_mount_finish 2>"${diagnostics_file}"; then
    fail "detach failure was accepted"
  fi
  diagnostics="$(<"${diagnostics_file}")"

  [[ -d "${mount_root}" ]] \
    || fail "mount root was removed after detach failure"
  [[ "${diagnostics}" == *"detachStatus=16"* ]] \
    || fail "detach status was not reported"
  [[ "${diagnostics}" == *"${moved_mount_root}"* ]] \
    || fail "moved mount readback was not reported"
)

test_present_device_readback_rejects_successful_detach_status() (
  local mount_root
  local diagnostics_file
  local diagnostics

  mount_root="$(make_mount_root "present readback")"
  diagnostics_file="${TEST_ROOT}/present-readback.log"
  flowtab_dmg_detach_device() {
    return 0
  }
  flowtab_dmg_mount_table() {
    echo "/dev/disk5s1 on ${mount_root} (apfs, local, read-only, nobrowse)"
  }

  flowtab_dmg_mount_prepare "${mount_root}"
  FLOWTAB_DMG_MOUNT_ATTACHED="true"
  FLOWTAB_DMG_MOUNT_DEVICE="/dev/disk5s1"
  if flowtab_dmg_mount_finish 2>"${diagnostics_file}"; then
    fail "detach status was accepted while the device remained mounted"
  fi
  diagnostics="$(<"${diagnostics_file}")"

  [[ -d "${mount_root}" ]] \
    || fail "mount root was removed while the device remained present"
  [[ "${diagnostics}" == *"unmetCondition=diskImageAbsent"* ]] \
    || fail "missing device-absence diagnostic"
)

test_mount_readback_error_blocks_cleanup() (
  local mount_root
  local diagnostics_file
  local diagnostics

  mount_root="$(make_mount_root "readback failure")"
  diagnostics_file="${TEST_ROOT}/readback-failure.log"
  flowtab_dmg_detach_device() {
    return 0
  }
  flowtab_dmg_mount_table() {
    echo "synthetic mount-table failure" >&2
    return 3
  }

  flowtab_dmg_mount_prepare "${mount_root}"
  FLOWTAB_DMG_MOUNT_ATTACHED="true"
  FLOWTAB_DMG_MOUNT_DEVICE="/dev/disk5s1"
  if flowtab_dmg_mount_finish 2>"${diagnostics_file}"; then
    fail "mount readback failure was accepted"
  fi
  diagnostics="$(<"${diagnostics_file}")"

  [[ -d "${mount_root}" ]] \
    || fail "mount root was removed without a valid absence readback"
  [[ "${diagnostics}" == *"readbackError=mount status=3"* ]] \
    || fail "mount readback status was not reported"
)

test_missing_device_falls_back_to_the_owned_mount_root() (
  local mount_root
  local detach_target=""

  mount_root="$(make_mount_root "mount-root fallback")"
  flowtab_dmg_detach_device() {
    detach_target="$1"
  }
  flowtab_dmg_mount_table() {
    return 0
  }

  flowtab_dmg_mount_prepare "${mount_root}"
  FLOWTAB_DMG_MOUNT_ATTACHED="true"
  FLOWTAB_DMG_MOUNT_DEVICE=""
  flowtab_dmg_mount_finish

  [[ "${detach_target}" == "${mount_root}" ]] \
    || fail "cleanup did not fall back to the owned mount root"
)

test_pending_attach_uses_mount_readback_before_cleanup() (
  local mount_root
  local detach_target=""
  local readback_state_file
  local readback_count

  mount_root="$(make_mount_root "pending attach")"
  readback_state_file="${TEST_ROOT}/pending-attach-readback-count"
  printf '0\n' > "${readback_state_file}"
  flowtab_dmg_detach_device() {
    detach_target="$1"
  }
  flowtab_dmg_mount_table() {
    readback_count="$(<"${readback_state_file}")"
    readback_count=$((readback_count + 1))
    printf '%s\n' "${readback_count}" > "${readback_state_file}"
    if [[ "${readback_count}" -eq 1 ]]; then
      echo "/dev/disk5s1 on ${mount_root} (apfs, local, read-only, nobrowse)"
    fi
  }

  flowtab_dmg_mount_prepare "${mount_root}"
  flowtab_dmg_mount_will_attach
  flowtab_dmg_mount_finish

  [[ "${detach_target}" == "${mount_root}" ]] \
    || fail "pending attach cleanup did not use its owned mount root"
  readback_count="$(<"${readback_state_file}")"
  [[ "${readback_count}" -eq 2 ]] \
    || fail "pending attach cleanup did not confirm post-detach absence"
)

test_prepare_installs_exit_and_signal_cleanup_traps() (
  local mount_root
  local signal_name
  local trap_definition

  mount_root="$(make_mount_root "signal traps")"
  flowtab_dmg_mount_prepare "${mount_root}"

  for signal_name in EXIT HUP INT TERM; do
    trap_definition="$(trap -p "${signal_name}")"
    [[ "${trap_definition}" == *"flowtab_dmg_mount_"* ]] \
      || fail "missing DMG cleanup trap for ${signal_name}"
  done

  flowtab_dmg_mount_clear_traps
  /bin/rmdir "${mount_root}"
)

test_exit_trap_cleans_mount_and_preserves_failure_status() (
  local mount_root
  local detach_log
  local child_status

  mount_root="$(make_mount_root "exit trap")"
  detach_log="${TEST_ROOT}/exit-trap-detach.log"
  if (
    flowtab_dmg_detach_device() {
      printf '%s\n' "$1" > "${detach_log}"
    }
    flowtab_dmg_mount_table() {
      return 0
    }

    flowtab_dmg_mount_prepare "${mount_root}"
    FLOWTAB_DMG_MOUNT_ATTACHED="true"
    FLOWTAB_DMG_MOUNT_DEVICE="/dev/disk5s1"
    exit 42
  ); then
    fail "exit trap replaced the original failure with success"
  else
    child_status=$?
  fi

  [[ "${child_status}" -eq 42 ]] \
    || fail "exit trap did not preserve status 42"
  [[ "$(<"${detach_log}")" == "/dev/disk5s1" ]] \
    || fail "exit trap did not detach the stable device"
  [[ ! -e "${mount_root}" ]] \
    || fail "exit trap left its mount root behind"
)

test_term_trap_cleans_mount_before_signal_exit() (
  local mount_root
  local detach_log
  local child_status

  mount_root="$(make_mount_root "term trap")"
  detach_log="${TEST_ROOT}/term-trap-detach.log"
  if (
    flowtab_dmg_detach_device() {
      printf '%s\n' "$1" > "${detach_log}"
    }
    flowtab_dmg_mount_table() {
      return 0
    }

    flowtab_dmg_mount_prepare "${mount_root}"
    FLOWTAB_DMG_MOUNT_ATTACHED="true"
    FLOWTAB_DMG_MOUNT_DEVICE="/dev/disk5s1"
    flowtab_dmg_mount_cleanup_on_signal TERM 143
  ); then
    fail "TERM cleanup handler returned success"
  else
    child_status=$?
  fi

  [[ "${child_status}" -eq 143 ]] \
    || fail "TERM cleanup handler did not return signal status 143"
  [[ "$(<"${detach_log}")" == "/dev/disk5s1" ]] \
    || fail "TERM cleanup handler did not detach the stable device"
  [[ ! -e "${mount_root}" ]] \
    || fail "TERM cleanup handler left its mount root behind"
)

test_distribution_verifier_uses_the_shared_lifecycle() (
  /usr/bin/grep -F -q \
    'source "${DMG_MOUNT_LIFECYCLE_PATH}"' \
    "${VERIFY_SCRIPT}" \
    || fail "distribution verifier does not source the lifecycle helper"
  /usr/bin/grep -F -q \
    'flowtab_dmg_mount_record_attach "${ATTACH_OUTPUT}"' \
    "${VERIFY_SCRIPT}" \
    || fail "distribution verifier does not record the stable mounted device"
  /usr/bin/grep -F -q \
    'flowtab_dmg_mount_finish' \
    "${VERIFY_SCRIPT}" \
    || fail "distribution verifier does not require confirmed cleanup"

  if /usr/bin/grep -F -q \
    'hdiutil detach "${MOUNT_ROOT}" -quiet || true' \
    "${VERIFY_SCRIPT}"; then
    fail "distribution verifier still discards detach failure"
  fi
)

test_device_is_resolved_from_the_exact_mount_root
test_success_requires_absence_readback_and_removes_mount_root
test_detach_failure_is_reported_and_preserves_mount_root
test_present_device_readback_rejects_successful_detach_status
test_mount_readback_error_blocks_cleanup
test_missing_device_falls_back_to_the_owned_mount_root
test_pending_attach_uses_mount_readback_before_cleanup
test_prepare_installs_exit_and_signal_cleanup_traps
test_exit_trap_cleans_mount_and_preserves_failure_status
test_term_trap_cleans_mount_before_signal_exit
test_distribution_verifier_uses_the_shared_lifecycle

echo "DMG mount lifecycle requires confirmed device absence across success, failure, and signal cleanup paths."
