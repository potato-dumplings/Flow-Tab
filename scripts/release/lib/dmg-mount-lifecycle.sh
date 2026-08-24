#!/usr/bin/env bash

FLOWTAB_DMG_MOUNT_ROOT=""
FLOWTAB_DMG_MOUNT_DEVICE=""
FLOWTAB_DMG_MOUNT_ATTACHED="false"
FLOWTAB_DMG_MOUNT_LAST_OBSERVATION=""

flowtab_dmg_device_for_mount_root() {
  local attach_output="${1-}"
  local mount_root="${2-}"

  if [[ -z "${attach_output}" || -z "${mount_root}" ]]; then
    return 64
  fi

  /usr/bin/awk -F '\t' -v expected_mount_root="${mount_root}" '
    {
      observed_mount_root = $NF
      sub(/\r$/, "", observed_mount_root)
      if (observed_mount_root != expected_mount_root) {
        next
      }

      device = $1
      sub(/^[[:space:]]+/, "", device)
      sub(/[[:space:]]+$/, "", device)
      print device
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' <<< "${attach_output}"
}

flowtab_dmg_detach_device() {
  /usr/bin/hdiutil detach "$1" -quiet
}

flowtab_dmg_mount_table() {
  /sbin/mount
}

flowtab_dmg_remove_mount_root() {
  /bin/rmdir "$1"
}

flowtab_dmg_mount_readback() {
  local mount_root="$1"
  local device_entry="$2"
  local mount_output=""
  local mount_status=0
  local line=""
  local observation=""

  if mount_output="$(flowtab_dmg_mount_table 2>&1)"; then
    mount_status=0
  else
    mount_status=$?
  fi
  if [[ "${mount_status}" -ne 0 ]]; then
    FLOWTAB_DMG_MOUNT_LAST_OBSERVATION="readbackError=mount status=${mount_status}"
    if [[ -n "${mount_output}" ]]; then
      FLOWTAB_DMG_MOUNT_LAST_OBSERVATION+=$'\n'
      FLOWTAB_DMG_MOUNT_LAST_OBSERVATION+="${mount_output}"
    fi
    return 2
  fi

  while IFS= read -r line; do
    if [[ -n "${device_entry}" && "${line}" == "${device_entry} on "* ]] \
      || [[ "${line}" == *" on ${mount_root} ("* ]]; then
      if [[ -n "${observation}" ]]; then
        observation+=$'\n'
      fi
      observation+="${line}"
    fi
  done <<< "${mount_output}"

  FLOWTAB_DMG_MOUNT_LAST_OBSERVATION="${observation}"
  [[ -z "${observation}" ]]
}

flowtab_dmg_mount_clear_traps() {
  trap - EXIT HUP INT TERM
}

flowtab_dmg_mount_cleanup() {
  local detach_command_target=""
  local detach_status=0
  local readback_status=0

  if [[ -z "${FLOWTAB_DMG_MOUNT_ROOT}" ]]; then
    return 0
  fi

  if [[ "${FLOWTAB_DMG_MOUNT_ATTACHED}" == "pending" ]]; then
    if flowtab_dmg_mount_readback \
      "${FLOWTAB_DMG_MOUNT_ROOT}" \
      "${FLOWTAB_DMG_MOUNT_DEVICE}"; then
      FLOWTAB_DMG_MOUNT_ATTACHED="false"
    else
      readback_status=$?
      if [[ "${readback_status}" -eq 1 ]]; then
        FLOWTAB_DMG_MOUNT_ATTACHED="true"
      else
        echo "Could not determine whether the pending disk image attach completed." >&2
        echo "${FLOWTAB_DMG_MOUNT_LAST_OBSERVATION}" >&2
        return 1
      fi
    fi
  fi

  if [[ "${FLOWTAB_DMG_MOUNT_ATTACHED}" == "true" ]]; then
    # The device remains observable if the mount directory is renamed, so a moved mount cannot be mistaken for absence.
    detach_command_target="${FLOWTAB_DMG_MOUNT_DEVICE:-${FLOWTAB_DMG_MOUNT_ROOT}}"
    if flowtab_dmg_detach_device "${detach_command_target}"; then
      detach_status=0
    else
      detach_status=$?
    fi
    if [[ "${detach_status}" -ne 0 ]]; then
      if flowtab_dmg_mount_readback \
        "${FLOWTAB_DMG_MOUNT_ROOT}" \
        "${FLOWTAB_DMG_MOUNT_DEVICE}"; then
        readback_status=0
      else
        readback_status=$?
      fi
      echo "Could not detach the release disk image." >&2
      echo "detachStatus=${detach_status} detachTarget=${detach_command_target}" >&2
      echo "readbackStatus=${readback_status}" >&2
      if [[ -n "${FLOWTAB_DMG_MOUNT_LAST_OBSERVATION}" ]]; then
        echo "lastObservation:" >&2
        echo "${FLOWTAB_DMG_MOUNT_LAST_OBSERVATION}" >&2
      fi
      return 1
    fi

    if flowtab_dmg_mount_readback \
      "${FLOWTAB_DMG_MOUNT_ROOT}" \
      "${FLOWTAB_DMG_MOUNT_DEVICE}"; then
      readback_status=0
    else
      readback_status=$?
    fi
    if [[ "${readback_status}" -eq 1 ]]; then
      echo "Disk image detach returned success while the mount remained present." >&2
      echo "unmetCondition=diskImageAbsent" >&2
      echo "lastObservation:" >&2
      echo "${FLOWTAB_DMG_MOUNT_LAST_OBSERVATION}" >&2
      return 1
    fi
    if [[ "${readback_status}" -ne 0 ]]; then
      echo "Could not confirm disk image absence after detach." >&2
      echo "${FLOWTAB_DMG_MOUNT_LAST_OBSERVATION}" >&2
      return 1
    fi

    FLOWTAB_DMG_MOUNT_ATTACHED="false"
  fi

  if [[ ! -d "${FLOWTAB_DMG_MOUNT_ROOT}" || -L "${FLOWTAB_DMG_MOUNT_ROOT}" ]]; then
    echo "Owned DMG mount root is unavailable after detach: ${FLOWTAB_DMG_MOUNT_ROOT}" >&2
    return 1
  fi
  if ! flowtab_dmg_remove_mount_root "${FLOWTAB_DMG_MOUNT_ROOT}"; then
    echo "Could not remove the empty DMG mount root: ${FLOWTAB_DMG_MOUNT_ROOT}" >&2
    return 1
  fi

  FLOWTAB_DMG_MOUNT_ROOT=""
  FLOWTAB_DMG_MOUNT_DEVICE=""
  FLOWTAB_DMG_MOUNT_LAST_OBSERVATION=""
}

flowtab_dmg_mount_cleanup_on_exit() {
  local exit_status="$1"

  flowtab_dmg_mount_clear_traps
  if ! flowtab_dmg_mount_cleanup; then
    exit 1
  fi
  exit "${exit_status}"
}

flowtab_dmg_mount_cleanup_on_signal() {
  local signal_name="$1"
  local exit_status="$2"

  flowtab_dmg_mount_clear_traps
  if ! flowtab_dmg_mount_cleanup; then
    echo "DMG cleanup failed while handling ${signal_name}." >&2
    exit 1
  fi
  exit "${exit_status}"
}

flowtab_dmg_mount_prepare() {
  local mount_root="${1-}"

  if [[ -n "${FLOWTAB_DMG_MOUNT_ROOT}" ]]; then
    echo "A DMG mount lifecycle is already active." >&2
    return 1
  fi
  if [[ -z "${mount_root}" || "${mount_root}" != /* || "${mount_root}" == "/" ]]; then
    echo "DMG mount cleanup requires a non-root absolute mount path." >&2
    return 64
  fi
  if [[ ! -d "${mount_root}" || -L "${mount_root}" ]]; then
    echo "DMG mount root must be an owned directory: ${mount_root}" >&2
    return 66
  fi

  FLOWTAB_DMG_MOUNT_ROOT="${mount_root}"
  FLOWTAB_DMG_MOUNT_DEVICE=""
  FLOWTAB_DMG_MOUNT_ATTACHED="false"
  FLOWTAB_DMG_MOUNT_LAST_OBSERVATION=""

  trap 'flowtab_dmg_mount_cleanup_on_exit "$?"' EXIT
  trap 'flowtab_dmg_mount_cleanup_on_signal HUP 129' HUP
  trap 'flowtab_dmg_mount_cleanup_on_signal INT 130' INT
  trap 'flowtab_dmg_mount_cleanup_on_signal TERM 143' TERM
}

flowtab_dmg_mount_will_attach() {
  if [[ -z "${FLOWTAB_DMG_MOUNT_ROOT}" ]]; then
    echo "DMG mount lifecycle was not prepared." >&2
    return 1
  fi
  if [[ "${FLOWTAB_DMG_MOUNT_ATTACHED}" != "false" ]]; then
    echo "DMG mount lifecycle is already attaching or attached." >&2
    return 1
  fi
  # A signal can arrive after hdiutil mounts but before its output is recorded.
  FLOWTAB_DMG_MOUNT_ATTACHED="pending"
}

flowtab_dmg_mount_record_attach() {
  local attach_output="${1-}"
  local device_entry=""

  if [[ -z "${FLOWTAB_DMG_MOUNT_ROOT}" \
    || "${FLOWTAB_DMG_MOUNT_ATTACHED}" != "pending" ]]; then
    echo "DMG attach result arrived outside the prepared lifecycle." >&2
    return 1
  fi
  FLOWTAB_DMG_MOUNT_ATTACHED="true"
  if device_entry="$(
    flowtab_dmg_device_for_mount_root \
      "${attach_output}" \
      "${FLOWTAB_DMG_MOUNT_ROOT}"
  )"; then
    :
  else
    echo "Could not resolve the mounted device for ${FLOWTAB_DMG_MOUNT_ROOT}." >&2
    return 1
  fi
  if [[ "${device_entry}" != /dev/disk* ]]; then
    echo "Unexpected mounted device entry: ${device_entry:-<empty>}" >&2
    return 1
  fi

  FLOWTAB_DMG_MOUNT_DEVICE="${device_entry}"
}

flowtab_dmg_mount_finish() {
  local cleanup_status=0

  if flowtab_dmg_mount_cleanup; then
    cleanup_status=0
  else
    cleanup_status=$?
  fi
  flowtab_dmg_mount_clear_traps
  return "${cleanup_status}"
}
