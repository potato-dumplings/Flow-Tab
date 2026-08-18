#!/usr/bin/env bash

flowtab_code_signing_fingerprint_is_valid() {
  local fingerprint="${1-}"

  [[ "${#fingerprint}" -eq 40 && "${fingerprint}" != *[!0-9A-Fa-f]* ]]
}

flowtab_resolve_code_sign_identity_from_readback() {
  local requested="${1-}"
  local team="${2-}"
  local identities="${3-}"
  local line=""
  local fingerprint=""
  local identity=""
  local normalized_requested=""

  if flowtab_code_signing_fingerprint_is_valid "${requested}"; then
    normalized_requested="$(printf '%s' "${requested}" | /usr/bin/tr '[:lower:]' '[:upper:]')"
  fi

  while IFS= read -r line; do
    fingerprint="${line#*) }"
    fingerprint="${fingerprint%% *}"
    identity="${line#*\"}"
    identity="${identity%%\"*}"

    if ! flowtab_code_signing_fingerprint_is_valid "${fingerprint}"; then
      continue
    fi
    if [[ "${identity}" == "${line}" || -z "${identity}" ]]; then
      continue
    fi
    if [[ -n "${team}" && "${identity}" != *"(${team})" ]]; then
      continue
    fi

    if [[ -n "${normalized_requested}" ]]; then
      fingerprint="$(printf '%s' "${fingerprint}" | /usr/bin/tr '[:lower:]' '[:upper:]')"
      [[ "${fingerprint}" == "${normalized_requested}" ]] || continue
    elif [[ -n "${requested}" && "${requested}" != "Apple Development" ]]; then
      [[ "${identity}" == "${requested}" ]] || continue
    elif [[ "${identity}" != Apple\ Development:* ]]; then
      continue
    fi

    printf '%s' "${fingerprint}"
    return 0
  done <<< "${identities}"

  return 1
}

flowtab_resolve_code_sign_identity() {
  local requested="${1-}"
  local team="${2-}"
  local identities=""

  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  flowtab_resolve_code_sign_identity_from_readback \
    "${requested}" \
    "${team}" \
    "${identities}"
}
