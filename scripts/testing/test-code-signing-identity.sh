#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
IDENTITY_HELPER_PATH="${ROOT_DIR}/scripts/lib/code-signing-identity.sh"
INSTALL_SCRIPT_PATH="${ROOT_DIR}/scripts/testing/install-ui-test-app.sh"
RUN_SCRIPT_PATH="${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh"

# shellcheck source=/dev/null
source "${IDENTITY_HELPER_PATH}"

FIRST_FINGERPRINT="BF86A9CC3D6747BFC760270007FE797C8D0405E6"
SECOND_FINGERPRINT="1BF0E48A99836282230C3A10EAF6ADC83A4AED82"
OTHER_FINGERPRINT="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
TEAM="RF9WCUVKH8"
DUPLICATE_NAME="Apple Development: gobestsoft@qq.com (${TEAM})"
IDENTITY_READBACK="$(printf '%s\n' \
  "  1) ${FIRST_FINGERPRINT} \"${DUPLICATE_NAME}\"" \
  "  2) ${SECOND_FINGERPRINT} \"${DUPLICATE_NAME}\"" \
  "  3) ${OTHER_FINGERPRINT} \"Developer ID Application: Example (OTHERTEAM1)\"" \
  "     3 valid identities found")"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_resolves() {
  local expected="$1"
  local requested="$2"
  local team="$3"
  local readback="$4"
  local actual=""

  actual="$(
    flowtab_resolve_code_sign_identity_from_readback \
      "${requested}" \
      "${team}" \
      "${readback}"
  )" || fail "identity did not resolve requested=${requested} team=${team}"
  [[ "${actual}" == "${expected}" ]] \
    || fail "resolved ${actual}, expected ${expected}"
}

assert_rejected() {
  local requested="$1"
  local team="$2"
  local readback="$3"

  if flowtab_resolve_code_sign_identity_from_readback \
    "${requested}" \
    "${team}" \
    "${readback}" >/dev/null
  then
    fail "unexpected identity requested=${requested} team=${team}"
  fi
}

assert_resolves \
  "${FIRST_FINGERPRINT}" \
  "Apple Development" \
  "${TEAM}" \
  "${IDENTITY_READBACK}"
assert_resolves \
  "${FIRST_FINGERPRINT}" \
  "${DUPLICATE_NAME}" \
  "${TEAM}" \
  "${IDENTITY_READBACK}"
assert_resolves \
  "${SECOND_FINGERPRINT}" \
  "$(printf '%s' "${SECOND_FINGERPRINT}" | /usr/bin/tr '[:upper:]' '[:lower:]')" \
  "${TEAM}" \
  "${IDENTITY_READBACK}"
assert_resolves \
  "${OTHER_FINGERPRINT}" \
  "Developer ID Application: Example (OTHERTEAM1)" \
  "OTHERTEAM1" \
  "${IDENTITY_READBACK}"

assert_rejected "Apple Development" "MISSING123" "${IDENTITY_READBACK}"
assert_rejected "${SECOND_FINGERPRINT}" "OTHERTEAM1" "${IDENTITY_READBACK}"
assert_rejected "Apple Development" "${TEAM}" $'malformed\n0 valid identities found'

for script_path in "${INSTALL_SCRIPT_PATH}" "${RUN_SCRIPT_PATH}"; do
  /usr/bin/grep -Fq 'source "${CODE_SIGNING_IDENTITY_PATH}"' "${script_path}" \
    || fail "missing shared resolver source: ${script_path}"
  /usr/bin/grep -Fq \
    '/usr/bin/codesign --force --deep --sign "${RESOLVED_CODE_SIGN_IDENTITY}"' \
    "${script_path}" \
    || fail "resolved fingerprint does not reach codesign: ${script_path}"
  if /usr/bin/grep -Fq 'resolve_code_sign_identity() {' "${script_path}"; then
    fail "script retained a private identity resolver: ${script_path}"
  fi
  if /usr/bin/grep -Eq '(^|[^_])resolve_code_sign_identity([[:space:]]|$)' "${script_path}"; then
    fail "script retained a private identity-resolver call: ${script_path}"
  fi
  /usr/bin/grep -Fq 'flowtab_resolve_code_sign_identity' "${script_path}" \
    || fail "shared identity resolver is not called: ${script_path}"
done

echo "Code-signing identity contract tests passed."
